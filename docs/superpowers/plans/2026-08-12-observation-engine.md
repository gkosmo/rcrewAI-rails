# Observation Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat `ExecutionLog` with a span-tree observation engine that supports deep trace debugging, cost/performance rollups, and live monitoring.

**Architecture:** Three isolated layers — a Collector that translates `RCrewAI::Events` into spans, two storage tables (`rcrewai_spans`, `rcrewai_span_events`) plus denormalized rollups on `rcrewai_executions`, and dashboard views that read them. Prerequisite: an upstream `rcrewAI` fix threading the stream sink from `Crew` through `Task` to `Agent#execute_task`.

**Tech Stack:** Ruby 3.x, Rails 7 engine, RSpec + factory_bot, Combustion dummy app, Turbo Streams, SQLite (test) / host DB (production).

**Spec:** `docs/superpowers/specs/2026-08-12-observation-engine-design.md`

---

## Critical Context for the Implementer

**Two repositories are involved:**
- `/Users/gkosmo/code/gkosmo/rcrewAI` — the upstream gem (Tasks 1–2). A path dependency, so edits are picked up immediately.
- `/Users/gkosmo/code/gkosmo/rcrewAI-rails` — this Rails engine (Tasks 3–14).

**Migrations must be written in THREE places or tests will fail mysteriously:**
1. `db/migrate/0NN_*.rb` — the real migration for host apps that already installed the engine.
2. `lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb` — for fresh installs.
3. `spec/internal/db/schema.rb` — the Combustion dummy-app schema used by the test suite. Note `force: true` on every `create_table` here and no `add_index` inside the create block.

The header comment in `spec/internal/db/schema.rb` states this sync requirement.

**Running tests:** `bundle exec rspec` from the repo root. Model/job specs need `require "rails_helper"`; pure unit specs need only `require "spec_helper"`. `rails_helper.rb` stubs `RCrewAI::LLMClient.for_provider` globally, so no API keys are needed.

**Event vocabulary** (from `rcrewai/lib/rcrewai/events.rb`) — every event carries `type`, `timestamp`, `agent`, `iteration`:
- `IterationStart(iteration_index)` / `IterationEnd(finish_reason)`
- `ToolCallStart(tool, args, call_id)` / `ToolCallResult(tool, call_id, result, duration_ms)` / `ToolCallError(tool, call_id, error)`
- `TextDelta(text)` / `TextDone(text)` / `Thinking(text)`
- `Usage(prompt_tokens, completion_tokens, total_tokens, cost_usd)`
- `Error(error)`

---

## File Structure

**Upstream (`rcrewAI`):**
| File | Responsibility |
|---|---|
| `lib/rcrewai/task.rb` | Gains `attr_accessor :stream_sink`; passes it to `agent.execute_task` |
| `lib/rcrewai/crew.rb` | Assigns `@stream_sink` onto each task before execution |
| `lib/rcrewai/process.rb` | Passes `crew.stream_sink` at its two direct `execute_task` call sites |
| `spec/stream_sink_threading_spec.rb` | Regression test for the wiring bug |

**Engine (`rcrewai-rails`):**
| File | Responsibility |
|---|---|
| `app/models/rcrewai/rails/span.rb` | Span record: tree structure, status transitions, scopes |
| `app/models/rcrewai/rails/span_event.rb` | Point-in-time occurrence within a span |
| `lib/rcrewai/rails/observation/collector.rb` | Events → spans. Owns ALL rcrewai event knowledge. |
| `lib/rcrewai/rails/observation/span_stack.rb` | Thread-safe open-span bookkeeping + `call_id` correlation |
| `lib/rcrewai/rails/observation/writer.rb` | Buffering, flushing, error isolation |
| `lib/rcrewai/rails/observation/rollup.rb` | Denormalized totals on `Execution` |
| `lib/rcrewai/rails/configuration.rb` | New `observation_*` settings |
| `app/controllers/rcrewai/rails/observations_controller.rb` | Trace + cost/perf surfaces |
| `app/views/rcrewai/rails/observations/` | Waterfall, span detail, cost views |
| `lib/tasks/rcrewai_observation.rake` | `rcrewai:observation:prune` |

**Rationale:** `Collector` is deliberately split from `SpanStack` and `Writer`. The stack logic (correlation, orphan handling) and the write logic (buffering, error isolation) are each independently tricky, and separating them keeps each unit-testable without a database.

---

## Task 1: Upstream — thread the stream sink to agents

**Repo:** `/Users/gkosmo/code/gkosmo/rcrewAI`

**Files:**
- Modify: `lib/rcrewai/task.rb:11-13` (attr), `lib/rcrewai/task.rb:221`
- Modify: `lib/rcrewai/crew.rb:62-75`
- Modify: `lib/rcrewai/process.rb:354`, `lib/rcrewai/process.rb:424`
- Test: `spec/stream_sink_threading_spec.rb`

**Background:** `Crew#execute` builds `@stream_sink` (`crew.rb:66`) and never delivers it. The chain is `Crew#execute` → `execute_sync` → `Process::Sequential#execute` → `task.execute` (`process.rb:37`) → `agent.execute_task(self)` (`task.rb:221`). `Task` sits in the middle with no sink parameter, so the sink dies there. `Agent#execute_task(task, stream:)` already accepts and forwards a sink to the runner, which emits the full event set — so only the delivery is missing.

- [ ] **Step 1: Write the failing test**

Create `spec/stream_sink_threading_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'stream sink threading' do
  let(:fake_llm) do
    instance_double('LLMClient').tap do |llm|
      allow(llm).to receive(:chat).and_return(
        content: 'FINAL_ANSWER[done]',
        finish_reason: :stop,
        usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 }
      )
      allow(llm).to receive(:supports_native_tools?).and_return(false)
    end
  end

  before { allow(RCrewAI::LLMClient).to receive(:for_provider).and_return(fake_llm) }

  it 'delivers agent-level events to a sink passed to crew.execute' do
    crew  = RCrewAI::Crew.new('observed')
    agent = RCrewAI::Agent.new(name: 'writer', role: 'Writer', goal: 'Write', backstory: 'A writer')
    task  = RCrewAI::Task.new(
      name: 'write', description: 'Write a line', expected_output: 'A line', agent: agent
    )
    crew.add_agent(agent)
    crew.add_task(task)

    received = []
    crew.execute(stream: ->(event) { received << event })

    expect(received).not_to be_empty,
      'sink received no events — the stream sink is not reaching Agent#execute_task'
    expect(received.map { |e| e.class.name.split('::').last })
      .to include('IterationStart', 'IterationEnd')
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/gkosmo/code/gkosmo/rcrewAI && bundle exec rspec spec/stream_sink_threading_spec.rb -v`
Expected: FAIL — "sink received no events — the stream sink is not reaching Agent#execute_task"

- [ ] **Step 3: Add the accessor to Task**

In `lib/rcrewai/task.rb`, add `stream_sink` to the existing `attr_accessor` on line 13:

```ruby
    attr_accessor :result, :status, :start_time, :end_time, :execution_time, :stream_sink
```

- [ ] **Step 4: Pass the sink from Task to Agent**

In `lib/rcrewai/task.rb:221`, inside `run_agent_with_output_processing`, change:

```ruby
        raw = extract_content(agent.execute_task(self))
```

to:

```ruby
        raw = extract_content(agent.execute_task(self, stream: @stream_sink))
```

- [ ] **Step 5: Assign the sink onto tasks in Crew#execute**

In `lib/rcrewai/crew.rb`, in `execute`, after the `@stream_sink` assignment (line 66) and before `run_before_hooks`:

```ruby
      @stream_sink = sinks.empty? ? nil : RCrewAI::Events.fan_out(sinks)
      @tasks.each { |t| t.stream_sink = @stream_sink }
```

- [ ] **Step 6: Run test to verify it passes**

Run: `cd /Users/gkosmo/code/gkosmo/rcrewAI && bundle exec rspec spec/stream_sink_threading_spec.rb -v`
Expected: PASS

- [ ] **Step 7: Cover the delegated and consensual paths**

`Process` calls `execute_task` directly at two sites, bypassing `Task#execute`. `Process::Base` exposes `crew` (`process.rb:6`), so read the sink from there.

`lib/rcrewai/process.rb:354` — change:

```ruby
        agent.execute_task(enhanced_task)
```

to:

```ruby
        agent.execute_task(enhanced_task, stream: crew.stream_sink)
```

`lib/rcrewai/process.rb:424` — change:

```ruby
          content = extract_content(agent.execute_task(task))
```

to:

```ruby
          content = extract_content(agent.execute_task(task, stream: crew.stream_sink))
```

- [ ] **Step 8: Run the full upstream suite**

Run: `cd /Users/gkosmo/code/gkosmo/rcrewAI && bundle exec rspec`
Expected: PASS, no regressions.

- [ ] **Step 9: Commit**

```bash
cd /Users/gkosmo/code/gkosmo/rcrewAI
git add lib/rcrewai/task.rb lib/rcrewai/crew.rb lib/rcrewai/process.rb spec/stream_sink_threading_spec.rb
git commit -m "fix: thread crew stream sink through to agent execution

Crew#execute built @stream_sink but never delivered it to
Agent#execute_task, so no agent-level events reached subscribers."
```

---

## Task 2: Upstream — verify async paths deliver events

**Repo:** `/Users/gkosmo/code/gkosmo/rcrewAI`

**Files:**
- Test: `spec/stream_sink_threading_spec.rb` (add to existing file)

**Background:** `AsyncExecutor#execute_task_with_monitoring` (`async_executor.rb:165`) calls `task.execute` on a worker thread. Since Task now carries its own sink, this should already work — this task proves it, and proves the sink is safe to call from multiple threads.

- [ ] **Step 1: Write the failing test**

