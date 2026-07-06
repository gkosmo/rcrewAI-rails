# Group C2 — Batch Crew Execution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose `kickoff_for_each` (batch execution) through the Rails engine: run a crew once per input set, mapping each run onto its own `Execution` record grouped by a shared `batch_id`.

**Architecture:** Add a nullable `batch_id` column to `rcrewai_executions` (host migration + install generator + Combustion test schema). Extend the existing `CrewExecutionJob#perform` with an optional `batch_id:` kwarg (one execution code path; existing callers unaffected). Add `execute_batch_async` / `execute_batch_sync` / `batch_executions` to the Crew model, generating one shared UUID per batch. Behavior mirrors CrewAI's `kickoff_for_each`: N inputs → N ordered runs, one result each.

**Tech Stack:** Ruby, Rails engine, ActiveJob, RSpec + Combustion (schema from `spec/internal/db/schema.rb`, not migrations), rcrewai 0.5.0.

---

## File Structure

- **Modify** `spec/internal/db/schema.rb` — add `batch_id` column + index to the `rcrewai_executions` block.
- **Modify** `spec/jobs/crew_execution_job_spec.rb` — add a batch_id stamping spec.
- **Modify** `spec/models/crew_spec.rb` — add batch execution specs.
- **Modify** `app/jobs/rcrewai/rails/crew_execution_job.rb` — add `batch_id:` kwarg to `perform`.
- **Modify** `app/models/rcrewai/rails/crew.rb` — `execute_batch_async` / `execute_batch_sync` / `batch_executions`.
- **Create** `db/migrate/005_add_batch_id_to_rcrewai_executions.rb` — host migration.
- **Modify** `lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb` — generator template.

---

### Task 1: Add batch_id to the test schema + failing job spec

**Files:**
- Modify: `spec/internal/db/schema.rb` (the `create_table :rcrewai_executions` block)
- Modify: `spec/jobs/crew_execution_job_spec.rb`

- [ ] **Step 1: Add the column + index to the Combustion test schema**

In `spec/internal/db/schema.rb`, inside the `create_table :rcrewai_executions, force: true do |t|` block, add this line immediately after the existing `t.integer :duration_seconds` line:

```ruby
    t.string :batch_id
```

Then, right after the existing `add_index :rcrewai_executions, :created_at` line (outside the create_table block), add:

```ruby
  add_index :rcrewai_executions, :batch_id
```

- [ ] **Step 2: Write the failing job spec**

In `spec/jobs/crew_execution_job_spec.rb`, add this example inside the top-level `RSpec.describe RcrewAI::Rails::CrewExecutionJob` block (after the existing examples, before the final `end`):

```ruby
  it "stamps batch_id on the execution when given one" do
    agent = crew.agents.create!(name: "a", role: "Worker")
    crew.tasks.create!(description: "do it", expected_output: "ok", agent: agent)

    described_class.new.perform(crew, {}, batch_id: "batch-xyz")

    execution = crew.executions.order(:id).last
    expect(execution.batch_id).to eq("batch-xyz")
  end

  it "leaves batch_id nil for a normal run" do
    agent = crew.agents.create!(name: "a", role: "Worker")
    crew.tasks.create!(description: "do it", expected_output: "ok", agent: agent)

    described_class.new.perform(crew)

    execution = crew.executions.order(:id).last
    expect(execution.batch_id).to be_nil
  end
```

- [ ] **Step 3: Run the job spec — confirm the batch_id example fails on BEHAVIOR, not schema**

Run: `bundle exec rspec spec/jobs/crew_execution_job_spec.rb`
Expected: NO `ActiveModel::UnknownAttributeError` (schema now has `batch_id`). The "stamps batch_id" example FAILS because `perform` does not accept/persist `batch_id` yet (likely an `ArgumentError: unknown keyword: :batch_id`). The "leaves batch_id nil" example PASSES.

If you see `UnknownAttributeError`, the Step 1 schema edit is wrong — fix it before continuing. Do NOT modify the job (that is Task 2).

- [ ] **Step 4: Commit**

```bash
git add spec/internal/db/schema.rb spec/jobs/crew_execution_job_spec.rb
git commit -m "Add batch_id column + failing job spec"
```

---

### Task 2: Add batch_id kwarg to the job

**Files:**
- Modify: `app/jobs/rcrewai/rails/crew_execution_job.rb`

- [ ] **Step 1: Add the kwarg and persist it**

