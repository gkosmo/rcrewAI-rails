# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Observation engine: span-tree tracing of every crew execution with per-agent,
  per-LLM-call and per-tool-call detail (timings, token counts, cost). Includes a
  trace waterfall at `/rcrewai/executions/:id/observation`, a cost/performance
  dashboard at `/rcrewai/observations/costs`, live monitoring over Turbo Streams,
  and a `rcrewai:observation:prune` rake task with retention configuration
  (`observation_retention_days`).

### Deprecated
- `Execution#log` and `ExecutionLog`, superseded by the observation engine. Both
  still work and now emit a deprecation warning; scheduled for removal one minor
  version after this release.

### Requires
- `rcrewai >= 0.7.1` for agent-level tracing. On earlier 0.7.x versions traces
  contain only crew-level spans.

## [0.6.1] - 2026-07-07

### Fixed
- Refresh the README for rcrewai 0.7: corrected the install-generator namespace
  (`rcrewai:rails:install`) and removed a broken crew-level `memory_enabled`
  example (that DSL method no longer exists — memory is agent-level). Added a
  "rcrewai 0.7 capabilities" section documenting the new agent/task/crew/
  knowledge/flow configuration. Docs only.

## [0.6.0] - 2026-07-07

Tracks rcrewai 0.7.0: adds the `:consensual` crew process and agent-level
cognitive memory configuration, and requires `rcrewai ~> 0.7`. Includes a
schema cleanup that removes unused columns (see Removed + the `009` migration).

### Added
- Support the rcrewai 0.7.0 `:consensual` crew process: `process_type:
  "consensual"` is now valid, a nullable `consensus_agents` column is forwarded to
  the core crew (defaulting to the core's 3 when unset), and the web UI + API
  permit it. Existing sequential/hierarchical crews are unaffected.
- Agent memory configuration: enable rcrewai 0.6+ cognitive memory per agent via
  the existing `memory_enabled` flag, with `memory_scope` /
  `memory_short_term_limit` columns forwarded to the core agent. The embedder and
  store come from `RcrewAI::Rails.config.default_memory_embedder` /
  `default_memory_store` (set in a host initializer). Memory is off by default, so
  existing agents are unaffected.

### Changed
- Require `rcrewai ~> 0.7` (was `~> 0.5`).

### Removed
- Dropped the unused `memory_enabled` and `memory` columns from `rcrewai_crews`.
  Core memory is agent-level; these crew columns were never wired to anything.
  **Migration note:** the `009` migration removes them (reversible).

## [0.5.1] - 2026-07-06

### Fixed
- Exclude internal `docs/superpowers/` design and plan documents from the packaged
  gem (they were swept in alongside the intended `docs/index.html`). No code
  changes; first published build carrying the 0.4/0.5 parity work.

## [0.5.0] - 2026-07-06

Adds the second CrewAI pillar — **Flows** — to the Rails engine as a persistence
layer, completing the rcrewai 0.4/0.5 feature-parity effort. Additive; existing
crews, agents, and tasks are unaffected.

### Added
- Flows persistence: `RcrewAI::Rails::ActiveRecordStateStore` backs rcrewai Flow
  state with a `rcrewai_flow_states` table so flows resume from the DB
  (`flow.restore(state_id)`), and `RcrewAI::Rails::FlowRun` records each kickoff
  (status, state id, inputs, result, timing) via `FlowRun.execute(FlowClass,
  inputs:)`. Flow subclasses are still defined in the host app; the engine adds
  the persistence layer (#13).

## [0.4.0] - 2026-07-06

Feature-parity release: brings the rcrewai 0.4/0.5 agent, task, and crew
capabilities to the Rails engine. Requires `rcrewai ~> 0.5`. All additive —
existing agents, tasks, and crews build unchanged.

### Added
- Forward rcrewai 0.5.0 agent options through `RcrewAI::Rails::Agent#to_rcrew_agent`:
  `reasoning`, `max_reasoning_attempts`, `respect_context_window`, and per-agent
  `llm` (from the `llm_config` column). Also fixes a latent gap where the existing
  `max_rpm` and `llm_config` columns were never passed to the core agent. New
  columns are added via a host migration, the install generator, and the test
  schema; all options are emitted only when set, so existing agents are
  unaffected (#6).
- Forward rcrewai 0.4/0.5 task output-processing options through
  `RcrewAI::Rails::Task#to_rcrew_task`: `output_schema` (structured output),
  `guardrail` (resolved from `guardrail_class` + `guardrail_method_name`),
  `guardrail_max_retries`, `output_file`, `create_directory`, `markdown`, and
  multimodal `attachments`. Options are emitted only when meaningfully set, so
  existing tasks construct unchanged (#7).
- Forward rcrewai 0.5.0 crew options through `RcrewAI::Rails::Crew#to_rcrew`:
  `planning` / `planning_llm`, and `before_kickoff` / `after_kickoff` lifecycle
  hooks (resolved from `*_class` + `*_method` columns). Options are emitted and
  hooks registered only when configured, so existing crews build unchanged (#9).
- Batch crew execution (`kickoff_for_each` parity): `Crew#execute_batch_sync` /
  `#execute_batch_async` run the crew once per input set, creating one `Execution`
  per input grouped by a shared `batch_id` (new nullable column). `#batch_executions`
  returns a batch's runs in order. Existing single-run executions are unaffected (#10).
- Knowledge (RAG) sources: a polymorphic `RcrewAI::Rails::KnowledgeSource`
  (owned by an Agent or a Crew) persists `{source_type, value}` for string, file,
  PDF, CSV, and URL sources. `Agent#to_rcrew_agent` / `Crew#to_rcrew` forward
  active sources as `knowledge_sources:`; the core embeds them lazily at
  execution. Emitted only when sources exist, so existing agents/crews are
  unaffected (#11).

### Changed
- Require `rcrewai ~> 0.5` (was `~> 0.3`) (#6).

## [0.3.1] - 2026-06-16

### Added
- GitHub Pages landing + documentation site, served from `/docs` at
  https://gkosmo.github.io/rcrewai-rails/ (#3).

### Fixed
- Zeitwerk eager-load failure caused by `lib/` being on the autoload paths (#2).

### Changed
- Point the gemspec `documentation_uri` at the new GitHub Pages site (#3).

## [0.3.0] - 2026-05-12

### Added
- Adapt the engine to rcrewai 0.3.
- Test suite (RSpec) covering models, jobs, builders, and tools.
- GitHub Actions CI workflow.

### Changed
- Rename generators from `rcrew_a_i` to `rcrewai` namespacing.

[Unreleased]: https://github.com/gkosmo/rcrewai-rails/compare/v0.6.1...HEAD
[0.6.1]: https://github.com/gkosmo/rcrewai-rails/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/gkosmo/rcrewai-rails/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/gkosmo/rcrewai-rails/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/gkosmo/rcrewai-rails/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/gkosmo/rcrewai-rails/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/gkosmo/rcrewai-rails/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/gkosmo/rcrewai-rails/releases/tag/v0.3.0
