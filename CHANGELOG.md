# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