In `app/jobs/rcrewai/rails/crew_execution_job.rb`, change the `perform` signature and the `create!` call. Replace:

```ruby
      def perform(crew, inputs = {})
        execution = crew.executions.create!(
          status: "pending",
          inputs: inputs
        )
```

with:

```ruby
      def perform(crew, inputs = {}, batch_id: nil)
        execution = crew.executions.create!(
          status: "pending",
          inputs: inputs,
          batch_id: batch_id
        )
```

Leave the rest of the method (start!/execute/complete!/fail!, logs, streaming, notify, and the `result` return) exactly as-is.

- [ ] **Step 2: Run the job spec — expect green**

Run: `bundle exec rspec spec/jobs/crew_execution_job_spec.rb`
Expected: PASS — all examples green, including both new batch_id examples.

- [ ] **Step 3: Run the full suite**

Run: `bundle exec rspec`
Expected: PASS — 65 examples, 0 failures (63 prior + 2 new).

- [ ] **Step 4: Commit**

```bash
git add app/jobs/rcrewai/rails/crew_execution_job.rb
git commit -m "Accept optional batch_id in CrewExecutionJob#perform"
```

---

### Task 3: Add batch execution methods to the Crew model (failing specs first)

**Files:**
- Modify: `spec/models/crew_spec.rb`
- Modify: `app/models/rcrewai/rails/crew.rb`

- [ ] **Step 1: Write the failing model specs**

In `spec/models/crew_spec.rb`, add this NEW `describe` block as a SIBLING of the existing top-level describes (after the last one, before the final top-level `end`). It defines its own setup and needs a real agent+task so the stubbed LLM produces a completed run:

```ruby
  describe "batch execution" do
    let(:batch_crew) do
      c = RcrewAI::Rails::Crew.create!(name: "Batch", process_type: "sequential")
      agent = c.agents.create!(name: "a", role: "Worker")
      c.tasks.create!(description: "do it", expected_output: "ok", agent: agent)
      c
    end

    describe "#execute_batch_sync" do
      it "creates one completed execution per input, sharing a batch_id" do
        result = batch_crew.execute_batch_sync([{ topic: "a" }, { topic: "b" }])

        execs = batch_crew.executions.where(batch_id: result[:batch_id])
        expect(execs.count).to eq(2)
        expect(execs.pluck(:status).uniq).to eq(["completed"])
        expect(result[:batch_id]).to be_a(String)
        expect(result[:executions].length).to eq(2)
      end

      it "preserves each input on its own execution" do
        batch_crew.execute_batch_sync([{ "topic" => "a" }, { "topic" => "b" }])

        topics = batch_crew.executions.order(:created_at, :id).map { |e| e.inputs["topic"] }
        expect(topics).to eq(["a", "b"])
      end
    end

    describe "#batch_executions" do
      it "returns the executions for a batch ordered by created_at" do
        result = batch_crew.execute_batch_sync([{ topic: "a" }, { topic: "b" }])

        rows = batch_crew.batch_executions(result[:batch_id])
        expect(rows.map(&:batch_id).uniq).to eq([result[:batch_id]])
        expect(rows.count).to eq(2)
      end
    end

    describe "#execute_batch_async" do
      it "enqueues one job per input and returns a String batch_id" do
        ActiveJob::Base.queue_adapter = :test

        batch_id = nil
        expect {
          batch_id = batch_crew.execute_batch_async([{ topic: "a" }, { topic: "b" }])
        }.to have_enqueued_job(RcrewAI::Rails::CrewExecutionJob).twice

        expect(batch_id).to be_a(String)
      end
    end

    it "leaves batch_id nil for a normal execute_sync run" do
      batch_crew.execute_sync({ topic: "solo" })

      expect(batch_crew.executions.order(:created_at).last.batch_id).to be_nil
    end
  end
```

- [ ] **Step 2: Run the model spec — confirm behavioral failures**

Run: `bundle exec rspec spec/models/crew_spec.rb`
Expected: the `execute_batch_sync` / `batch_executions` / `execute_batch_async` examples FAIL with `NoMethodError` (methods not defined yet). The "leaves batch_id nil for a normal execute_sync run" example PASSES. No `UnknownAttributeError`.

- [ ] **Step 3: Add the methods to the Crew model**

