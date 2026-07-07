# Group E (Part 1) — Consensual process + constraint bump (rcrewai 0.7.0)

**Date:** 2026-07-07
**Status:** Draft — awaiting user review
**Scope:** The quick, mechanical half of adapting the Rails engine to rcrewai
0.6/0.7. Surfaces the new `:consensual` crew process (0.7.0) and bumps the core
dependency. Memory forwarding (0.6.0) is a separate, considered spec (Part 2).

## Context

rcrewai advanced 0.5.0 → 0.7.0 while the engine targeted 0.5. Key deltas:
- **0.7.0** turned `:consensual` from a stub into a real process
  (`Crew.new(process: :consensual, consensus_agents: N)`; core validates
  `%i[sequential hierarchical consensual]`, `consensus_agents` default 3).
- The engine currently hardcodes only `sequential`/`hierarchical` in the Crew
  model validation and the UI dropdowns, so it cannot produce a consensual crew.
- Nothing is broken (the `~> 0.5` constraint already permits 0.7.0, and the
  engine can't emit `:consensual` today so the 0.7 behavior change doesn't affect
  it) — this is a feature gap, not a regression.

## Goal

Let Rails crews use the `:consensual` process, forward `consensus_agents`, and
require the rcrewai version that provides it.

## Design

### Schema

Add one column to `rcrewai_crews` (migration `008` + generator + test schema):

```ruby
add_column :rcrewai_crews, :consensus_agents, :integer
```

Nullable — nil means "let the core default (3) apply". Only forwarded when set.

### Model (`app/models/rcrewai/rails/crew.rb`)

- Widen the validation:
  `validates :process_type, inclusion: { in: %w[sequential hierarchical consensual] }`
- Forward `consensus_agents` in `to_rcrew` via `crew_planning_options` (the
  existing "emit only when set" helper):
  `opts[:consensus_agents] = consensus_agents if consensus_agents.present?`

Backward-compat: existing sequential/hierarchical crews are unaffected; a crew
with nil `consensus_agents` forwards nothing.

### UI

Add `['Consensual', 'consensual']` to the `process_type` select in
`app/views/rcrewai/rails/crews/new.html.erb` and `edit.html.erb`, and permit
`consensus_agents` in both crews controllers' strong params (web + api/v1).

### Gemspec

Bump `spec.add_dependency "rcrewai", "~> 0.5"` → `"~> 0.7"`.

### Testing (TDD)

1. Model: `process_type: "consensual"` is now valid; an unknown type still
   rejected.
2. `to_rcrew` forwards `consensus_agents` when set; not when nil (regression
   guard on `crew_planning_options`).
3. Constraint bump: full suite green against the local 0.7.0 sibling.

## Out of scope

- **Memory config forwarding (0.6.0/0.6.1)** — Part 2, needs its own design (the
  memory options are mostly objects, not persistable scalars; plus the stale
  `memory`/`memory_enabled` columns need a decision).
- Consensual-specific UI beyond the dropdown + the agents field.

## Risks

- The engine has a stale, unused `memory` (JSON) column and `memory_enabled`
  boolean on `rcrewai_crews`. Not touched here; addressed in Part 2.