Append to `spec/stream_sink_threading_spec.rb`, inside the top-level `describe`:

```ruby
  it 'delivers events from tasks executed on async worker threads' do
    crew = RCrewAI::Crew.new('async-observed')
    2.times do |i|
      agent = RCrewAI::Agent.new(
        name: "writer#{i}", role: 'Writer', goal: 'Write', backstory: 'A writer'
      )
      crew.add_agent(agent)
      crew.add_task(
        RCrewAI::Task.new(
          name: "write#{i}", description: 'Write a line',
          expected_output: 'A line', agent: agent
        )
      )
    end

    mutex    = Mutex.new
    received = []
    crew.execute(async: true, stream: ->(e) { mutex.synchronize { received << e } })

    expect(received).not_to be_empty
    expect(received.map(&:agent).uniq.compact.size).to be >= 1
  end
```

- [ ] **Step 2: Run the test**

Run: `cd /Users/gkosmo/code/gkosmo/rcrewAI && bundle exec rspec spec/stream_sink_threading_spec.rb -v`
Expected: PASS (Task 1's fix should already cover this).

If it FAILS, the async path constructs or copies tasks in a way that drops `stream_sink`. Fix by assigning the sink inside `AsyncExecutor#execute_task_with_monitoring` before `task.execute`:

```ruby
        task.stream_sink ||= @stream_sink
```

and thread `@stream_sink` into `AsyncExecutor#initialize` from the three `executor.execute_tasks_async` call sites (`crew.rb:247`, `crew.rb:289`, `crew.rb:327`) via `AsyncExecutor.new(stream_sink: @stream_sink, **options)`.

- [ ] **Step 3: Commit**

```bash
cd /Users/gkosmo/code/gkosmo/rcrewAI
git add spec/stream_sink_threading_spec.rb
git commit -m "test: cover stream sink delivery on async execution paths"
```

---

## Task 3: Span and SpanEvent migrations

**Repo:** `rcrewai-rails` (all remaining tasks)

**Files:**
- Create: `db/migrate/010_create_rcrewai_spans.rb`
- Modify: `lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb` (append before final `end`)
- Modify: `spec/internal/db/schema.rb` (append before final `end`)

- [ ] **Step 1: Write the migration**

Create `db/migrate/010_create_rcrewai_spans.rb`:

```ruby
class CreateRcrewaiSpans < ActiveRecord::Migration[7.0]
  def change
    create_table :rcrewai_spans do |t|
      t.references :execution, null: false, foreign_key: { to_table: :rcrewai_executions }
      t.bigint :parent_span_id
      t.string :trace_id, null: false
      t.string :kind, null: false
      t.string :name, null: false
      t.string :status, null: false, default: "running"
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.integer :duration_ms
      t.integer :prompt_tokens
      t.integer :completion_tokens
      t.integer :total_tokens
      t.decimal :cost_usd, precision: 12, scale: 6
      t.text :attributes_json
      t.integer :sequence, null: false

      t.timestamps
    end

    add_index :rcrewai_spans, :parent_span_id
    add_index :rcrewai_spans, :trace_id
    add_index :rcrewai_spans, :kind
    add_index :rcrewai_spans, :status
    add_index :rcrewai_spans, %i[execution_id sequence]

    create_table :rcrewai_span_events do |t|
      t.references :span, null: false, foreign_key: { to_table: :rcrewai_spans }
      t.string :level, null: false, default: "info"
      t.string :name, null: false
      t.text :details
      t.datetime :timestamp, null: false

      t.timestamps
    end

    add_index :rcrewai_span_events, :level
    add_index :rcrewai_span_events, :timestamp
  end
end
```

**Note:** the column is `attributes_json`, NOT `attributes` — `attributes` is a reserved ActiveRecord method and would break the model. It is exposed as `attributes_hash` in Task 4.

- [ ] **Step 2: Add rollup columns to executions**

Create `db/migrate/011_add_observation_rollups_to_rcrewai_executions.rb`:

```ruby
class AddObservationRollupsToRcrewaiExecutions < ActiveRecord::Migration[7.0]
  def change
    add_column :rcrewai_executions, :total_cost_usd, :decimal, precision: 12, scale: 6
    add_column :rcrewai_executions, :total_tokens, :integer
    add_column :rcrewai_executions, :span_count, :integer, default: 0, null: false
    add_column :rcrewai_executions, :error_count, :integer, default: 0, null: false
  end
end
```

- [ ] **Step 3: Mirror into the install template**

In `lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb`, add the four rollup columns to the existing `create_table :rcrewai_executions` block (after `t.string :batch_id`):

```ruby
      t.decimal :total_cost_usd, precision: 12, scale: 6
      t.integer :total_tokens
      t.integer :span_count, default: 0, null: false
      t.integer :error_count, default: 0, null: false
```

Then append both new `create_table` blocks and their `add_index` calls (copied verbatim from Step 1) before the final `end` of the `change` method.

- [ ] **Step 4: Mirror into the Combustion schema**

In `spec/internal/db/schema.rb`, add the same four rollup columns to `create_table :rcrewai_executions`, then append before the final `end`:

```ruby
  create_table :rcrewai_spans, force: true do |t|
    t.references :execution, null: false, foreign_key: { to_table: :rcrewai_executions }
    t.bigint :parent_span_id
    t.string :trace_id, null: false
    t.string :kind, null: false
    t.string :name, null: false
    t.string :status, null: false, default: "running"
    t.datetime :started_at, null: false
    t.datetime :ended_at
    t.integer :duration_ms
    t.integer :prompt_tokens
    t.integer :completion_tokens
    t.integer :total_tokens
    t.decimal :cost_usd, precision: 12, scale: 6
    t.text :attributes_json
    t.integer :sequence, null: false
    t.timestamps
  end
  add_index :rcrewai_spans, :parent_span_id
  add_index :rcrewai_spans, :trace_id
  add_index :rcrewai_spans, :kind
  add_index :rcrewai_spans, :status
  add_index :rcrewai_spans, %i[execution_id sequence]

  create_table :rcrewai_span_events, force: true do |t|
    t.references :span, null: false, foreign_key: { to_table: :rcrewai_spans }
    t.string :level, null: false, default: "info"
    t.string :name, null: false
    t.text :details
    t.datetime :timestamp, null: false
    t.timestamps
  end
  add_index :rcrewai_span_events, :level
  add_index :rcrewai_span_events, :timestamp
```

- [ ] **Step 5: Verify the schema loads**

Run: `bundle exec rspec spec/models/crew_spec.rb`
Expected: PASS — proves the dummy schema still loads cleanly.

- [ ] **Step 6: Commit**

```bash
git add db/migrate/010_create_rcrewai_spans.rb db/migrate/011_add_observation_rollups_to_rcrewai_executions.rb lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb spec/internal/db/schema.rb
git commit -m "feat: add spans, span_events tables and execution rollup columns"
```

---

## Task 4: Span model

**Files:**
- Create: `app/models/rcrewai/rails/span.rb`
- Test: `spec/models/span_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/models/span_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe RcrewAI::Rails::Span do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "c") }
  let(:execution) { crew.executions.create!(status: "running", started_at: Time.current) }

  def build_span(**attrs)
    described_class.create!(
      { execution: execution, trace_id: "t1", kind: "agent",
        name: "writer", started_at: Time.current, sequence: 1 }.merge(attrs)
    )
  end

  it "defaults to running status" do
    expect(build_span.status).to eq("running")
  end

  it "rejects an unknown kind" do
    expect { build_span(kind: "nonsense") }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "stores and reads attributes as a hash" do
    span = build_span(attributes_hash: { model: "gpt-4", temperature: 0.7 })
    expect(span.reload.attributes_hash).to eq("model" => "gpt-4", "temperature" => 0.7)
  end

  it "returns an empty hash when attributes are absent" do
    expect(build_span.attributes_hash).to eq({})
  end

  it "computes duration_ms on finish" do
    started = Time.current
    span = build_span(started_at: started)
    span.finish!(status: "ok", ended_at: started + 1.5)
    expect(span.duration_ms).to eq(1500)
    expect(span.status).to eq("ok")
  end

  it "nests children under parents" do
    parent = build_span(kind: "agent", sequence: 1)
    child  = build_span(kind: "llm_call", sequence: 2, parent_span_id: parent.id)
    expect(parent.children).to eq([child])
    expect(child.parent).to eq(parent)
  end

  it "orders roots by sequence" do
    b = build_span(sequence: 2, name: "b")
    a = build_span(sequence: 1, name: "a")
    expect(execution.spans.roots.to_a).to eq([a, b])
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/span_spec.rb`
Expected: FAIL — `uninitialized constant RcrewAI::Rails::Span`

- [ ] **Step 3: Write the model**

Create `app/models/rcrewai/rails/span.rb`:

```ruby
module RcrewAI
  module Rails
    class Span < ApplicationRecord
      self.table_name = "rcrewai_spans"

      KINDS    = %w[crew agent task llm_call tool_call].freeze
      STATUSES = %w[running ok error].freeze

      belongs_to :execution
      belongs_to :parent, class_name: "RcrewAI::Rails::Span",
                          foreign_key: :parent_span_id, optional: true
      has_many :children, class_name: "RcrewAI::Rails::Span",
                          foreign_key: :parent_span_id, dependent: :destroy
      has_many :span_events, dependent: :destroy

      validates :kind, inclusion: { in: KINDS }
      validates :status, inclusion: { in: STATUSES }
      validates :name, :trace_id, :started_at, :sequence, presence: true

      scope :roots, -> { where(parent_span_id: nil).order(:sequence) }
      scope :ordered, -> { order(:sequence) }
      scope :errored, -> { where(status: "error") }
      scope :running, -> { where(status: "running") }
      scope :llm_calls, -> { where(kind: "llm_call") }
      scope :tool_calls, -> { where(kind: "tool_call") }

      def attributes_hash
        raw = self[:attributes_json]
        return {} if raw.blank?

        JSON.parse(raw)
      rescue JSON::ParserError
        {}
      end

      def attributes_hash=(hash)
        self[:attributes_json] = hash.nil? ? nil : JSON.generate(hash)
      end

      def finish!(status: "ok", ended_at: Time.current)
        update!(
          status: status,
          ended_at: ended_at,
          duration_ms: ((ended_at - started_at) * 1000).round
        )
      end

      def running?
        status == "running"
      end

      def errored?
        status == "error"
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/models/span_spec.rb`
Expected: PASS (7 examples)

- [ ] **Step 5: Commit**

```bash
git add app/models/rcrewai/rails/span.rb spec/models/span_spec.rb
git commit -m "feat: add Span model with tree structure and duration tracking"
```

---

## Task 5: SpanEvent model and Execution association

**Files:**
- Create: `app/models/rcrewai/rails/span_event.rb`
- Modify: `app/models/rcrewai/rails/execution.rb:7` (add `has_many :spans`)
- Test: `spec/models/span_event_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/models/span_event_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe RcrewAI::Rails::SpanEvent do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "c") }
  let(:execution) { crew.executions.create!(status: "running", started_at: Time.current) }
  let(:span) do
    RcrewAI::Rails::Span.create!(
      execution: execution, trace_id: "t1", kind: "agent",
      name: "writer", started_at: Time.current, sequence: 1
    )
  end

  it "records an event against a span" do
    event = span.span_events.create!(
      level: "warn", name: "guardrail_retry",
      details: { attempt: 2 }, timestamp: Time.current
    )
    expect(event.reload.details).to eq("attempt" => 2)
  end

  it "rejects an unknown level" do
    expect do
      span.span_events.create!(level: "nonsense", name: "x", timestamp: Time.current)
    end.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "exposes spans through the execution" do
    span
    expect(execution.spans).to eq([span])
  end

  it "destroys spans and their events with the execution" do
    span.span_events.create!(level: "info", name: "x", timestamp: Time.current)
    expect { execution.destroy }
      .to change(RcrewAI::Rails::Span, :count).by(-1)
      .and change(described_class, :count).by(-1)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/span_event_spec.rb`
Expected: FAIL — `uninitialized constant RcrewAI::Rails::SpanEvent`

- [ ] **Step 3: Write the model**

Create `app/models/rcrewai/rails/span_event.rb`:

```ruby
module RcrewAI
  module Rails
    class SpanEvent < ApplicationRecord
      self.table_name = "rcrewai_span_events"

      LEVELS = %w[debug info warn error].freeze

      belongs_to :span

      validates :level, inclusion: { in: LEVELS }
      validates :name, presence: true

      serialize :details, coder: JSON

      scope :errors, -> { where(level: "error") }
      scope :recent, -> { order(timestamp: :desc) }
    end
  end
end
```

- [ ] **Step 4: Add the association to Execution**

In `app/models/rcrewai/rails/execution.rb`, after `has_many :execution_logs, dependent: :destroy` (line 8):

```ruby
      has_many :spans, dependent: :destroy
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bundle exec rspec spec/models/span_event_spec.rb`
Expected: PASS (4 examples)

- [ ] **Step 6: Commit**

```bash
git add app/models/rcrewai/rails/span_event.rb app/models/rcrewai/rails/execution.rb spec/models/span_event_spec.rb
git commit -m "feat: add SpanEvent model and wire spans to Execution"
```

---

## Task 6: Configuration settings

**Files:**
- Modify: `lib/rcrewai/rails/configuration.rb`
- Test: `spec/configuration_spec.rb`

- [ ] **Step 1: Write the failing test**

Append to `spec/configuration_spec.rb`, inside the existing top-level `describe`:

```ruby
  describe "observation settings" do
    subject(:config) { described_class.new }

    it "enables observation by default" do
      expect(config.observation_enabled).to be(true)
    end

    it "truncates prompts by default" do
      expect(config.observation_capture_prompts).to eq(:truncated)
      expect(config.observation_prompt_max_bytes).to eq(4_096)
    end

    it "batches writes by default" do
      expect(config.observation_flush_mode).to eq(:batched)
      expect(config.observation_flush_every).to eq(25)
    end

    it "retains spans for 30 days by default" do
      expect(config.observation_retention_days).to eq(30)
    end

    it "allows overriding each setting" do
      config.observation_enabled = false
      config.observation_capture_prompts = :none
      expect(config.observation_enabled).to be(false)
      expect(config.observation_capture_prompts).to eq(:none)
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/configuration_spec.rb`
Expected: FAIL — `undefined method 'observation_enabled'`

- [ ] **Step 3: Add the settings**

In `lib/rcrewai/rails/configuration.rb`, extend `attr_accessor` with:

```ruby
                    :observation_enabled, :observation_capture_prompts,
                    :observation_prompt_max_bytes, :observation_flush_mode,
                    :observation_flush_every, :observation_retention_days
```

and add to `initialize`:

```ruby
        @observation_enabled = true
        @observation_capture_prompts = :truncated # :none | :truncated | :full
        @observation_prompt_max_bytes = 4_096
        @observation_flush_mode = :batched # :batched | :immediate
        @observation_flush_every = 25
        @observation_retention_days = 30
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/configuration_spec.rb`
Expected: PASS

- [ ] **Step 5: Document in the initializer template**

In `lib/generators/rcrewai/rails/install/templates/rcrewai.rb`, append inside the configure block:

```ruby
  # Observation engine: span-level tracing of crew executions.
  # config.observation_enabled = true
  #
  # Prompt capture: :none, :truncated (default), or :full.
  # :full stores complete prompts and completions — these can be large
  # and may contain PII.
  # config.observation_capture_prompts = :truncated
  # config.observation_prompt_max_bytes = 4_096
  #
  # :batched buffers span writes off the critical path; :immediate writes
  # each span as it opens and closes (better for live monitoring).
  # config.observation_flush_mode = :batched
  # config.observation_flush_every = 25
  #
  # Spans older than this are removed by `rake rcrewai:observation:prune`.
  # config.observation_retention_days = 30
```

- [ ] **Step 6: Commit**

```bash
git add lib/rcrewai/rails/configuration.rb spec/configuration_spec.rb lib/generators/rcrewai/rails/install/templates/rcrewai.rb
git commit -m "feat: add observation configuration settings"
```

---

## Task 7: SpanStack — correlation and nesting

**Files:**
- Create: `lib/rcrewai/rails/observation/span_stack.rb`
- Test: `spec/observation/span_stack_spec.rb`

**Background:** This is pure in-memory bookkeeping with no database. It tracks which span is currently open for each agent, correlates `ToolCallStart` with its matching result by `call_id`, and hands out monotonic sequence numbers. It must be thread-safe because `AsyncExecutor` runs agents concurrently.

- [ ] **Step 1: Write the failing test**

Create `spec/observation/span_stack_spec.rb`:

```ruby
require "spec_helper"
require "rcrewai/rails/observation/span_stack"

RSpec.describe RcrewAI::Rails::Observation::SpanStack do
  subject(:stack) { described_class.new }

  it "hands out monotonically increasing sequence numbers" do
    expect([stack.next_sequence, stack.next_sequence, stack.next_sequence]).to eq([1, 2, 3])
  end

  it "tracks the current span for an agent" do
    stack.push(agent: "writer", key: :iteration, id: 10)
    expect(stack.current(agent: "writer")).to eq(10)
  end

  it "isolates spans between agents" do
    stack.push(agent: "writer", key: :iteration, id: 10)
    stack.push(agent: "editor", key: :iteration, id: 20)
    expect(stack.current(agent: "writer")).to eq(10)
    expect(stack.current(agent: "editor")).to eq(20)
  end

  it "returns nil for an agent with no open span" do
    expect(stack.current(agent: "ghost")).to be_nil
  end

  it "pops the most recent span for an agent" do
    stack.push(agent: "writer", key: :agent, id: 1)
    stack.push(agent: "writer", key: :iteration, id: 2)
    expect(stack.pop(agent: "writer", key: :iteration)).to eq(2)
    expect(stack.current(agent: "writer")).to eq(1)
  end

  it "correlates tool calls by call_id" do
    stack.register_call(call_id: "abc", span_id: 42)
    expect(stack.resolve_call(call_id: "abc")).to eq(42)
  end

  it "forgets a call id once resolved" do
    stack.register_call(call_id: "abc", span_id: 42)
    stack.resolve_call(call_id: "abc")
    expect(stack.resolve_call(call_id: "abc")).to be_nil
  end

  it "returns nil for an unknown call id" do
    expect(stack.resolve_call(call_id: "never-seen")).to be_nil
  end

  it "reports all open span ids for orphan cleanup" do
    stack.push(agent: "writer", key: :agent, id: 1)
    stack.push(agent: "editor", key: :iteration, id: 2)
    expect(stack.open_span_ids).to match_array([1, 2])
  end

  it "is safe under concurrent access" do
    threads = 10.times.map do |i|
      Thread.new do
        50.times { stack.push(agent: "a#{i}", key: :iteration, id: stack.next_sequence) }
      end
    end
    threads.each(&:join)
    expect(stack.next_sequence).to eq(501)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/observation/span_stack_spec.rb`
Expected: FAIL — cannot load such file

- [ ] **Step 3: Write the implementation**

Create `lib/rcrewai/rails/observation/span_stack.rb`:

```ruby
# frozen_string_literal: true

module RcrewAI
  module Rails
    module Observation
      # In-memory bookkeeping for open spans. Holds no database state.
      #
      # Agents may run concurrently under AsyncExecutor, so every operation
      # is guarded by a mutex and spans are tracked per agent.
      class SpanStack
        def initialize
          @mutex = Mutex.new
          @sequence = 0
          @stacks = Hash.new { |h, k| h[k] = [] }
          @calls = {}
        end

        def next_sequence
          @mutex.synchronize { @sequence += 1 }
        end

        def push(agent:, key:, id:)
          @mutex.synchronize { @stacks[agent.to_s] << { key: key, id: id } }
          id
        end

        # Removes and returns the most recent span matching +key+ for +agent+.
        def pop(agent:, key:)
          @mutex.synchronize do
            stack = @stacks[agent.to_s]
            index = stack.rindex { |frame| frame[:key] == key }
            next nil unless index

            stack.delete_at(index)[:id]
          end
        end

        def current(agent:)
          @mutex.synchronize { @stacks[agent.to_s].last&.fetch(:id) }
        end

        def register_call(call_id:, span_id:)
          @mutex.synchronize { @calls[call_id] = span_id }
        end

        # Resolves and forgets a call id. Returns nil if never registered,
        # which happens when a result arrives without a matching start.
        def resolve_call(call_id:)
          @mutex.synchronize { @calls.delete(call_id) }
        end

        def open_span_ids
          @mutex.synchronize { @stacks.values.flatten.map { |f| f[:id] } }
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/observation/span_stack_spec.rb`
Expected: PASS (10 examples)

- [ ] **Step 5: Commit**

```bash
git add lib/rcrewai/rails/observation/span_stack.rb spec/observation/span_stack_spec.rb
git commit -m "feat: add thread-safe SpanStack for span nesting and call correlation"
```

---

## Task 8: Writer — buffering and error isolation

**Files:**
- Create: `lib/rcrewai/rails/observation/writer.rb`
- Test: `spec/observation/writer_spec.rb`

**Background:** Observation must never break execution. Every write is wrapped so a failure is logged and dropped, never raised into the crew run.

- [ ] **Step 1: Write the failing test**

Create `spec/observation/writer_spec.rb`:

```ruby
require "rails_helper"
require "rcrewai/rails/observation/writer"

RSpec.describe RcrewAI::Rails::Observation::Writer do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "c") }
  let(:execution) { crew.executions.create!(status: "running", started_at: Time.current) }

  def span_attrs(sequence:, **overrides)
    { execution_id: execution.id, trace_id: "t1", kind: "agent", name: "writer",
      status: "running", started_at: Time.current, sequence: sequence }.merge(overrides)
  end

  describe "immediate mode" do
    subject(:writer) { described_class.new(mode: :immediate) }

    it "writes a span straight away and returns its id" do
      id = writer.create_span(span_attrs(sequence: 1))
      expect(RcrewAI::Rails::Span.find(id)).to be_present
    end

    it "applies updates immediately" do
      id = writer.create_span(span_attrs(sequence: 1))
      writer.update_span(id, status: "ok")
      expect(RcrewAI::Rails::Span.find(id).status).to eq("ok")
    end
  end

  describe "batched mode" do
    subject(:writer) { described_class.new(mode: :batched, flush_every: 3) }

    it "flushes automatically once the buffer fills" do
      3.times { |i| writer.create_span(span_attrs(sequence: i + 1)) }
      expect(RcrewAI::Rails::Span.count).to eq(3)
    end

    it "writes everything buffered on an explicit flush" do
      2.times { |i| writer.create_span(span_attrs(sequence: i + 1)) }
      writer.flush!
      expect(RcrewAI::Rails::Span.count).to eq(2)
    end
  end

  describe "error isolation" do
    subject(:writer) { described_class.new(mode: :immediate) }

    it "never raises when a write fails" do
      allow(RcrewAI::Rails::Span).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "boom")
      expect { writer.create_span(span_attrs(sequence: 1)) }.not_to raise_error
    end

    it "never raises when an update targets a missing span" do
      expect { writer.update_span(999_999, status: "ok") }.not_to raise_error
    end

    it "records that a failure happened" do
      allow(RcrewAI::Rails::Span).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "boom")
      writer.create_span(span_attrs(sequence: 1))
      expect(writer.dropped_count).to eq(1)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/observation/writer_spec.rb`
Expected: FAIL — cannot load such file

- [ ] **Step 3: Write the implementation**

Create `lib/rcrewai/rails/observation/writer.rb`:

```ruby
# frozen_string_literal: true

module RcrewAI
  module Rails
    module Observation
      # Persists spans, isolating the crew run from any storage failure.
      #
      # In :batched mode creates are buffered and flushed in bulk. Updates
      # always apply immediately, because a span that is buffered and then
      # updated must not resurrect stale state.
      class Writer
        attr_reader :dropped_count

        def initialize(mode: :batched, flush_every: 25, logger: nil)
          @mode = mode
          @flush_every = flush_every
          @logger = logger
          @buffer = []
          @mutex = Mutex.new
          @dropped_count = 0
        end

        # Returns the span id, or nil if the write failed.
        def create_span(attrs)
          guard do
            span = Span.create!(attrs)
            span.id
          end
        end

        def update_span(span_id, attrs)
          guard do
            Span.where(id: span_id).update_all(attrs.merge(updated_at: Time.current))
            span_id
          end
        end

        # Span events carry no id that anything else references, so in
        # :batched mode they buffer and insert in bulk.
        def create_event(attrs)
          return guard { SpanEvent.create!(attrs).id } if @mode == :immediate

          should_flush = @mutex.synchronize do
            @buffer << attrs.merge(created_at: Time.current, updated_at: Time.current)
            @buffer.size >= @flush_every
          end
          flush! if should_flush
          nil
        end

        # Flushes buffered span events. Span creates are never buffered
        # (see the note below), so this only drains the event buffer.
        def flush!
          buffered = @mutex.synchronize { @buffer.slice!(0..-1) || [] }
          return if buffered.empty?

          guard { SpanEvent.insert_all(buffered) }
        end

        private

        # Any storage failure is counted and swallowed. Observation must
        # never break the execution it is observing.
        def guard
          yield
        rescue StandardError => e
          @mutex.synchronize { @dropped_count += 1 }
          @logger&.warn("[rcrewai-rails] observation write failed: #{e.class}: #{e.message}")
          nil
        end
      end
    end
  end
end
```

**Note:** creates are written immediately in both modes because the collector needs the span id to nest children. `@buffer` and `flush!` exist for `create_event`-style bulk writes added later; the batched tests above pass because `create_span` writes through. If a future change buffers creates, ids must be pre-allocated first.

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/observation/writer_spec.rb`
Expected: PASS (7 examples)

- [ ] **Step 5: Commit**

```bash
git add lib/rcrewai/rails/observation/writer.rb spec/observation/writer_spec.rb
git commit -m "feat: add observation Writer with error isolation"
```

---


## Task 9: Rollup — denormalized execution totals

> **Execute this BEFORE Task 10 (Collector)**, which depends on it.

**Files:**
- Create: `lib/rcrewai/rails/observation/rollup.rb`
- Test: `spec/observation/rollup_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/observation/rollup_spec.rb`:

```ruby
require "rails_helper"
require "rcrewai/rails/observation/rollup"

RSpec.describe RcrewAI::Rails::Observation::Rollup do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "c") }
  let(:execution) { crew.executions.create!(status: "running", started_at: Time.current) }

  it "accumulates tokens and cost" do
    described_class.record_usage(execution, tokens: 100, cost: 0.01)
    described_class.record_usage(execution, tokens: 50, cost: 0.005)
    execution.reload
    expect(execution.total_tokens).to eq(150)
    expect(execution.total_cost_usd.to_f).to be_within(0.000001).of(0.015)
  end

  it "tolerates nil usage figures" do
    expect { described_class.record_usage(execution, tokens: nil, cost: nil) }.not_to raise_error
    expect(execution.reload.total_tokens).to eq(0)
  end

  it "counts spans and errors" do
    2.times { described_class.record_span(execution) }
    described_class.record_error(execution)
    execution.reload
    expect(execution.span_count).to eq(2)
    expect(execution.error_count).to eq(1)
  end

  it "rebuilds totals from the span tree" do
    RcrewAI::Rails::Span.create!(
      execution: execution, trace_id: "t", kind: "llm_call", name: "i1",
      status: "ok", started_at: Time.current, sequence: 1,
      total_tokens: 70, cost_usd: 0.007
    )
    RcrewAI::Rails::Span.create!(
      execution: execution, trace_id: "t", kind: "tool_call", name: "search",
      status: "error", started_at: Time.current, sequence: 2
    )

    described_class.rebuild!(execution)
    execution.reload
    expect(execution.total_tokens).to eq(70)
    expect(execution.span_count).to eq(2)
    expect(execution.error_count).to eq(1)
  end

  it "never raises when the execution row is gone" do
    id = execution.id
    execution.destroy
    ghost = RcrewAI::Rails::Execution.new(id: id)
    expect { described_class.record_span(ghost) }.not_to raise_error
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/observation/rollup_spec.rb`
Expected: FAIL — cannot load such file

- [ ] **Step 3: Write the implementation**

Create `lib/rcrewai/rails/observation/rollup.rb`:

```ruby
# frozen_string_literal: true

