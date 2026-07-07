# Group E (Part 2) — Agent memory config forwarding (rcrewai 0.6/0.7)

**Date:** 2026-07-07
**Status:** Draft — awaiting user review
**Scope:** The considered half of adapting the Rails engine to rcrewai 0.6/0.7.
Surfaces the cognitive memory system (0.6.0/0.6.1) at the agent level, and cleans
up the stale misplaced memory columns. Part 1 (consensual process + `~> 0.7`
constraint) shipped in #16.

## Context

rcrewai 0.6.0 replaced its placeholder memory with a real cognitive memory system:
semantic recall, four memory types, optional SQLite persistence. It's configured
at the **agent** level: `Agent.new(memory: {...})`. The Rails engine currently
forwards no memory config, and carries stale unused columns.

Core options (`Agent#build_memory`): `{ scope:, short_term_limit:, embedder:,
store:, entity_extractor: }`. Split by persistability:
- **Scalars** (`scope` string, `short_term_limit` int) → DB columns.
- **Objects** (`embedder`, `store`, `entity_extractor`) → cannot live in a DB
  column; they need real config (API keys, a SQLite path).

Decisions taken (with the user):
1. **Scalars via columns; embedder/store via a config initializer.** Host apps set
   `RcrewAI::Rails.config.default_memory_embedder` / `default_memory_store` in code,
   where credentials/paths belong. `entity_extractor` is deferred (advanced).
2. **Use the Agent's existing `memory_enabled` column as the on/off gate** (it
   exists but has never been wired to anything), and **drop the misplaced Crew
   `memory_enabled` + `memory` columns** — core memory is agent-level, and both
   Crew columns have always been unused. Resolves the schema drift.

## Design

### Model (`app/models/rcrewai/rails/agent.rb`)

Forward a `memory:` options hash only when `memory_enabled`:

```ruby
def agent_options
  opts = {}
  # ... existing keys (max_rpm, reasoning, llm, knowledge_sources, ...) ...
  opts[:memory] = memory_options if memory_enabled
  opts
end

# Agent memory config (rcrewai 0.6+). Scalars come from columns; embedder/store
# come from the engine configuration (set in a host initializer). Returns a hash
# that may be empty — an empty hash still enables memory with core defaults.
def memory_options
  m = {}
  m[:scope] = memory_scope if memory_scope.present?
  m[:short_term_limit] = memory_short_term_limit if memory_short_term_limit.present?
  embedder = RcrewAI::Rails.config.default_memory_embedder
  store = RcrewAI::Rails.config.default_memory_store
  m[:embedder] = embedder if embedder
  m[:store] = store if store
  m
end
```

Backward-compat: `memory_enabled` defaults `false`, so existing agents forward no
`memory:` key and construct identically. When enabled with nothing else set, the
core applies its own defaults (agent-name scope, in-memory store, lexical recall)
— a valid minimal memory setup.

Note the core distinguishes "no `memory:` key" (default Memory) from
`memory: {}` — both yield a working default Memory, so forwarding `{}` when
enabled-but-unconfigured is correct and harmless.

### Schema (migration `009_add_memory_config_to_agents_and_clean_crews.rb`)

```ruby
add_column :rcrewai_agents, :memory_scope, :string
add_column :rcrewai_agents, :memory_short_term_limit, :integer
# rcrewai_agents.memory_enabled already exists — reused as the on/off gate.

# Cleanup: core memory is agent-level; these Crew columns were never used.
remove_column :rcrewai_crews, :memory_enabled, :boolean, default: false
remove_column :rcrewai_crews, :memory, :text
```

Mirrored into `spec/internal/db/schema.rb` and the install-generator template:
add the two agent columns; remove the two crew columns. Migration `remove_column`
calls pass the type/options so the migration is reversible.

### Configuration (`lib/rcrewai/rails/configuration.rb`)

Add two accessors (default nil), alongside the existing `default_llm_*`:

```ruby
attr_accessor ..., :default_memory_embedder, :default_memory_store
# @default_memory_embedder = nil
# @default_memory_store = nil
```

Host usage (documented, not required):

```ruby
RcrewAI::Rails.configure do |c|
  c.default_memory_embedder = RCrewAI::Knowledge::Embedder.new
  c.default_memory_store = RCrewAI::Memory::SqliteStore.new("db/rcrewai_memory.sqlite3")
end
```

### Crew model cleanup

Remove the `serialize :memory, coder: JSON` line from `app/models/rcrewai/rails/crew.rb`
(the column it serialized is being dropped). Confirm nothing else references the
crew `memory`/`memory_enabled` columns (controllers/views/builders) and remove any
such references (e.g. strong-params, form fields) as part of the change.

### Testing (TDD)

Spy on `RCrewAI::Agent.new` and assert on the `memory:` kwarg:

1. All-default agent (`memory_enabled` false) → no `:memory` key (regression guard).
2. `memory_enabled: true`, no scalars, no config → `memory: {}` (enabled, core
   defaults).
3. `memory_enabled: true` with `memory_scope` / `memory_short_term_limit` → those
   forwarded inside the memory hash.
4. `default_memory_embedder` / `default_memory_store` set on the config → forwarded
   inside the memory hash (stub the config in the example).
5. Config accessors default to nil.
6. Crew: dropping the columns doesn't break `to_rcrew` (a crew builds fine); the
   `serialize :memory` line is gone.

## Out of scope

- `entity_extractor` config — advanced; deferred.
- Crew-level memory — the core has none (agent-level only).
- Web UI controls for the memory fields — follow-up.
- The core gem's "cognitive" internals (importance scoring, consolidation) — those
  live in rcrewai, not this engine.

## Risks

- **Dropping `rcrewai_crews.memory` / `memory_enabled` is destructive** for any host
  that (against the engine's intent) wrote data there. Both have always been unused
  by the engine, and core memory is agent-level, so real data loss is very
  unlikely; the migration is reversible (`remove_column` with type given). Called
  out for the changelog.
- **Embedder/store are process-level singletons** via config — every memory-enabled
  agent shares them. That matches the core's expectation (a store is a shared
  backend; scope keys isolate agents within it), so it's correct, not a limitation.
