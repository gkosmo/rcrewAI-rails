# Group D (Flows) — AR-backed flow state store + run persistence (rcrewai 0.4/0.5)

**Date:** 2026-07-06
**Status:** Draft — awaiting user review
**Scope:** Second Group D pillar. Surfaces rcrewai's Flow engine through the Rails
engine as a persistence layer: an ActiveRecord-backed state store and a flow-run
record. Knowledge/RAG (the other D pillar) shipped in #11.

## Context & the central constraint

rcrewai's `RCrewAI::Flow` is CrewAI's second pillar: an event-driven workflow
engine. Crucially, **a Flow is defined as a Ruby subclass with a class-level DSL**
(`start`, `listen`, `router`, `and_`/`or_`), with the workflow logic living in
method bodies bound via `method_added`. Unlike agents/tasks/crews — which are
*data* that map to AR rows — a Flow's essence is *code*. You cannot persist a
method body in a database column, and it would be wrong to try.

What DOES map cleanly to Rails is the core's **pluggable state store**: any object
with `#save(id, hash)` / `#load(id)`. rcrewai ships `MemoryStateStore` and
`FileStateStore`; the core calls `@state_store.save(@state.id, @state.to_h)` after
a run and reloads via `restore(id)` → `load(id)` → `State.new(symbolize(hash))`.

Decision taken (with the user): deliver an **AR-backed state store + run
persistence**. Users define Flow subclasses in their own app (Ruby, as the core
intends); the engine provides:
1. `RcrewAI::Rails::ActiveRecordStateStore` — persist/resume flow state in the DB.
2. `RcrewAI::Rails::FlowRun` — a record tracking each flow kickoff (status,
   state id, inputs, result, timing), mirroring how `Execution` tracks crew runs.

No attempt to model the flow graph in the DB. No background job / generator
(deferred — the "full orchestration" option we set aside).

## Grounding: the core Flow contract

```ruby
flow = MyFlow.new(state_store: store)   # store must respond to save(id, hash) / load(id)
flow.kickoff(inputs: { topic: "ruby" }) # runs graph to fixed point; persists via store; returns state
flow.restore(state_id)                  # rebuilds state from store.load(state_id)
flow.state.to_h                         # JSON-serializable attributes hash (includes :id)
```

`State#to_h` returns a symbol-keyed hash including the auto `:id` UUID; it is
JSON-safe for plain values. `restore` symbolizes string keys back.

## Design

### Part 1 — The state store

New table `rcrewai_flow_states` (migration `007`, generator, test schema):

```ruby
create_table :rcrewai_flow_states do |t|
  t.string :state_id, null: false
  t.text   :data, null: false
  t.timestamps
end
add_index :rcrewai_flow_states, :state_id, unique: true
```

New model `RcrewAI::Rails::FlowState` (`app/models/rcrewai/rails/flow_state.rb`):

```ruby
class FlowState < ApplicationRecord
  self.table_name = "rcrewai_flow_states"
  serialize :data, coder: JSON
  validates :state_id, presence: true, uniqueness: true
end
```

New store `RcrewAI::Rails::ActiveRecordStateStore`
(`app/models/rcrewai/rails/active_record_state_store.rb` — a plain object, not an
AR model, but co-located with models for autoload simplicity):

```ruby
class ActiveRecordStateStore
  # Core contract: save(id, hash) / load(id) => hash or nil
  def save(id, hash)
    record = FlowState.find_or_initialize_by(state_id: id)
    record.data = hash
    record.save!
  end

  def load(id)
    FlowState.find_by(state_id: id)&.data
  end
end
```

Usage in a host app: `MyFlow.new(state_store: RcrewAI::Rails::ActiveRecordStateStore.new)`.

Round-trip note: the core saves a symbol-keyed hash; JSON serialization stringifies
keys; `load` returns string-keyed data; the core's `restore` calls `symbolize` on
it. So `save`→`load` through JSON is lossless for the core's needs (it
re-symbolizes). Tests assert the store returns the data hash the core can restore
from.

### Part 2 — The flow run record

New table `rcrewai_flow_runs` (same migration `007`, generator, test schema):

```ruby
create_table :rcrewai_flow_runs do |t|
  t.string   :flow_class, null: false
  t.string   :state_id
  t.string   :status, null: false
  t.text     :inputs
  t.text     :result
  t.string   :error_message
  t.datetime :started_at
  t.datetime :completed_at
  t.timestamps
end
add_index :rcrewai_flow_runs, :status
add_index :rcrewai_flow_runs, :state_id
```

New model `RcrewAI::Rails::FlowRun` (`app/models/rcrewai/rails/flow_run.rb`),
mirroring `Execution`'s lifecycle:

```ruby
class FlowRun < ApplicationRecord
  self.table_name = "rcrewai_flow_runs"

  serialize :inputs, coder: JSON
  serialize :result, coder: JSON

  validates :flow_class, presence: true
  validates :status, inclusion: { in: %w[pending running completed failed] }

  scope :successful, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }

  # Runs a Flow subclass with an AR state store, wrapped in a run record.
  # flow_class: a Class (the user's Flow subclass) or its String name.
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
```

`FlowRun.execute(MyFlow, inputs: {...})` returns a completed (or failed) run
record; the persisted state is queryable via `FlowState.find_by(state_id:
run.state_id)`.

### Testing (TDD)

Flow methods are plain Ruby (no LLM), so tests define a tiny Flow subclass inline.

**State store:**
1. `save(id, hash)` then `load(id)` returns the data (round-trips a hash).
2. `save` twice with the same id updates (find_or_initialize), doesn't duplicate.
3. `load` of an unknown id returns nil.
4. Integration: a real Flow subclass with `ActiveRecordStateStore` — after
   `kickoff`, a `FlowState` row exists for `state.id`; a fresh flow instance
   `restore(state.id)` rebuilds the same state.

**FlowRun:**
5. `FlowRun.execute(SomeFlow, inputs: {...})` creates a `completed` run with
   `flow_class`, `state_id` set, and `result` = the final state hash.
6. Accepts a String flow_class (constantized).
7. On a flow that raises, the run is `failed` with `error_message`, and the error
   re-raises.
8. `FlowState` validations: `state_id` presence + uniqueness.

Define the in-spec Flow subclass as a top-level constant (so `constantize` works
for the String test), e.g. `class FlowsSpecFlow < RCrewAI::Flow; start :go; def go; state.ran = true; end; end`.

## Out of scope (explicit)

- **Background job** for async flow runs (like CrewExecutionJob) — deferred.
- **Flow-scaffolding generator** — deferred.
- **Modeling the flow graph** (start/listen/router structure) in the DB — a Flow
  is code; only its state/runs are persisted.
- **Flow ↔ Crew step persistence** — a flow can invoke a crew as a step; that
  crew's own execution persistence is Group C territory and not re-plumbed here.
- **Web UI** for flow runs.

## Risks

- **Non-JSON-serializable state values.** If a host's flow stores a non-JSON value
  (e.g. a Ruby object) in `state`, `serialize ..., JSON` will fail to round-trip.
  The core's own `FileStateStore` has the identical constraint (it JSON-encodes),
  so this matches core behavior, not a regression. Documented.
- **`flow_class.constantize`** trusts the stored/passed class name — same trust
  model as the existing callback/guardrail/hook patterns.
- **No background execution** means `FlowRun.execute` runs the flow inline
  (synchronously in the caller). For long flows a host should call it from their
  own job; the async wrapper is deferred by decision.