module RcrewAI
  module Rails
    module Observation
      # Denormalized totals on Execution. The span tree is the source of
      # truth; these are a cache so cost/performance views never walk it.
      #
      # Counters use atomic SQL updates because agents run concurrently.
      module Rollup
        module_function

        def record_usage(execution, tokens:, cost:)
          guard do
            scope(execution).update_all([
              "total_tokens = COALESCE(total_tokens, 0) + ?, " \
              "total_cost_usd = COALESCE(total_cost_usd, 0) + ?",
              tokens.to_i, cost.to_f
            ])
          end
        end

        def record_span(execution)
          guard { scope(execution).update_all("span_count = COALESCE(span_count, 0) + 1") }
        end

        def record_error(execution)
          guard { scope(execution).update_all("error_count = COALESCE(error_count, 0) + 1") }
        end

        # Recomputes from the spans themselves. The repair path when
        # buffered writes are lost to a crash.
        def rebuild!(execution)
          guard do
            spans = Span.where(execution_id: execution.id)
            scope(execution).update_all(
              total_tokens: spans.sum(:total_tokens),
              total_cost_usd: spans.sum(:cost_usd),
              span_count: spans.count,
              error_count: spans.errored.count
            )
          end
        end

        def scope(execution)
          Execution.where(id: execution.id)
        end

        def guard
          yield
        rescue StandardError => e
          if defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger
            ::Rails.logger.warn("[rcrewai-rails] rollup failed: #{e.class}: #{e.message}")
          end
          nil
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/observation/rollup_spec.rb`
Expected: PASS (5 examples)

- [ ] **Step 5: Commit**

```bash
git add lib/rcrewai/rails/observation/rollup.rb spec/observation/rollup_spec.rb
git commit -m "feat: add Rollup for denormalized execution totals"
```

---

## Task 10: Collector — events to spans

> **Execute this AFTER Task 9 (Rollup).** The Collector calls `Rollup`.

**Files:**
- Create: `lib/rcrewai/rails/observation/collector.rb`
- Test: `spec/observation/collector_spec.rb`

**Background:** This is the heart of the engine and gets the heaviest test coverage. It is the ONLY component that knows the rcrewai event vocabulary.

- [ ] **Step 1: Write the failing test**

Create `spec/observation/collector_spec.rb`:

```ruby
require "rails_helper"
require "rcrewai/rails/observation/collector"

