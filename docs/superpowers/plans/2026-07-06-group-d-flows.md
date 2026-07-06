# Group D (Flows) — AR State Store + Run Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide an ActiveRecord-backed state store (`RcrewAI::Rails::ActiveRecordStateStore` + `FlowState`) so rcrewai Flows persist/resume via the DB, and a `FlowRun` record that tracks each flow kickoff.

**Architecture:** Users define Flow subclasses in their own app (Ruby). The engine adds two tables. `rcrewai_flow_states` holds `{state_id, data}` and backs a store implementing the core's `save(id, hash)`/`load(id)` contract. `rcrewai_flow_runs` tracks each kickoff (status/state_id/inputs/result/timing) with a `FlowRun.execute(FlowClass, inputs:)` helper mirroring the existing `Execution` lifecycle. No graph modeling, no job, no generator (deferred).

**Tech Stack:** Ruby, Rails engine (Zeitwerk-autoloaded `app/`), RSpec + Combustion (schema from `spec/internal/db/schema.rb`), rcrewai 0.5.0.

---

## File Structure

- **Modify** `spec/internal/db/schema.rb` — add `rcrewai_flow_states` + `rcrewai_flow_runs` tables.
- **Create** `spec/models/flow_state_spec.rb` — FlowState + ActiveRecordStateStore specs (incl. real-Flow integration).
- **Create** `spec/models/flow_run_spec.rb` — FlowRun specs.
- **Create** `app/models/rcrewai/rails/flow_state.rb` — the state AR model.
- **Create** `app/models/rcrewai/rails/active_record_state_store.rb` — the store (plain class).
- **Create** `app/models/rcrewai/rails/flow_run.rb` — the run AR model + `execute` helper.
- **Create** `db/migrate/007_create_rcrewai_flows.rb` — host migration (both tables).
- **Modify** `lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb` — generator (both tables).

---

### Task 1: State store table + FlowState model + ActiveRecordStateStore

**Files:**
- Modify: `spec/internal/db/schema.rb`
- Create: `spec/models/flow_state_spec.rb`
- Create: `app/models/rcrewai/rails/flow_state.rb`
- Create: `app/models/rcrewai/rails/active_record_state_store.rb`

- [ ] **Step 1: Add the flow_states table to the test schema**

