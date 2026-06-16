# GitHub Pages Landing Site for `rcrewai-rails`

**Date:** 2026-06-16
**Status:** Approved

## Goal

Publish a polished landing + documentation page for the `rcrewai-rails` gem,
served via GitHub Pages from the `/docs` folder on `master`. The page gives a
strong first impression and doubles as practical usage documentation.

## Constraints

- **Single self-contained file:** `docs/index.html`. No build step, no
  framework, no JavaScript dependencies, no external network requests.
- **Styling:** Inline `<style>` in the document. Clean light / Rails-y look —
  off-white background, crimson Rails-style accent, system sans-serif for prose,
  monospace for code. Code blocks styled with CSS only (dark block, monospace,
  soft border) — no syntax-token coloring.
- **Content accuracy:** All copy drawn from the existing `README.md` and
  `rcrewai-rails.gemspec` so the page stays correct.

## Hosting

GitHub Pages configured to serve from the `master` branch `/docs` folder. The
resulting URL is `https://gkosmo.github.io/rcrewai-rails/`. (Enabling Pages in
the repo settings is a manual GitHub step the user performs; this spec only
produces the file.)

## Page Structure

Single scrolling page with a sticky top navigation:

1. **Sticky header** — gem name, tagline, anchor links (Features · Install ·
   Usage · Tools · API), GitHub link.
2. **Hero** — name, one-line pitch, `gem 'rcrewai-rails'` snippet, CTA buttons
   (GitHub repo, RubyGems).
3. **Features grid** — 6 cards: ActiveRecord persistence, ActiveJob integration,
   Rails generators, Web dashboard, Multi-LLM support, Rails-specific tools.
4. **Installation** — Gemfile, `bundle install`, install generator, `db:migrate`,
   manual route mounting.
5. **Configuration** — the initializer example from the README.
6. **Usage** — generator command, programmatic crew example, async/sync execution.
7. **Rails Tools** — tool ecosystem (ActiveRecord, ActionMailer, Cache,
   ActiveStorage, Logger) with the `DataAnalystAgent` example.
8. **Web UI & Models** — what `/rcrewai` provides + the ActiveRecord model list.
9. **API endpoints** — the JSON API table.
10. **Footer** — MIT license, links.

## Additional Change

Update `rcrewai-rails.gemspec`:
`spec.metadata["documentation_uri"]` from
`https://gkosmo.github.io/rcrewAI/` to
`https://gkosmo.github.io/rcrewai-rails/`.

## Out of Scope

- Multi-page docs / Jekyll.
- JavaScript-driven syntax highlighting.
- Automated Pages deployment workflow (GitHub builds static `/docs` directly).