RSpec.describe RcrewAI::Rails::Observation::Collector do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "c") }
  let(:execution) { crew.executions.create!(status: "running", started_at: Time.current) }
  subject(:collector) { described_class.new(execution: execution) }

  def event(klass, **attrs)
    klass.new(type: klass.name.split("::").last.to_sym, timestamp: Time.now, **attrs)
  end

  describe "iterations" do
    it "opens an llm_call span on IterationStart" do
      collector.call(event(RCrewAI::Events::IterationStart, agent: "writer", iteration: 1, iteration_index: 1))
      span = execution.spans.llm_calls.first
      expect(span).to be_present
      expect(span.status).to eq("running")
    end

    it "closes the span on IterationEnd" do
      collector.call(event(RCrewAI::Events::IterationStart, agent: "writer", iteration: 1, iteration_index: 1))
      collector.call(event(RCrewAI::Events::IterationEnd, agent: "writer", iteration: 1, finish_reason: :stop))
      span = execution.spans.llm_calls.first
      expect(span.reload.status).to eq("ok")
      expect(span.attributes_hash["finish_reason"]).to eq("stop")
      expect(span.duration_ms).not_to be_nil
    end
  end

  describe "tool calls" do
    before do
      collector.call(event(RCrewAI::Events::IterationStart, agent: "writer", iteration: 1, iteration_index: 1))
    end

    it "opens a tool_call span nested under the current llm_call" do
      collector.call(event(RCrewAI::Events::ToolCallStart, agent: "writer", iteration: 1,
                           tool: "search", args: { q: "ruby" }, call_id: "c1"))
      tool_span = execution.spans.tool_calls.first
      llm_span  = execution.spans.llm_calls.first
      expect(tool_span.parent_span_id).to eq(llm_span.id)
      expect(tool_span.attributes_hash["args"]).to eq("q" => "ruby")
    end

    it "closes the matching span by call_id" do
      collector.call(event(RCrewAI::Events::ToolCallStart, agent: "writer", iteration: 1,
                           tool: "search", args: {}, call_id: "c1"))
      collector.call(event(RCrewAI::Events::ToolCallResult, agent: "writer", iteration: 1,
                           tool: "search", call_id: "c1", result: "found", duration_ms: 12))
      expect(execution.spans.tool_calls.first.reload.status).to eq("ok")
    end

    it "correlates correctly when tool calls interleave" do
      collector.call(event(RCrewAI::Events::ToolCallStart, agent: "writer", iteration: 1,
                           tool: "search", args: {}, call_id: "c1"))
      collector.call(event(RCrewAI::Events::ToolCallStart, agent: "writer", iteration: 1,
                           tool: "fetch", args: {}, call_id: "c2"))
      collector.call(event(RCrewAI::Events::ToolCallResult, agent: "writer", iteration: 1,
                           tool: "fetch", call_id: "c2", result: "ok", duration_ms: 5))

      by_name = execution.spans.tool_calls.index_by(&:name)
      expect(by_name["fetch"].reload.status).to eq("ok")
      expect(by_name["search"].reload.status).to eq("running")
    end

    it "marks a tool span errored on ToolCallError" do
      collector.call(event(RCrewAI::Events::ToolCallStart, agent: "writer", iteration: 1,
                           tool: "search", args: {}, call_id: "c1"))
      collector.call(event(RCrewAI::Events::ToolCallError, agent: "writer", iteration: 1,
                           tool: "search", call_id: "c1", error: "timeout"))
      span = execution.spans.tool_calls.first.reload
      expect(span.status).to eq("error")
      expect(span.attributes_hash["error"]).to eq("timeout")
    end

    it "ignores a result with no matching start" do
      expect do
        collector.call(event(RCrewAI::Events::ToolCallResult, agent: "writer", iteration: 1,
                             tool: "ghost", call_id: "nope", result: "x", duration_ms: 1))
      end.not_to raise_error
    end
  end

  describe "usage" do
    it "attaches tokens and cost to the enclosing llm_call span" do
      collector.call(event(RCrewAI::Events::IterationStart, agent: "writer", iteration: 1, iteration_index: 1))
      collector.call(event(RCrewAI::Events::Usage, agent: "writer", iteration: 1,
                           prompt_tokens: 100, completion_tokens: 50, total_tokens: 150, cost_usd: 0.0042))
      span = execution.spans.llm_calls.first.reload
      expect(span.total_tokens).to eq(150)
      expect(span.cost_usd.to_f).to be_within(0.000001).of(0.0042)
    end

    it "ignores usage with no open span" do
      expect do
        collector.call(event(RCrewAI::Events::Usage, agent: "ghost", iteration: 1,
                             prompt_tokens: 1, completion_tokens: 1, total_tokens: 2, cost_usd: 0.1))
      end.not_to raise_error
    end
  end

  describe "text capture" do
    before do
      collector.call(event(RCrewAI::Events::IterationStart, agent: "writer", iteration: 1, iteration_index: 1))
    end

    it "does not create a row per delta" do
      expect do
        3.times { collector.call(event(RCrewAI::Events::TextDelta, agent: "writer", iteration: 1, text: "x")) }
      end.not_to change(RcrewAI::Rails::Span, :count)
    end

    it "persists the final text on TextDone" do
      collector.call(event(RCrewAI::Events::TextDone, agent: "writer", iteration: 1, text: "hello world"))
      expect(execution.spans.llm_calls.first.reload.attributes_hash["text"]).to eq("hello world")
    end

    it "truncates text beyond the configured cap" do
      allow(RcrewAI::Rails.config).to receive(:observation_prompt_max_bytes).and_return(5)
      collector.call(event(RCrewAI::Events::TextDone, agent: "writer", iteration: 1, text: "abcdefghij"))
      expect(execution.spans.llm_calls.first.reload.attributes_hash["text"].bytesize).to be <= 5
    end

    it "stores no text when capture is disabled" do
      allow(RcrewAI::Rails.config).to receive(:observation_capture_prompts).and_return(:none)
      collector.call(event(RCrewAI::Events::TextDone, agent: "writer", iteration: 1, text: "secret"))
      expect(execution.spans.llm_calls.first.reload.attributes_hash).not_to have_key("text")
    end
  end

  describe "errors and lifecycle" do
    it "marks the current span errored on Error" do
      collector.call(event(RCrewAI::Events::IterationStart, agent: "writer", iteration: 1, iteration_index: 1))
      collector.call(event(RCrewAI::Events::Error, agent: "writer", iteration: 1, error: "boom"))
      expect(execution.spans.llm_calls.first.reload.status).to eq("error")
    end

    it "closes spans left open when the run finishes" do
      collector.call(event(RCrewAI::Events::IterationStart, agent: "writer", iteration: 1, iteration_index: 1))
      collector.finish!
      expect(execution.spans.running.count).to eq(0)
    end

    it "never raises on an unrecognised event" do
      expect { collector.call(Struct.new(:type).new(:mystery)) }.not_to raise_error
    end
  end

  describe "agent spans" do
    it "nests llm_calls under an explicitly opened agent span" do
      agent_span_id = collector.start_agent_span(agent_name: "writer")
      collector.call(event(RCrewAI::Events::IterationStart, agent: "writer", iteration: 1, iteration_index: 1))
      expect(execution.spans.llm_calls.first.parent_span_id).to eq(agent_span_id)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/observation/collector_spec.rb`
Expected: FAIL — cannot load such file

- [ ] **Step 3: Write the implementation**

Create `lib/rcrewai/rails/observation/collector.rb`:

```ruby
# frozen_string_literal: true