In `spec/internal/db/schema.rb`, add this block at the END of the schema (after the last existing table's `end`, before the final `end` that closes `ActiveRecord::Schema.define`). Match 2-space indentation:

```ruby
  create_table :rcrewai_flow_states, force: true do |t|
    t.string :state_id, null: false
    t.text :data, null: false
    t.timestamps
  end
  add_index :rcrewai_flow_states, :state_id, unique: true
```

- [ ] **Step 2: Write the failing state-store spec**

Create `spec/models/flow_state_spec.rb`. Note the top-level Flow subclass constant (needed for the integration test and for a resolvable class name):

```ruby
require "rails_helper"

# A tiny real Flow subclass for integration tests. Flow methods are plain Ruby.
class FlowStateSpecFlow < RCrewAI::Flow
  start :go
  def go
    state.ran = true
    state.count = 41
  end
end

RSpec.describe RcrewAI::Rails::ActiveRecordStateStore, type: :model do
  let(:store) { described_class.new }

  it "round-trips a hash by id" do
    store.save("abc", { "a" => 1, "b" => "two" })
    expect(store.load("abc")).to eq({ "a" => 1, "b" => "two" })
  end

  it "updates rather than duplicating on repeat save" do
    store.save("abc", { "n" => 1 })
    store.save("abc", { "n" => 2 })

    expect(store.load("abc")).to eq({ "n" => 2 })
    expect(RcrewAI::Rails::FlowState.where(state_id: "abc").count).to eq(1)
  end

  it "returns nil for an unknown id" do
    expect(store.load("missing")).to be_nil
  end

  it "persists and restores a real Flow's state through the DB" do
    flow = FlowStateSpecFlow.new(state_store: store)
    result = flow.kickoff

    expect(RcrewAI::Rails::FlowState.find_by(state_id: result.id)).to be_present

    restored = FlowStateSpecFlow.new(state_store: store)
    state = restored.restore(result.id)
    expect(state.ran).to eq(true)
    expect(state.count).to eq(41)
  end
end

RSpec.describe RcrewAI::Rails::FlowState, type: :model do
  it "validates state_id presence and uniqueness" do
    RcrewAI::Rails::FlowState.create!(state_id: "dup", data: { "x" => 1 })

    missing = RcrewAI::Rails::FlowState.new(data: { "x" => 1 })
    expect(missing).not_to be_valid

    dup = RcrewAI::Rails::FlowState.new(state_id: "dup", data: { "x" => 1 })
    expect(dup).not_to be_valid
  end
end
```

- [ ] **Step 3: Run the spec — confirm it fails on the missing constants, not schema**

Run: `bundle exec rspec spec/models/flow_state_spec.rb`
Expected: FAIL — `NameError: uninitialized constant RcrewAI::Rails::ActiveRecordStateStore` (and/or `FlowState`). NOT "no such table". If you see "no such table: rcrewai_flow_states", fix the Step 1 schema edit.

- [ ] **Step 4: Create the FlowState model**

Create `app/models/rcrewai/rails/flow_state.rb`:

```ruby
module RcrewAI
  module Rails
    class FlowState < ApplicationRecord
      self.table_name = "rcrewai_flow_states"

      serialize :data, coder: JSON

      validates :state_id, presence: true, uniqueness: true
    end
  end
end
```

- [ ] **Step 5: Create the ActiveRecordStateStore**

Create `app/models/rcrewai/rails/active_record_state_store.rb`:

```ruby
module RcrewAI
  module Rails
    # Persists rcrewai Flow state to the DB. Implements the core state-store
    # contract: save(id, hash) / load(id) => hash or nil. Pass an instance as
    # +state_store:+ when constructing a Flow.
    class ActiveRecordStateStore
      def save(id, hash)
        record = FlowState.find_or_initialize_by(state_id: id)
        record.data = hash
        record.save!
      end

      def load(id)
        FlowState.find_by(state_id: id)&.data
      end
    end
  end
end
```

- [ ] **Step 6: Run the spec — expect green**

Run: `bundle exec rspec spec/models/flow_state_spec.rb`
Expected: PASS — all examples green (round-trip, update, nil, real-Flow integration, validations).

- [ ] **Step 7: Run the full suite**

Run: `bundle exec rspec`
Expected: PASS — 93 examples, 0 failures (88 prior + 5 new).

- [ ] **Step 8: Commit**

```bash
git add spec/internal/db/schema.rb spec/models/flow_state_spec.rb app/models/rcrewai/rails/flow_state.rb app/models/rcrewai/rails/active_record_state_store.rb
git commit -m "Add ActiveRecord flow state store"
```

---

### Task 2: FlowRun table + model + execute helper

**Files:**
- Modify: `spec/internal/db/schema.rb`
- Create: `spec/models/flow_run_spec.rb`
- Create: `app/models/rcrewai/rails/flow_run.rb`

- [ ] **Step 1: Add the flow_runs table to the test schema**

In `spec/internal/db/schema.rb`, add this block immediately after the `add_index :rcrewai_flow_states, :state_id, unique: true` line (from Task 1), still before the final `end`:

```ruby
  create_table :rcrewai_flow_runs, force: true do |t|
    t.string :flow_class, null: false
    t.string :state_id
    t.string :status, null: false
    t.text :inputs
    t.text :result
    t.string :error_message
    t.datetime :started_at
    t.datetime :completed_at
    t.timestamps
  end
  add_index :rcrewai_flow_runs, :status
  add_index :rcrewai_flow_runs, :state_id
```

- [ ] **Step 2: Write the failing FlowRun spec**

Create `spec/models/flow_run_spec.rb`:

```ruby
require "rails_helper"

class FlowRunSpecFlow < RCrewAI::Flow
  start :go
  def go
    state.topic = "ruby"
    state.done = true
  end
end

class FlowRunBoomFlow < RCrewAI::Flow
  start :go
  def go
    raise "kaboom"
  end
end

RSpec.describe RcrewAI::Rails::FlowRun, type: :model do
  describe ".execute" do
    it "creates a completed run with the final state" do
      run = described_class.execute(FlowRunSpecFlow, inputs: { seed: "x" })

      expect(run.status).to eq("completed")
      expect(run.flow_class).to eq("FlowRunSpecFlow")
      expect(run.state_id).to be_present
      expect(run.result["topic"]).to eq("ruby")
      expect(run.result["done"]).to eq(true)
      expect(run.inputs).to eq({ "seed" => "x" })
    end

    it "accepts a String flow class name" do
      run = described_class.execute("FlowRunSpecFlow")
      expect(run.status).to eq("completed")
      expect(run.flow_class).to eq("FlowRunSpecFlow")
    end

    it "persists the flow state so it is queryable by state_id" do
      run = described_class.execute(FlowRunSpecFlow)
      expect(RcrewAI::Rails::FlowState.find_by(state_id: run.state_id)).to be_present
    end

    it "records a failure and re-raises when the flow raises" do
      expect {
        described_class.execute(FlowRunBoomFlow)
      }.to raise_error("kaboom")

      run = described_class.where(flow_class: "FlowRunBoomFlow").order(:id).last
      expect(run.status).to eq("failed")
      expect(run.error_message).to eq("kaboom")
    end
  end

  describe "validations and scopes" do
    it "validates flow_class presence and status inclusion" do
      bad = described_class.new(flow_class: nil, status: "weird")
      expect(bad).not_to be_valid
      expect(bad.errors[:flow_class]).to be_present
      expect(bad.errors[:status]).to be_present
    end

    it "scopes successful and failed" do
      ok = described_class.create!(flow_class: "X", status: "completed")
      bad = described_class.create!(flow_class: "X", status: "failed")

      expect(described_class.successful).to include(ok)
      expect(described_class.successful).not_to include(bad)
      expect(described_class.failed).to include(bad)
    end
  end
end
```

- [ ] **Step 3: Run the spec — confirm behavioral failure**

Run: `bundle exec rspec spec/models/flow_run_spec.rb`
Expected: FAIL — `NameError: uninitialized constant RcrewAI::Rails::FlowRun`. NOT "no such table" (the table now exists).

- [ ] **Step 4: Create the FlowRun model**

Create `app/models/rcrewai/rails/flow_run.rb`:

```ruby
module RcrewAI
  module Rails
    class FlowRun < ApplicationRecord
      self.table_name = "rcrewai_flow_runs"

      serialize :inputs, coder: JSON
      serialize :result, coder: JSON

      validates :flow_class, presence: true
      validates :status, inclusion: { in: %w[pending running completed failed] }

      scope :successful, -> { where(status: "completed") }
      scope :failed, -> { where(status: "failed") }

      # Runs a Flow subclass (a Class or its String name) with an AR-backed state
      # store, wrapped in a run record. Returns the run. Re-raises on failure
      # after recording it.
      def self.execute(flow_class, inputs: {})
        klass = flow_class.is_a?(String) ? flow_class.constantize : flow_class
        run = create!(flow_class: klass.name, status: "pending", inputs: inputs)
        run.run!(klass, inputs)
        run
      end

      def run!(klass, inputs)
        update!(status: "running", started_at: Time.current)
        flow = klass.new(state_store: ActiveRecordStateStore.new)
        state = flow.kickoff(inputs: inputs)
        update!(
          status: "completed",
          state_id: state.id,
          result: state.to_h,
          completed_at: Time.current
        )
      rescue => e
        update!(status: "failed", error_message: e.message, completed_at: Time.current)
        raise
      end
    end
  end
end
```

- [ ] **Step 5: Run the spec — expect green**

Run: `bundle exec rspec spec/models/flow_run_spec.rb`
Expected: PASS — all examples green.

- [ ] **Step 6: Run the full suite**

Run: `bundle exec rspec`
Expected: PASS — 99 examples, 0 failures (93 after Task 1 + 6 new).

- [ ] **Step 7: Commit**

```bash
git add spec/internal/db/schema.rb spec/models/flow_run_spec.rb app/models/rcrewai/rails/flow_run.rb
git commit -m "Add FlowRun model with execute helper"
```

---

### Task 3: Ship the host-app migration

**Files:**
- Create: `db/migrate/007_create_rcrewai_flows.rb`

- [ ] **Step 1: Write the migration**

Create `db/migrate/007_create_rcrewai_flows.rb`:

```ruby
class CreateRcrewaiFlows < ActiveRecord::Migration[7.0]
  def change
    create_table :rcrewai_flow_states do |t|
      t.string :state_id, null: false
      t.text :data, null: false
      t.timestamps
    end
    add_index :rcrewai_flow_states, :state_id, unique: true

    create_table :rcrewai_flow_runs do |t|
      t.string :flow_class, null: false
      t.string :state_id
      t.string :status, null: false
      t.text :inputs
      t.text :result
      t.string :error_message
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :rcrewai_flow_runs, :status
    add_index :rcrewai_flow_runs, :state_id
  end
end
```

- [ ] **Step 2: Verify syntax**

Run: `ruby -c db/migrate/007_create_rcrewai_flows.rb`
Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add db/migrate/007_create_rcrewai_flows.rb
git commit -m "Add host-app migration for flow states and runs"
```

---

### Task 4: Update the install-generator template

**Files:**
- Modify: `lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb`

- [ ] **Step 1: Add both tables to the generator template**

In `lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb`, add these two `create_table` blocks immediately after the LAST existing statement in the `change` method (the `create_table :rcrewai_knowledge_sources` block's `end`) and BEFORE the `end` that closes `change`. Match the block's 4-space `create_table` indentation:

```ruby
    create_table :rcrewai_flow_states do |t|
      t.string :state_id, null: false
      t.text :data, null: false

      t.timestamps
    end
    add_index :rcrewai_flow_states, :state_id, unique: true

    create_table :rcrewai_flow_runs do |t|
      t.string :flow_class, null: false
      t.string :state_id
      t.string :status, null: false
      t.text :inputs
      t.text :result
      t.string :error_message
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end
    add_index :rcrewai_flow_runs, :status
    add_index :rcrewai_flow_runs, :state_id
```

- [ ] **Step 2: Verify syntax**

Run: `ruby -c lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb`
Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb
git commit -m "Include flow tables in install generator"
```

---

### Task 5: Full-suite verification + schema consistency + changelog

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Run the full suite**

Run: `bundle exec rspec`
Expected: `99 examples, 0 failures`.

- [ ] **Step 2: Confirm the two tables are consistent across the three definitions**

Run: `grep -n "rcrewai_flow_states\|rcrewai_flow_runs\|flow_class\|state_id" spec/internal/db/schema.rb db/migrate/007_create_rcrewai_flows.rb lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb`
Expected: both tables + their columns appear in all three files.

- [ ] **Step 3: Add the changelog entry**

In `CHANGELOG.md`, under the `## [Unreleased]` heading (currently empty at the top), add an `### Added` section with this bullet:

```markdown
### Added
- Flows persistence: `RcrewAI::Rails::ActiveRecordStateStore` backs rcrewai Flow
  state with a `rcrewai_flow_states` table so flows resume from the DB
  (`flow.restore(state_id)`), and `RcrewAI::Rails::FlowRun` records each kickoff
  (status, state id, inputs, result, timing) via `FlowRun.execute(FlowClass,
  inputs:)`. Flow subclasses are still defined in the host app; the engine adds
  the persistence layer (#13).
```

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md
git commit -m "Document Flows persistence in the changelog"
```

---

## Notes / Out of scope

- **Background job / async flow runs** — deferred; `FlowRun.execute` runs inline.
- **Flow-scaffolding generator** — deferred.
- **Graph modeling** — a Flow is code; only state/runs are persisted.
- **Flow ↔ Crew step persistence** — not re-plumbed here.
