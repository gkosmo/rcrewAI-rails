# Group D (Knowledge/RAG) — Rails knowledge sources (rcrewai 0.4/0.5)

**Date:** 2026-07-06
**Status:** Draft — awaiting user review
**Scope:** First of the two Group D pillars. Surfaces rcrewai's Knowledge (RAG)
sources through the Rails engine. The Flows pillar is a separate spec.

## Context

rcrewai 0.4 added Knowledge (RAG): sources (`StringSource`, `FileSource`,
`PdfSource`, `CsvSource`, `UrlSource`) are chunked, embedded, and stored in an
in-memory cosine-similarity vector store, then attached to an Agent
(role-specific) or a Crew (shared) via `knowledge_sources:` / `knowledge:`.

This spec persists knowledge **source config** in ActiveRecord and forwards it to
the core at build time. It does NOT persist vectors — the core builds/embeds its
store lazily at execution.

Decisions taken (with the user):

- **Polymorphic owner.** One `rcrewai_knowledge_sources` table with a polymorphic
  `owner` (an Agent or a Crew). Both get `has_many :knowledge_sources, as: :owner`.
  Matches how the core attaches sources to either an agent or a crew.
- **Lazy build at execution.** Rails stores source config only; the core wraps the
  sources in a `Knowledge::Base` and lazily `build!`s (embeds) at execution — which
  runs inside the background job for async crew runs. Embedding is an API call, so
  it belongs in the job, not a web request. No vector persistence in Rails.

## Grounding: the 0.4/0.5 core API

```ruby
# Source constructors (each maps to a persisted {type, value}):
RCrewAI::Knowledge::StringSource.new(text)
RCrewAI::Knowledge::FileSource.new(path)
RCrewAI::Knowledge::PdfSource.new(path)
RCrewAI::Knowledge::CsvSource.new(path)
RCrewAI::Knowledge::UrlSource.new(url)   # optional fetcher: kwarg — not exposed here

# Attach via the knowledge_sources: option on either:
RCrewAI::Agent.new(..., knowledge_sources: [source, ...])
RCrewAI::Crew.new(name, ..., knowledge_sources: [source, ...])
# The core wraps them in Knowledge::Base and calls build! lazily (embeds) at run time.
```

`UrlSource` also accepts a `fetcher:` (a callable) — not exposed through the DB in
this pass (default HTTP fetch only); noted as out of scope.

## Design

### Schema (new migration `006_create_rcrewai_knowledge_sources.rb`)

```ruby
create_table :rcrewai_knowledge_sources do |t|
  t.references :owner, polymorphic: true, null: false   # Agent or Crew
  t.string  :source_type, null: false                   # string|file|pdf|csv|url
  t.text    :value, null: false                         # inline text, file path, or url
  t.boolean :active, default: true
  t.timestamps
end
# t.references ... polymorphic: true already creates the [owner_type, owner_id] index.
```

Mirrored into `spec/internal/db/schema.rb` and the install-generator template
(three-way consistency, as in Groups A–C2). Note: a `t.references :owner,
polymorphic: true` already emits the composite index, so no separate add_index is
needed — but the test schema (which uses explicit `create_table`) must include
`t.references :owner, polymorphic: true` to match.

### Model (`app/models/rcrewai/rails/knowledge_source.rb`, new)

```ruby
module RcrewAI
  module Rails
    class KnowledgeSource < ApplicationRecord
      self.table_name = "rcrewai_knowledge_sources"

      TYPE_MAP = {
        "string" => RCrewAI::Knowledge::StringSource,
        "file"   => RCrewAI::Knowledge::FileSource,
        "pdf"    => RCrewAI::Knowledge::PdfSource,
        "csv"    => RCrewAI::Knowledge::CsvSource,
        "url"    => RCrewAI::Knowledge::UrlSource,
      }.freeze

      belongs_to :owner, polymorphic: true

      validates :source_type, inclusion: { in: TYPE_MAP.keys }
      validates :value, presence: true

      scope :active, -> { where(active: true) }

      # Maps this row to the matching core Source object.
      def to_rcrew_source
        TYPE_MAP.fetch(source_type).new(value)
      end
    end
  end
end
```

Add to both `Agent` and `Crew` models:

```ruby
has_many :knowledge_sources, as: :owner, class_name: "RcrewAI::Rails::KnowledgeSource", dependent: :destroy
```

### Wiring (emit only when sources exist — established discipline)

`Agent#to_rcrew_agent` — extend the existing `agent_options`:

```ruby
opts[:knowledge_sources] = rcrew_knowledge_sources if rcrew_knowledge_sources.any?
```

`Crew#to_rcrew` — extend the existing `crew_planning_options` (or add alongside):

```ruby
opts[:knowledge_sources] = rcrew_knowledge_sources if rcrew_knowledge_sources.any?
```

Shared private helper on each model:

```ruby
def rcrew_knowledge_sources
  knowledge_sources.active.map(&:to_rcrew_source)
end
```

Backward-compat: a crew/agent with no sources emits nothing and builds exactly as
before. The core lazily embeds at execution.

### Testing (TDD, mirrors prior groups)

The embedder/vector store is core-side and requires an embedding API; tests assert
the SOURCE OBJECTS are forwarded, not that embedding runs.

1. `KnowledgeSource#to_rcrew_source` maps each of the 5 `source_type`s to the
   correct core `Source` class, constructed with `value`.
2. `source_type` inclusion validation rejects an unknown type; `value` presence
   validation.
3. Polymorphic association: an Agent and a Crew can each own knowledge sources
   (`agent.knowledge_sources` / `crew.knowledge_sources`).
4. `Agent#to_rcrew_agent` forwards `knowledge_sources:` (array of core Source
   objects) only when active sources exist; forwards nothing otherwise (regression
   guard).
5. `Crew#to_rcrew` forwards `knowledge_sources:` likewise.
6. Inactive sources (`active: false`) are excluded.

Assert forwarding by spying on `RCrewAI::Agent.new` / `RCrewAI::Crew.new` and
inspecting the `knowledge_sources:` kwarg (checking the element classes), as in
Groups A–C.

## Out of scope (explicit)

- **Vector persistence** — the core store is in-memory and built per run.
- **Custom embedder config** (model/api_key/chunk_size/overlap) — uses core
  defaults; can be a follow-up.
- **UrlSource `fetcher:`** — default HTTP fetch only.
- **`knowledge:` (pre-built Base) passthrough** — only `knowledge_sources:` is
  exposed; a pre-built Base can't be persisted in a row.
- **Web UI** for managing sources.
- **The Flows pillar** — separate Group D spec.

## Risks

- **File/PDF/CSV sources read from the worker filesystem** at execution
  (`FileSource.new(path).read`). Same filesystem caveat as `output_file` /
  `attachments` in Group B. The `value` is a path resolved on the worker host.
- **UrlSource fetches at execution** (HTTP GET on the worker). Expected for RAG.
- **Embedding happens at execution and costs an API call** — deliberately placed
  in the (background) job path, not a web request. Documented.