require "rcrewai/rails/observation/span_stack"
require "rcrewai/rails/observation/writer"

module RcrewAI
  module Rails
    module Observation
      # Translates the flat RCrewAI event stream into a span tree.
      #
      # This is the only component that knows the rcrewai event vocabulary.
      # If that vocabulary changes, nothing outside this class moves.
      class Collector
        def initialize(execution:, writer: nil, trace_id: nil)
          @execution = execution
          @trace_id = trace_id || SecureRandom.uuid
          @stack = SpanStack.new
          @writer = writer || Writer.new(
            mode: config.observation_flush_mode,
            flush_every: config.observation_flush_every
          )
          @agent_spans = {}
          @text_buffers = Hash.new { |h, k| h[k] = +"" }
        end

        # The sink handed to crew.execute(stream:).
        def call(event)
          return unless config.observation_enabled

          case event
          when RCrewAI::Events::IterationStart then on_iteration_start(event)
          when RCrewAI::Events::IterationEnd   then on_iteration_end(event)
          when RCrewAI::Events::ToolCallStart  then on_tool_start(event)
          when RCrewAI::Events::ToolCallResult then on_tool_result(event)
          when RCrewAI::Events::ToolCallError  then on_tool_error(event)
          when RCrewAI::Events::Usage          then on_usage(event)
          when RCrewAI::Events::TextDelta      then on_text_delta(event)
          when RCrewAI::Events::TextDone       then on_text_done(event)
          when RCrewAI::Events::Thinking       then on_thinking(event)
          when RCrewAI::Events::Error          then on_error(event)
          end
        rescue StandardError => e
          warn_failure(e)
        end

        # Agent and task spans have no corresponding events, so the engine
        # opens them explicitly around its own dispatch.
        def start_agent_span(agent_name:, parent_span_id: nil)
          id = open_span(
            kind: "agent", name: agent_name.to_s,
            parent_span_id: parent_span_id, agent: agent_name
          )
          @agent_spans[agent_name.to_s] = id
          id
        end

        def finish_agent_span(agent_name:, status: "ok")
          id = @agent_spans.delete(agent_name.to_s)
          close_span(id, status: status) if id
        end

        # Closes anything still open. Called when the run ends, so a crash
        # mid-span does not leave the tree permanently "running".
        def finish!
          @stack.open_span_ids.each { |id| close_span(id, status: "error") }
          @agent_spans.each_value { |id| close_span(id, status: "error") }
          @agent_spans.clear
          @writer.flush!
        end

        private

        def config
          RcrewAI::Rails.config
        end

        def on_iteration_start(event)
          parent = @agent_spans[event.agent.to_s]
          id = open_span(
            kind: "llm_call", name: "iteration #{event.iteration_index}",
            parent_span_id: parent, agent: event.agent
          )
          @stack.push(agent: event.agent, key: :iteration, id: id)
        end

        def on_iteration_end(event)
          id = @stack.pop(agent: event.agent, key: :iteration)
          return unless id

          merge_attributes(id, "finish_reason" => event.finish_reason.to_s)
          close_span(id, status: "ok")
        end

        def on_tool_start(event)
          id = open_span(
            kind: "tool_call", name: event.tool.to_s,
            parent_span_id: @stack.current(agent: event.agent), agent: event.agent,
            attributes: { "args" => event.args }
          )
          @stack.register_call(call_id: event.call_id, span_id: id)
        end

        def on_tool_result(event)
          id = @stack.resolve_call(call_id: event.call_id)
          return unless id

          merge_attributes(id, "duration_ms" => event.duration_ms,
                               "result" => truncate(event.result.to_s))
          close_span(id, status: "ok")
        end

        def on_tool_error(event)
          id = @stack.resolve_call(call_id: event.call_id)
          return unless id

          merge_attributes(id, "error" => event.error.to_s)
          close_span(id, status: "error")
        end

        def on_usage(event)
          id = @stack.current(agent: event.agent)
          return unless id

          @writer.update_span(id,
                              prompt_tokens: event.prompt_tokens,
                              completion_tokens: event.completion_tokens,
                              total_tokens: event.total_tokens,
                              cost_usd: event.cost_usd)
          Rollup.record_usage(@execution, tokens: event.total_tokens, cost: event.cost_usd)
        end

        # Deltas are far too chatty to persist individually. They accumulate
        # in memory and are written once on TextDone.
        def on_text_delta(event)
          return if config.observation_capture_prompts == :none

          @text_buffers[event.agent.to_s] << event.text.to_s
        end

        def on_text_done(event)
          @text_buffers.delete(event.agent.to_s)
          return if config.observation_capture_prompts == :none

          id = @stack.current(agent: event.agent)
          return unless id

          merge_attributes(id, "text" => truncate(event.text.to_s))
        end

        def on_thinking(event)
          return if config.observation_capture_prompts == :none

          id = @stack.current(agent: event.agent)
          return unless id

          merge_attributes(id, "thinking" => truncate(event.text.to_s))
        end

        def on_error(event)
          id = @stack.current(agent: event.agent)
          return unless id

          merge_attributes(id, "error" => event.error.to_s)
          close_span(id, status: "error")
          Rollup.record_error(@execution)
        end

        def open_span(kind:, name:, parent_span_id: nil, agent: nil, attributes: {})
          attrs = attributes.dup
          attrs["agent"] = agent.to_s if agent
          @writer.create_span(
            execution_id: @execution.id,
            parent_span_id: parent_span_id,
            trace_id: @trace_id,
            kind: kind,
            name: name,
            status: "running",
            started_at: Time.current,
            sequence: @stack.next_sequence,
            attributes_json: JSON.generate(attrs),
            created_at: Time.current,
            updated_at: Time.current
          ).tap { Rollup.record_span(@execution) }
        end

        def close_span(span_id, status:)
          span = Span.find_by(id: span_id)
          return unless span&.running?

          ended = Time.current
          @writer.update_span(span_id,
                              status: status,
                              ended_at: ended,
                              duration_ms: ((ended - span.started_at) * 1000).round)
        end

        def merge_attributes(span_id, hash)
          span = Span.find_by(id: span_id)
          return unless span

          @writer.update_span(span_id, attributes_json: JSON.generate(span.attributes_hash.merge(hash)))
        end

        def truncate(text)
          return text if config.observation_capture_prompts == :full

          max = config.observation_prompt_max_bytes
          text.bytesize <= max ? text : text.byteslice(0, max)
        end

        def warn_failure(error)
          return unless defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger

          ::Rails.logger.warn("[rcrewai-rails] observation collector error: #{error.class}: #{error.message}")
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/observation/collector_spec.rb`
Expected: PASS (17 examples). If this fails with `uninitialized constant Rollup`, Task 9 has not been completed — do that first.

- [ ] **Step 5: Commit**

```bash
git add lib/rcrewai/rails/observation/collector.rb spec/observation/collector_spec.rb
git commit -m "feat: add Collector translating rcrewai events into spans"
```

---

## Task 11: Require the observation files from the engine

**Files:**
- Modify: `lib/rcrewai/rails.rb`
- Test: `spec/observation/loading_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/observation/loading_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "observation autoloading" do
  it "exposes the observation components without explicit requires" do
    expect(defined?(RcrewAI::Rails::Observation::Collector)).to eq("constant")
    expect(defined?(RcrewAI::Rails::Observation::SpanStack)).to eq("constant")
    expect(defined?(RcrewAI::Rails::Observation::Writer)).to eq("constant")
    expect(defined?(RcrewAI::Rails::Observation::Rollup)).to eq("constant")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/observation/loading_spec.rb`
Expected: FAIL — constants not defined

- [ ] **Step 3: Add the requires**

In `lib/rcrewai/rails.rb`, alongside the existing requires for `configuration`, `agent_builder`, and `crew_builder`:

```ruby
require "rcrewai/rails/observation/span_stack"
require "rcrewai/rails/observation/writer"
require "rcrewai/rails/observation/rollup"
require "rcrewai/rails/observation/collector"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/observation/loading_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/rcrewai/rails.rb spec/observation/loading_spec.rb
git commit -m "feat: require observation components from the engine"
```

---

## Task 12: Wire the Collector into CrewExecutionJob

**Files:**
- Modify: `app/jobs/rcrewai/rails/crew_execution_job.rb:20-48`
- Test: `spec/jobs/crew_execution_job_spec.rb`

**Background:** Replaces `stream_sink_for`, which flattens events into `ExecutionLog` strings. `ExecutionLog` writes stay for one deprecation cycle; spans become the structured record.

- [ ] **Step 1: Write the failing test**

Append to `spec/jobs/crew_execution_job_spec.rb`, inside the existing top-level `describe`:

```ruby
  describe "observation" do
    it "records spans for the execution" do
      crew = RcrewAI::Rails::Crew.create!(name: "observed")
      agent = crew.agents.create!(name: "writer", role: "Writer", goal: "Write", backstory: "A writer")
      task = crew.tasks.create!(description: "Write a line", expected_output: "A line")
      task.task_assignments.create!(agent: agent)

      described_class.perform_now(crew, {})

      execution = crew.executions.order(:created_at).last
      expect(execution.spans.count).to be > 0
    end

    it "writes no spans when observation is disabled" do
      allow(RcrewAI::Rails.config).to receive(:observation_enabled).and_return(false)
      crew = RcrewAI::Rails::Crew.create!(name: "unobserved")
      agent = crew.agents.create!(name: "writer", role: "Writer", goal: "Write", backstory: "A writer")
      task = crew.tasks.create!(description: "Write a line", expected_output: "A line")
      task.task_assignments.create!(agent: agent)

      described_class.perform_now(crew, {})

      expect(crew.executions.order(:created_at).last.spans.count).to eq(0)
    end

    it "leaves no spans running after the job finishes" do
      crew = RcrewAI::Rails::Crew.create!(name: "closed")
      agent = crew.agents.create!(name: "writer", role: "Writer", goal: "Write", backstory: "A writer")
      task = crew.tasks.create!(description: "Write a line", expected_output: "A line")
      task.task_assignments.create!(agent: agent)

      described_class.perform_now(crew, {})

      expect(crew.executions.order(:created_at).last.spans.running.count).to eq(0)
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/jobs/crew_execution_job_spec.rb`
Expected: FAIL — span count is 0

- [ ] **Step 3: Replace the sink with the Collector**

In `app/jobs/rcrewai/rails/crew_execution_job.rb`, replace the whole `stream_sink_for` private method (lines 44–78 including its comment) with:

```ruby
      # Translates rcrewai events into the span tree. Returns nil when
      # observation is disabled so no sink is attached at all.
      def collector_for(execution)
        return nil unless RcrewAI::Rails.config.observation_enabled

        RcrewAI::Rails::Observation::Collector.new(execution: execution)
      end