In `app/models/rcrewai/rails/crew.rb`, add these three public methods next to the existing `execute_async` / `execute_sync` (keep them public — they are the model's API). Place them right after the existing `execute_sync` method:

```ruby
      def execute_batch_async(inputs_list)
        batch_id = SecureRandom.uuid
        Array(inputs_list).each do |inputs|
          CrewExecutionJob.perform_later(self, inputs, batch_id: batch_id)
        end
        batch_id
      end

      def execute_batch_sync(inputs_list)
        batch_id = SecureRandom.uuid
        Array(inputs_list).each do |inputs|
          CrewExecutionJob.perform_now(self, inputs, batch_id: batch_id)
        end
        { batch_id: batch_id, executions: batch_executions(batch_id).to_a }
      end

      def batch_executions(batch_id)
        executions.where(batch_id: batch_id).order(:created_at, :id)
      end
```

Note: `SecureRandom` is available in Rails without an explicit require. CAUTION: `Array()` destructures a bare Hash (`Array({a: 1})` → `[[:a, 1]]`, NOT `[{a: 1}]`), so a single-hash input must be guarded explicitly — see the `normalize_batch_inputs` helper added in the review fix, which does `inputs_list.is_a?(Hash) ? [inputs_list] : Array(inputs_list)`.

Ordering note: `order(:created_at, :id)` uses `id` as a deterministic tiebreaker. Two executions created in the same synchronous loop can share a `created_at` value at the column's timestamp precision; `id` (monotonic autoincrement) guarantees stable creation order regardless. This is why the "preserves each input" test can safely assert `["a", "b"]`.

- [ ] **Step 4: Run the model spec — expect green**

Run: `bundle exec rspec spec/models/crew_spec.rb`
Expected: PASS — all examples green.

- [ ] **Step 5: Run the full suite**

Run: `bundle exec rspec`
Expected: PASS — 70 examples, 0 failures (65 after Task 2 + 5 new).

- [ ] **Step 6: Commit**

```bash
git add spec/models/crew_spec.rb app/models/rcrewai/rails/crew.rb
git commit -m "Add batch execution methods to Crew model"
```

---

### Task 4: Ship the host-app migration

**Files:**
- Create: `db/migrate/005_add_batch_id_to_rcrewai_executions.rb`

- [ ] **Step 1: Write the migration**

Create `db/migrate/005_add_batch_id_to_rcrewai_executions.rb`:

```ruby
class AddBatchIdToRcrewaiExecutions < ActiveRecord::Migration[7.0]
  def change
    add_column :rcrewai_executions, :batch_id, :string
    add_index :rcrewai_executions, :batch_id
  end
end
```

- [ ] **Step 2: Verify syntax**

Run: `ruby -c db/migrate/005_add_batch_id_to_rcrewai_executions.rb`
Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add db/migrate/005_add_batch_id_to_rcrewai_executions.rb
git commit -m "Add host-app migration for execution batch_id"
```

---

### Task 5: Update the install-generator template

**Files:**
- Modify: `lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb` (the `create_table :rcrewai_executions` block)

- [ ] **Step 1: Add the column + index to the generator template**

In `lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb`, find the `create_table :rcrewai_executions do |t|` block. Add this line immediately after the existing `t.integer :duration_seconds` line (6-space indentation):

```ruby
      t.string :batch_id
```

Then find the existing `add_index :rcrewai_executions, :created_at` line and add immediately after it (4-space indentation, matching sibling add_index lines):

```ruby
    add_index :rcrewai_executions, :batch_id
```

- [ ] **Step 2: Verify syntax**

Run: `ruby -c lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb`
Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb
git commit -m "Include execution batch_id in install generator"
```

---

### Task 6: Full-suite verification + schema consistency

**Files:** none (verification only)

- [ ] **Step 1: Run the full suite**

Run: `bundle exec rspec`
Expected: `70 examples, 0 failures`.

- [ ] **Step 2: Confirm batch_id consistency across the three definitions**

Run: `grep -n "batch_id" spec/internal/db/schema.rb db/migrate/005_add_batch_id_to_rcrewai_executions.rb lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb`
Expected: each file has both a column definition (`t.string :batch_id` / `add_column ... :batch_id, :string`) and an index (`add_index :rcrewai_executions, :batch_id`). No commit — this is a check.

---

## Notes / Out of scope

- **train / test** — deferred (better suited to a rake/CLI feature).
- **Web UI** for viewing batches — follow-up.
- **Group D** (Flows / Knowledge-RAG) — separate spec.
- **Retry + batch_id:** the job's `retry_on` creates a fresh execution per attempt (pre-existing behavior); a batch's execution count may exceed its input count if retries fire. Documented in the spec, not changed here.
