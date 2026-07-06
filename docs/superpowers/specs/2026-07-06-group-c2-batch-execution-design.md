# Group C2 — Batch crew execution (rcrewai 0.5.0)

**Date:** 2026-07-06
**Status:** Draft — awaiting user review
**Scope:** Follow-on to Group C. Surfaces `kickoff_for_each` (batch execution)
through the Rails engine. Train/test are deferred (see below).

## Context

Group C surfaced crew lifecycle hooks + planning but deferred `kickoff_for_each`,
`train`, and `test` because they touch the execution/persistence layer rather
than being pure builder concerns. C2 handles batch execution. Decisions taken
(with the user):

- **Batch → N Executions + shared batch id.** Each input set becomes its own
  `Execution` row (reusing all existing per-run machinery: status, logs, timing,
  output), tagged with a shared `batch_id` so the batch is queryable together.
  Chosen over "one Execution holding an array" (loses per-input observability) and
  a dedicated parent table (more schema than needed).
- **Train/test deferred.** They are experiment/tooling-shaped — `train` needs an
  interactive human-feedback prompt and writes a JSON file; `test` needs a scorer
  and returns scores. Both fit a CLI/rake context better than a web/background-job
  engine. Revisit separately if wanted.

## CrewAI parity

Verified against CrewAI's own docs (docs.crewai.com/concepts/crews):
`kickoff_for_each(inputs=[{...}, {...}])` "executes tasks sequentially for each
provided input" and **returns a list of outputs, one per input, processed in
order**, with a thread-based async variant (`kickoff_for_each_async`). The
rcrewai 0.5.0 core mirrors this exactly (`Array(inputs).map { |i| execute(inputs:
i) }`). This design preserves that behavior: N inputs → N runs in order, each
producing an independent result/Execution, plus an async variant.

**Naming:** the Rails methods are `execute_batch_sync` / `execute_batch_async`
(not `kickoff_for_each`), matching the engine's existing `execute_sync` /
`execute_async` convention. The *behavior* matches CrewAI; the method names follow
the established Rails-engine API style rather than importing CrewAI's Python name.

## Grounding: the 0.5.0 core API

```ruby
# Runs the crew once per input set; returns one result per input, in order.
def kickoff_for_each(inputs:)
  Array(inputs).map { |input| execute(inputs: input) }
end
```

So batch = N independent `execute` calls. The Rails engine already runs each
`execute` through `CrewExecutionJob`, creating one `Execution` per call. C2 groups
N such executions under a generated `batch_id`.

## Current execution layer (what we build on)

`CrewExecutionJob#perform(crew, inputs = {})`:
1. `crew.executions.create!(status: "pending", inputs: inputs)`
2. `execution.start!` → `rcrew.execute(...)` → `execution.complete!(result)`
   (or `fail!` on error), plus logs, streaming sink, and a completion
   notification.
3. **Returns `result`** (the crew output), not the `Execution`.

`Crew#execute_async(inputs)` / `#execute_sync(inputs)` wrap
`CrewExecutionJob.perform_later/now`.

## Design

### Schema (new migration `005_add_batch_id_to_rcrewai_executions.rb`)

```ruby
add_column :rcrewai_executions, :batch_id, :string
add_index  :rcrewai_executions, :batch_id
```

`batch_id` is nullable — nil for normal single runs; a shared generated UUID for
each execution in a batch. Mirrored into `spec/internal/db/schema.rb` and the
install-generator template (three-way consistency).

### Job change (`app/jobs/rcrewai/rails/crew_execution_job.rb`)

Extend the existing job (no new job class — keep one execution code path):

```ruby
def perform(crew, inputs = {}, batch_id: nil)
  execution = crew.executions.create!(
    status: "pending",
    inputs: inputs,
    batch_id: batch_id
  )
  # ... unchanged: start!/execute/complete!/fail!, logs, streaming, notify ...
end
```

`batch_id` defaults to nil, so existing `execute_async`/`execute_sync` callers are
unaffected. Every input in a batch gets full independent observability
(status/logs/timing) — the point of the "N Executions" choice.

### Model (`app/models/rcrewai/rails/crew.rb`)

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
  executions.where(batch_id: batch_id).order(:created_at)
end
```

Notes:
- `execute_batch_async` returns the `batch_id` so the caller can later poll
  `batch_executions(batch_id)`.
- `execute_batch_sync` runs each job inline, then returns the batch id plus the
  N `Execution` records (fetched via `batch_executions`, since `perform_now`
  returns the crew *result*, not the execution).
- `Array(inputs_list)` tolerates a single hash or an array of hashes.

### Testing (TDD)

Batch execution uses the LLM stub already in the suite (`rails_helper`).

1. `execute_batch_sync([{a: 1}, {a: 2}])` creates exactly 2 `Execution` rows,
   both `completed`, sharing one non-nil `batch_id`, with `inputs` preserved per
   row.
2. The returned hash has `:batch_id` and an `:executions` array of length 2.
3. `batch_executions(batch_id)` returns the 2 rows ordered by `created_at`.
4. Regression: a normal `execute_sync({a: 1})` produces an execution with
   `batch_id` nil.
5. Job-level: `CrewExecutionJob.perform_now(crew, {a: 1}, batch_id: "b1")` stamps
   `batch_id: "b1"` on the created execution.
6. `execute_batch_async` enqueues N jobs (assert via ActiveJob test adapter /
   `have_enqueued_job` count) and returns a String batch id.

## Out of scope (explicit)

- **train / test** — deferred; better suited to a rake/CLI feature.
- **Web UI** for viewing batches.
- **Group D** (Flows / Knowledge-RAG).
- A dedicated batch parent table — deliberately avoided; `batch_id` grouping is
  enough for querying.

## Risks

- **Retries and batch_id.** `CrewExecutionJob` has `retry_on StandardError`. On
  retry the same job re-runs `perform` with the same `batch_id`, creating a NEW
  execution row (as it does today for single runs — the job already creates a
  fresh execution per attempt). This is pre-existing behavior, not introduced
  here; noted so the batch count is understood as "executions", which may exceed
  input count if retries fire. Acceptable for this pass.
- **Async batch result assembly** is the caller's job via `batch_executions`;
  the engine does not aggregate async results into a single object (there is no
  natural join point in a background-job model). Documented.