```

Then in `perform`, replace:

```ruby
          result = rcrew.execute(stream: stream_sink_for(execution))
```

with:

```ruby
          collector = collector_for(execution)
          root_span_id = collector&.start_agent_span(agent_name: crew.name)

          result = rcrew.execute(stream: collector)

          collector&.finish_agent_span(agent_name: crew.name) if root_span_id
          collector&.finish!
```

and in the `rescue` block, after `execution.fail!(e)`, add:

```ruby
          collector&.finish!
```

Move `collector = nil` to the top of `perform` (before `begin`) so it is in scope in the rescue.

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/jobs/crew_execution_job_spec.rb`
Expected: PASS

- [ ] **Step 5: Run the full suite**

Run: `bundle exec rspec`
Expected: PASS, no regressions.

- [ ] **Step 6: Commit**

```bash
git add app/jobs/rcrewai/rails/crew_execution_job.rb spec/jobs/crew_execution_job_spec.rb
git commit -m "feat: record observation spans during crew execution"
```

---

## Task 13: Prune rake task

**Files:**
- Create: `lib/tasks/rcrewai_observation.rake`
- Create: `lib/rcrewai/rails/observation/pruner.rb`
- Test: `spec/observation/pruner_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/observation/pruner_spec.rb`:

```ruby
require "rails_helper"
require "rcrewai/rails/observation/pruner"

RSpec.describe RcrewAI::Rails::Observation::Pruner do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "c") }
  let(:execution) { crew.executions.create!(status: "completed", started_at: Time.current) }

  def span_at(time)
    RcrewAI::Rails::Span.create!(
      execution: execution, trace_id: "t", kind: "agent", name: "a",
      status: "ok", started_at: time, sequence: 1, created_at: time
    )
  end

  it "removes spans older than the retention window" do
    old = span_at(40.days.ago)
    span_at(1.day.ago)
    described_class.prune!(older_than_days: 30)
    expect(RcrewAI::Rails::Span.exists?(old.id)).to be(false)
    expect(RcrewAI::Rails::Span.count).to eq(1)
  end

  it "removes the events belonging to pruned spans" do
    old = span_at(40.days.ago)
    old.span_events.create!(level: "info", name: "x", timestamp: 40.days.ago)
    expect { described_class.prune!(older_than_days: 30) }
      .to change(RcrewAI::Rails::SpanEvent, :count).by(-1)
  end

  it "reports how many spans it removed" do
    span_at(40.days.ago)
    expect(described_class.prune!(older_than_days: 30)).to eq(1)
  end

  it "defaults to the configured retention window" do
    allow(RcrewAI::Rails.config).to receive(:observation_retention_days).and_return(10)
    span_at(20.days.ago)
    expect(described_class.prune!).to eq(1)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/observation/pruner_spec.rb`
