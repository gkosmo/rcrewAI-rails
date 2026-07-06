# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/gkosmo/rcrewai-rails/compare/v0.3.1...HEAD
[0.3.1]: https://github.com/gkosmo/rcrewai-rails/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/gkosmo/rcrewai-rails/releases/tag/v0.3.0
