# Group A — Agent-level configuration parity (rcrewai 0.5.0)

**Date:** 2026-07-03
**Status:** Draft — awaiting user review
**Scope:** First of a decomposed effort to bring `rcrewai-rails` to feature parity
with the additive changes in `rcrewai` 0.4.0 + 0.5.0.

## Context

`rcrewai-rails` currently targets `rcrewai ~> 0.3`. Compatibility with 0.5.0 has
been verified (constraint permits it; full spec suite green: 43 examples, 0
failures). The 0.4/0.5 releases are entirely additive, so no breaking migration
is required — the work is purely about *exposing* the new capabilities through
the Rails engine.

The full parity effort is decomposed into four groups:

- **Group A (this spec)** — agent-level config: `max_rpm`, `reasoning`,
  `respect_context_window`, per-agent `llm:`.
- **Group B** — task-level output processing: `output_schema`, `guardrail`,
  `output_file`/`markdown`, multimodal `attachments`.
- **Group C** — crew-level orchestration/lifecycle: `before_kickoff`/
  `after_kickoff`, `kickoff_for_each` (batch), `planning`, `train`/`test`.
- **Group D (separate specs)** — Flows and Knowledge/RAG. These introduce new
  AR-backed domain objects and each warrant their own brainstorming pass.

Groups build and ship independently, in order A → B → C.

## Goal

1. Expose 0.5.0 agent knobs through `RcrewAI::Rails::Agent`.
2. Fix a latent bug: the `max_rpm` and `llm_config` columns already exist on
   `rcrewai_agents` but are **never passed** to `RCrewAI::Agent.new`.
3. Preserve exact backward compatibility: an agent with all defaults must produce
   the same core-agent construction as today.

## Grounding: the 0.5.0 `Agent.new` API

```ruby
def initialize(name:, role:, goal:, backstory: nil, tools: [], **options)
  # options consumed (all optional, safe defaults):
  #   :reasoning                (default false)
  #   :max_reasoning_attempts   (default 3)
  #   :respect_context_window   (default false)
  #   :max_rpm                  (nil/0 => unlimited)
  #   :llm                      (symbol | hash | pre-built client) via LLMClient.resolve
```

`llm:` hash form is `{ provider:, model:, api_key:, temperature: }` — this maps
directly onto the existing JSON `llm_config` column.

## Design

### Schema

New migration template `db/migrate/*_add_agent_config_to_rcrewai_agents.rb`
(shipped via the engine's migration path; existing installs upgrade cleanly —
the original `create_rcrewai_tables` template is **not** edited):

```ruby
add_column :rcrewai_agents, :reasoning, :boolean, default: false, null: false
add_column :rcrewai_agents, :max_reasoning_attempts, :integer, default: 3
add_column :rcrewai_agents, :respect_context_window, :boolean, default: false, null: false
```

`max_rpm` (integer) and `llm_config` (text/JSON, already `serialize`d) exist —
no schema change.

### Model wiring (`app/models/rcrewai/rails/agent.rb`)

```ruby
def to_rcrew_agent
  RCrewAI::Agent.new(
    name: name, role: role, goal: goal, backstory: backstory,
    verbose: verbose, allow_delegation: allow_delegation,
    tools: instantiated_tools, max_iterations: max_iterations,
    **agent_options
  )
end

private

def agent_options
  opts = {}
  opts[:max_rpm] = max_rpm if max_rpm.present?
  opts[:reasoning] = reasoning if reasoning
  opts[:max_reasoning_attempts] = max_reasoning_attempts if reasoning && max_reasoning_attempts
  opts[:respect_context_window] = respect_context_window if respect_context_window
  opts[:llm] = llm_config.symbolize_keys if llm_config.present?
  opts
end
```

**Backward-compat guarantee:** `agent_options` returns `{}` for an all-default
record, so `to_rcrew_agent` is byte-identical to today's construction.

No new validations are strictly required. Optional hardening (deferred unless
requested): validate `max_rpm` numericality `>= 0`, `max_reasoning_attempts >= 1`.

### Testing (TDD)

Extend `spec/agent_builder_spec.rb` / add `spec/models/agent_spec.rb` cases,
stubbing `RCrewAI::Agent.new` to assert on kwargs (real reasoning / throttling
needs live LLM calls, out of scope for unit tests):

1. **Regression guard** — bare agent passes none of the new keys.
2. `max_rpm` present → forwarded.
3. `reasoning: true` → `reasoning` + `max_reasoning_attempts` forwarded.
4. `reasoning: false` → neither forwarded (even if attempts set).
5. `respect_context_window: true` → forwarded.
6. `llm_config` present → forwarded as symbolized `llm:` hash.

## Out of scope

- Web UI / dashboard controls for the new fields (follow-up).
- Groups B, C, D.
- Generator/scaffold template updates for the new columns (nice-to-have; can be
  folded in if trivial during implementation).

## Risks

- **Schema drift:** the repo already references a `Tool` model + `rcrewai_tools`
  table with no migration. Not caused by this work, but noted — the new
  migration should follow whatever the install/migration convention turns out to
  be. Resolve during implementation.