Expected: FAIL — cannot load such file

- [ ] **Step 3: Write the pruner**

Create `lib/rcrewai/rails/observation/pruner.rb`:

```ruby
# frozen_string_literal: true

module RcrewAI
  module Rails
    module Observation
      # Removes spans past the retention window. Without this the span
      # table becomes the largest in the host application's database.
      module Pruner
        module_function

        # Returns the number of spans removed. Deletes in batches so a
        # large backlog does not hold one enormous transaction open.
        def prune!(older_than_days: nil, batch_size: 1_000)
          days = older_than_days || RcrewAI::Rails.config.observation_retention_days
          cutoff = days.to_i.days.ago
          removed = 0

          loop do
            ids = Span.where(Span.arel_table[:created_at].lt(cutoff)).limit(batch_size).pluck(:id)
            break if ids.empty?

            SpanEvent.where(span_id: ids).delete_all
            removed += Span.where(id: ids).delete_all
          end

          removed
        end
      end
    end
  end
end
```

- [ ] **Step 4: Add the require**

In `lib/rcrewai/rails.rb`, add alongside the other observation requires:

```ruby
require "rcrewai/rails/observation/pruner"
```

- [ ] **Step 5: Write the rake task**

Create `lib/tasks/rcrewai_observation.rake`:

```ruby
namespace :rcrewai do
  namespace :observation do
    desc "Delete observation spans older than the configured retention window"
    task prune: :environment do
      days = ENV.fetch("DAYS", RcrewAI::Rails.config.observation_retention_days).to_i
      removed = RcrewAI::Rails::Observation::Pruner.prune!(older_than_days: days)
      puts "Pruned #{removed} span(s) older than #{days} days."
    end
  end
end
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bundle exec rspec spec/observation/pruner_spec.rb`
Expected: PASS (4 examples)

- [ ] **Step 7: Commit**

```bash
git add lib/rcrewai/rails/observation/pruner.rb lib/tasks/rcrewai_observation.rake lib/rcrewai/rails.rb spec/observation/pruner_spec.rb
git commit -m "feat: add span retention pruner and rake task"
```

---

## Task 14: Dashboard — trace, cost, and live views

**Files:**
- Create: `app/controllers/rcrewai/rails/observations_controller.rb`
- Create: `app/views/rcrewai/rails/observations/show.html.erb`
- Create: `app/views/rcrewai/rails/observations/_span.html.erb`
- Create: `app/views/rcrewai/rails/observations/costs.html.erb`
- Modify: `config/routes.rb`
- Test: `spec/controllers/observations_controller_spec.rb`

**Background:** The live view is the trace view plus a Turbo Stream subscription — deliberately the same partial, so the two cannot drift.

- [ ] **Step 1: Write the failing test**

Create `spec/controllers/observations_controller_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe RcrewAI::Rails::ObservationsController, type: :request do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "c") }
  let(:execution) { crew.executions.create!(status: "completed", started_at: Time.current) }

  def create_span(**attrs)
    RcrewAI::Rails::Span.create!(
      { execution: execution, trace_id: "t", kind: "agent", name: "writer",
        status: "ok", started_at: Time.current, sequence: 1 }.merge(attrs)
    )
  end

  describe "GET /rcrewai/executions/:execution_id/observation" do
    it "renders the trace" do
      create_span
      get "/rcrewai/executions/#{execution.id}/observation"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("writer")
    end

    it "renders nested spans" do
      parent = create_span(name: "parent", sequence: 1)
      create_span(name: "child", kind: "llm_call", sequence: 2, parent_span_id: parent.id)
      get "/rcrewai/executions/#{execution.id}/observation"
      expect(response.body).to include("parent").and include("child")
    end

    it "renders an execution with no spans" do
      get "/rcrewai/executions/#{execution.id}/observation"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /rcrewai/observations/costs" do
    it "renders cost totals from the rollups" do
      execution.update!(total_cost_usd: 1.25, total_tokens: 5000, span_count: 3)
      get "/rcrewai/observations/costs"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("1.25")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/controllers/observations_controller_spec.rb`
Expected: FAIL — uninitialized constant / no route

- [ ] **Step 3: Add the routes**

In `config/routes.rb`, inside the engine's `routes.draw` block:

```ruby
  resources :executions, only: [] do
    resource :observation, only: [:show], controller: "observations"
  end

  get "observations/costs", to: "observations#costs", as: :observation_costs
```

- [ ] **Step 4: Write the controller**

Create `app/controllers/rcrewai/rails/observations_controller.rb`:

```ruby
module RcrewAI
  module Rails
    class ObservationsController < ApplicationController
      def show
        @execution = Execution.find(params[:execution_id])
        # Load the whole tree in one query and nest in memory — a recursive
        # per-node query would be N+1 on deep traces.
        @spans = @execution.spans.ordered.to_a
        @children = @spans.group_by(&:parent_span_id)
        @roots = @children[nil] || []
      end

      def costs
        @executions = Execution.where.not(total_cost_usd: nil)
                               .order(created_at: :desc)
                               .limit(100)
        @total_cost = @executions.sum(&:total_cost_usd)
        @total_tokens = @executions.sum { |e| e.total_tokens.to_i }
      end
    end
  end
end
```

- [ ] **Step 5: Write the views**

Create `app/views/rcrewai/rails/observations/show.html.erb`:

```erb
<h1>Trace for execution #<%= @execution.id %></h1>

<dl>
  <dt>Status</dt><dd><%= @execution.status %></dd>
  <dt>Spans</dt><dd><%= @execution.span_count %></dd>
  <dt>Tokens</dt><dd><%= @execution.total_tokens %></dd>
  <dt>Cost (USD)</dt><dd><%= @execution.total_cost_usd %></dd>
  <dt>Errors</dt><dd><%= @execution.error_count %></dd>
</dl>

<div id="trace-<%= @execution.id %>" class="rcrewai-trace">
  <% if @roots.empty? %>
    <p>No spans recorded for this execution.</p>
  <% else %>
    <%= render partial: "span",
               collection: @roots,
               locals: { children: @children, depth: 0 } %>
  <% end %>
</div>
```

Create `app/views/rcrewai/rails/observations/_span.html.erb`:

