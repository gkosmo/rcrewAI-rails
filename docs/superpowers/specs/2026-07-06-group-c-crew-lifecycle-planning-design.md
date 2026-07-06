# Group C — Crew lifecycle hooks + planning (rcrewai 0.5.0)

**Date:** 2026-07-06
**Status:** Draft — awaiting user review
**Scope:** Third of the decomposed parity effort. Follows Group A (agent config,
PR #6) and Group B (task output, PR #7).

## Context

Groups A and B established the pattern: add columns across three synchronized
schema definitions (host migration, install-generator template, Combustion test
schema), and forward options through a `*_options` helper that emits a key only
when meaningfully set — byte-identical construction for all-default records.
Callables that can't live in a DB row (guardrail, callback) are persisted as
`*_class` + `*_method` columns and resolved at build time. Group C applies the
same patterns to `Crew`.

## Scope

**In scope:** the 0.5.0 crew-level options that are pure builder concerns —
- `before_kickoff` / `after_kickoff` lifecycle hooks
- `planning` / `planning_llm`

**Deferred to a later spec (Group C2):**
- `kickoff_for_each` (batch) — needs a decision on how N results map onto
  `Execution` records (one Execution per input vs. one holding an array). That is
  a persistence-modeling choice best made interactively.
- `train` / `test` — CLI/experiment-shaped (interactive `feedback:`/`scorer:`
  callables, JSON file output); fits a persisted web engine awkwardly.

Keeping Group C to hooks + planning makes it a clean builder-only change, exactly
like A/B — no execution/job-layer changes required (see below).

## Grounding: the 0.5.0 Crew API

```ruby
def initialize(name, **options)
  @planning = options.fetch(:planning, false)   # planning pass before execution
  @planning_llm = options[:planning_llm]        # symbol/among; resolved via LLMClient.resolve
  ...
end

# Register callbacks; blocks run INSIDE #execute:
crew.before_kickoff { |inputs| transformed_inputs }   # run_before_hooks(inputs)
crew.after_kickoff  { |result| transformed_result }   # run_after_hooks(result)
```

Because hooks run inside the core `#execute` (which the Rails `CrewExecutionJob`
already calls via `rcrew.execute(...)`), registering hooks on the built crew is
sufficient — **no job-layer change is needed.** Group C stays a `to_rcrew`
change.

## Design

### Schema (new migration `004_add_lifecycle_to_rcrewai_crews.rb`)

```ruby
add_column :rcrewai_crews, :planning, :boolean, default: false, null: false
add_column :rcrewai_crews, :planning_llm, :string
add_column :rcrewai_crews, :before_kickoff_class, :string
add_column :rcrewai_crews, :before_kickoff_method, :string
add_column :rcrewai_crews, :after_kickoff_class, :string
add_column :rcrewai_crews, :after_kickoff_method, :string
```

Mirrored identically into `spec/internal/db/schema.rb` and the install-generator
template (Groups A/B consistency requirement).

### Model (`app/models/rcrewai/rails/crew.rb`)

```ruby
def to_rcrew
  crew = RCrewAI::Crew.new(
    name,
    process: process_type.to_sym,
    verbose: verbose,
    **crew_planning_options
  )

  agents.each { |agent| crew.add_agent(agent.to_rcrew_agent) }
  tasks.each  { |task|  crew.add_task(task.to_rcrew_task) }

  register_kickoff_hooks(crew)
  crew
end

# 0.5.0 planning options. Emit a key only when meaningfully set.
def crew_planning_options
  opts = {}
  opts[:planning] = planning if planning
  opts[:planning_llm] = planning_llm.to_sym if planning_llm.present?
  opts
end

private

# Registers before/after kickoff hooks resolved from *_class + *_method columns,
# mirroring the guardrail/callback pattern. No-op when unconfigured.
def register_kickoff_hooks(crew)
  if (before = hook_callable(before_kickoff_class, before_kickoff_method))
    crew.before_kickoff { |inputs| before.call(inputs) }
  end
  if (after = hook_callable(after_kickoff_class, after_kickoff_method))
    crew.after_kickoff { |result| after.call(result) }
  end
end

# Resolves a *_class + *_method pair to a callable; nil when either is blank.
def hook_callable(class_name, method_name)
  return nil unless class_name.present? && method_name.present?

  klass = class_name.constantize
  ->(arg) { klass.new.send(method_name, arg) }
end
```

Backward-compat: `crew_planning_options` returns `{}` and `register_kickoff_hooks`
registers nothing for an all-default crew, so `to_rcrew` is identical to today.

### Testing (TDD, mirrors A/B)

1. Regression guard — all-default crew: `RCrewAI::Crew.new` receives no
   `:planning`/`:planning_llm`, and no hooks are registered.
2. `planning: true` → `:planning` forwarded; `planning_llm` present → forwarded as
   a symbol.
3. `before_kickoff_class` + `before_kickoff_method` → a before-hook is registered
   that, when called with an inputs hash, calls through to the host class (assert
   the transformed value).
4. `after_kickoff_class` + `after_kickoff_method` → likewise for the after-hook.
5. Hook not registered when only the class (not the method) is set.

Hook registration is observable: the core `Crew` stores hooks in
`@before_kickoff_hooks`/`@after_kickoff_hooks`. Tests can either (a) spy on
`crew.before_kickoff`/`after_kickoff` to capture the block and invoke it, or
(b) run a minimal `crew.execute` with a stubbed process. Approach (a) is simpler
and preferred — assert the captured block calls through to the host class.

## Out of scope (explicit)

- Batch (`kickoff_for_each`), train/test — deferred to Group C2.
- Web UI controls for the new fields.
- Group D (Flows / Knowledge-RAG).

## Risks

- **Hook contract is the host's responsibility.** A `before_kickoff` host method
  must accept and return an inputs hash; `after_kickoff` a result. The Rails layer
  only resolves/forwards — same trust model as the existing callback/guardrail
  patterns.
- **`planning_llm` string → symbol.** The column stores a provider name string
  (e.g. `"anthropic"`); the core resolves via `LLMClient.resolve`, which accepts a
  symbol. `.to_sym` bridges it. A hash-form planning LLM is not supported through
  the column (single provider symbol only) — acceptable for this pass.