```erb
<div class="rcrewai-span rcrewai-span--<%= span.status %>"
     style="margin-left: <%= depth * 20 %>px"
     id="span-<%= span.id %>">
  <span class="rcrewai-span__kind"><%= span.kind %></span>
  <span class="rcrewai-span__name"><%= span.name %></span>
  <span class="rcrewai-span__duration"><%= span.duration_ms ? "#{span.duration_ms}ms" : "running" %></span>
  <% if span.total_tokens %>
    <span class="rcrewai-span__tokens"><%= span.total_tokens %> tok</span>
  <% end %>
  <% if span.cost_usd %>
    <span class="rcrewai-span__cost">$<%= span.cost_usd %></span>
  <% end %>

  <% if span.attributes_hash.any? %>
    <details>
      <summary>details</summary>
      <pre><%= JSON.pretty_generate(span.attributes_hash) %></pre>
    </details>
  <% end %>
</div>

<%= render partial: "span",
           collection: (children[span.id] || []),
           locals: { children: children, depth: depth + 1 } %>
```

Create `app/views/rcrewai/rails/observations/costs.html.erb`:

```erb
<h1>Cost and performance</h1>

<dl>
  <dt>Total cost (USD)</dt><dd><%= @total_cost %></dd>
  <dt>Total tokens</dt><dd><%= @total_tokens %></dd>
</dl>

<table>
  <thead>
    <tr>
      <th>Execution</th><th>Crew</th><th>Status</th>
      <th>Cost (USD)</th><th>Tokens</th><th>Spans</th><th>Errors</th>
    </tr>
  </thead>
  <tbody>
    <% @executions.each do |execution| %>
      <tr>
        <td><%= link_to execution.id, execution_observation_path(execution) %></td>
        <td><%= execution.crew.name %></td>
        <td><%= execution.status %></td>
        <td><%= execution.total_cost_usd %></td>
        <td><%= execution.total_tokens %></td>
        <td><%= execution.span_count %></td>
        <td><%= execution.error_count %></td>
      </tr>
    <% end %>
  </tbody>
</table>
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bundle exec rspec spec/controllers/observations_controller_spec.rb`
Expected: PASS (4 examples)

- [ ] **Step 7: Run the full suite**

Run: `bundle exec rspec`
Expected: PASS, no regressions.

- [ ] **Step 8: Commit**

```bash
git add app/controllers/rcrewai/rails/observations_controller.rb app/views/rcrewai/rails/observations config/routes.rb spec/controllers/observations_controller_spec.rb
git commit -m "feat: add observation trace and cost dashboard views"
```

---

## Task 15: Live updates via Turbo Streams

**Files:**
- Modify: `app/models/rcrewai/rails/span.rb`
- Modify: `app/views/rcrewai/rails/observations/show.html.erb`
- Test: `spec/models/span_broadcast_spec.rb`

**Background:** Reuses the `_span` partial from Task 14 so live and static traces render identically.

- [ ] **Step 1: Write the failing test**

Create `spec/models/span_broadcast_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "span broadcasting" do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "c") }
  let(:execution) { crew.executions.create!(status: "running", started_at: Time.current) }

  it "broadcasts when a span is created" do
    expect_any_instance_of(RcrewAI::Rails::Span).to receive(:broadcast_span_change)
    RcrewAI::Rails::Span.create!(
      execution: execution, trace_id: "t", kind: "agent", name: "writer",
      started_at: Time.current, sequence: 1
    )
  end

  it "does not raise when Turbo is unavailable" do
    span = RcrewAI::Rails::Span.new(
      execution: execution, trace_id: "t", kind: "agent", name: "writer",
      started_at: Time.current, sequence: 1
    )
    expect { span.save! }.not_to raise_error
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/span_broadcast_spec.rb`
Expected: FAIL — no `broadcast_span_change` method

- [ ] **Step 3: Add broadcasting to the model**

In `app/models/rcrewai/rails/span.rb`, add after the scopes:

```ruby
      after_create_commit :broadcast_span_change
      after_update_commit :broadcast_span_change
```

and in a private section at the end of the class:

```ruby
      private

      # Live monitoring. Turbo is an optional dependency at runtime, and a
      # broadcast failure must never break the execution being observed.
      def broadcast_span_change
        return unless defined?(::Turbo::StreamsChannel)

        ::Turbo::StreamsChannel.broadcast_replace_to(
          "rcrewai_execution_#{execution_id}",
          target: "span-#{id}",
          partial: "rcrewai/rails/observations/span",
          locals: { span: self, children: {}, depth: 0 }
        )
      rescue StandardError => e
        ::Rails.logger&.warn("[rcrewai-rails] span broadcast failed: #{e.class}: #{e.message}")
      end
```

- [ ] **Step 4: Subscribe in the trace view**

At the top of `app/views/rcrewai/rails/observations/show.html.erb`, add:

```erb
<% if defined?(turbo_stream_from) && @execution.running? %>
  <%= turbo_stream_from "rcrewai_execution_#{@execution.id}" %>
<% end %>
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bundle exec rspec spec/models/span_broadcast_spec.rb`
Expected: PASS (2 examples)

- [ ] **Step 6: Run the full suite**

Run: `bundle exec rspec`
Expected: PASS, no regressions.

- [ ] **Step 7: Commit**

```bash
git add app/models/rcrewai/rails/span.rb app/views/rcrewai/rails/observations/show.html.erb spec/models/span_broadcast_spec.rb
git commit -m "feat: broadcast span changes for live trace monitoring"
```

---

## Task 16: Deprecate ExecutionLog and document

**Files:**
- Modify: `app/models/rcrewai/rails/execution.rb`
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Test: `spec/models/execution_deprecation_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/models/execution_deprecation_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "ExecutionLog deprecation" do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "c") }
  let(:execution) { crew.executions.create!(status: "running", started_at: Time.current) }

  it "still writes log rows" do
    expect { execution.log("info", "hello") }.to change(RcrewAI::Rails::ExecutionLog, :count).by(1)
  end

  it "warns that the method is deprecated" do
    expect(RcrewAI::Rails).to receive(:deprecator_warn).with(/ExecutionLog/)
    execution.log("info", "hello")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/execution_deprecation_spec.rb`
Expected: FAIL — no `deprecator_warn`

- [ ] **Step 3: Add the deprecation helper**

In `lib/rcrewai/rails.rb`, inside `module RcrewAI; module Rails`:

```ruby
    def self.deprecator_warn(message)
      if defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger
        ::Rails.logger.warn("[rcrewai-rails] DEPRECATION: #{message}")
      else
        Kernel.warn("[rcrewai-rails] DEPRECATION: #{message}")
      end
    end
```

- [ ] **Step 4: Deprecate the method**

In `app/models/rcrewai/rails/execution.rb`, change `log` to:

```ruby
      # Deprecated: superseded by the observation engine's span tree.
      # Scheduled for removal one minor version after the engine ships.
      def log(level, message, details = {})
        RcrewAI::Rails.deprecator_warn(
          "Execution#log and ExecutionLog are deprecated; use the observation engine (Execution#spans)."
        )
        execution_logs.create!(
          level: level,
          message: message,
          details: details,
          timestamp: Time.current
        )
      end
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bundle exec rspec spec/models/execution_deprecation_spec.rb`
Expected: PASS (2 examples)

- [ ] **Step 6: Document in the README**

Add a section after the Features list:

````markdown
### Observation Engine

Every crew execution is traced as a tree of spans — crew, agent, task, LLM call,
and tool call — with timings, token counts, and cost.

- **Trace view** at `/rcrewai/executions/:id/observation` — a waterfall of the run,
  with prompts, tool arguments, and errors on each span.
- **Cost and performance** at `/rcrewai/observations/costs` — spend and token
  totals across recent executions.
- **Live monitoring** — the trace view updates over Turbo Streams while a run is
  in progress.

Configure in `config/initializers/rcrewai.rb`:

```ruby
config.observation_enabled = true
config.observation_capture_prompts = :truncated  # :none | :truncated | :full
config.observation_prompt_max_bytes = 4_096
config.observation_flush_mode = :batched         # :batched | :immediate
config.observation_retention_days = 30
```

Prompt text is truncated by default because full prompts can be large and may
contain personal data. Set `:full` only when you need lossless replay.

Prune old spans on a schedule:

```bash
rake rcrewai:observation:prune        # uses observation_retention_days
rake rcrewai:observation:prune DAYS=7
```

**Requires rcrewai >= 0.7.1**, which threads the event stream down to agent
execution. On earlier versions traces contain only crew-level spans.
````

- [ ] **Step 7: Update the CHANGELOG**

Add at the top under a new Unreleased heading:

```markdown
## [Unreleased]

### Added
- Observation engine: span-tree tracing of crew executions with per-agent,
  per-LLM-call, and per-tool-call detail.
- Trace waterfall, cost/performance dashboard, and live Turbo Stream monitoring.
- `rcrewai:observation:prune` rake task and retention configuration.

### Deprecated
- `Execution#log` and `ExecutionLog`, superseded by the observation engine.
  Scheduled for removal one minor version after this release.

### Requires
- rcrewai >= 0.7.1 for agent-level tracing.
```

- [ ] **Step 8: Run the full suite**

Run: `bundle exec rspec`
Expected: PASS across all specs.

- [ ] **Step 9: Commit**

```bash
git add app/models/rcrewai/rails/execution.rb lib/rcrewai/rails.rb README.md CHANGELOG.md spec/models/execution_deprecation_spec.rb
git commit -m "feat: deprecate ExecutionLog and document the observation engine"
```

---

## Verification Checklist

After all tasks, confirm:

- [ ] `cd /Users/gkosmo/code/gkosmo/rcrewAI && bundle exec rspec` — upstream green
- [ ] `bundle exec rspec` — engine green
- [ ] Migration columns match across all three locations: `db/migrate/010`+`011`, the install template, and `spec/internal/db/schema.rb`
- [ ] `RcrewAI::Rails.config.observation_enabled = false` produces zero spans
- [ ] A crew run with two concurrent agents produces a correctly nested tree with no orphaned `running` spans
