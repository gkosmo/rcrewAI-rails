# Group D (Knowledge/RAG) — Rails Knowledge Sources Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist knowledge sources in the Rails engine (a polymorphic `rcrewai_knowledge_sources` table) and forward them as `knowledge_sources:` into `RCrewAI::Agent`/`RCrewAI::Crew` at build time, so RAG works through ActiveRecord.

**Architecture:** A new `RcrewAI::Rails::KnowledgeSource` model with a polymorphic `owner` (Agent or Crew), a `source_type` (string/file/pdf/csv/url) → core `Source`-class map, and a `to_rcrew_source` mapper. Agent#to_rcrew_agent and Crew#to_rcrew forward `knowledge_sources:` only when active sources exist (established "emit only when set" discipline). Rails persists source config only; the core lazily embeds at execution. New column set added across host migration + install generator + test schema.

**Tech Stack:** Ruby, Rails engine, RSpec + Combustion (schema from `spec/internal/db/schema.rb`), rcrewai 0.5.0.

---

## File Structure

- **Modify** `spec/internal/db/schema.rb` — add the `rcrewai_knowledge_sources` table.
- **Create** `spec/models/knowledge_source_spec.rb` — model + mapping specs.
- **Modify** `spec/models/agent_spec.rb` — agent knowledge forwarding specs.
- **Modify** `spec/models/crew_spec.rb` — crew knowledge forwarding specs.
- **Create** `app/models/rcrewai/rails/knowledge_source.rb` — the model.
- **Modify** `app/models/rcrewai/rails/agent.rb` — association + `rcrew_knowledge_sources` + forward in `agent_options`.
- **Modify** `app/models/rcrewai/rails/crew.rb` — association + `rcrew_knowledge_sources` + forward in `crew_planning_options`.
- **Create** `db/migrate/006_create_rcrewai_knowledge_sources.rb` — host migration.
- **Modify** `lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb` — generator table.

---

### Task 1: Create the table (test schema) + the KnowledgeSource model with failing specs

**Files:**
- Modify: `spec/internal/db/schema.rb`
- Create: `spec/models/knowledge_source_spec.rb`
- Create: `app/models/rcrewai/rails/knowledge_source.rb`

- [ ] **Step 1: Add the table to the Combustion test schema**

In `spec/internal/db/schema.rb`, add this new `create_table` block at the end of the schema definition (after the last existing `add_index` line, before the block-closing `end` of the `ActiveRecord::Schema.define`). Match the file's 2-space indentation:

```ruby
  create_table :rcrewai_knowledge_sources, force: true do |t|
    t.references :owner, polymorphic: true, null: false
    t.string :source_type, null: false
    t.text :value, null: false
    t.boolean :active, default: true
    t.timestamps
  end
```

(`t.references :owner, polymorphic: true` auto-creates the `[owner_type, owner_id]` index.)

- [ ] **Step 2: Write the failing model spec**

Create `spec/models/knowledge_source_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe RcrewAI::Rails::KnowledgeSource, type: :model do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "C", process_type: "sequential") }
  let(:agent) { crew.agents.create!(name: "a", role: "Worker") }

  describe "#to_rcrew_source" do
    {
      "string" => RCrewAI::Knowledge::StringSource,
      "file"   => RCrewAI::Knowledge::FileSource,
      "pdf"    => RCrewAI::Knowledge::PdfSource,
      "csv"    => RCrewAI::Knowledge::CsvSource,
      "url"    => RCrewAI::Knowledge::UrlSource,
    }.each do |type, klass|
      it "maps #{type} to #{klass}" do
        source = crew.knowledge_sources.create!(source_type: type, value: "v")
        expect(source.to_rcrew_source).to be_a(klass)
      end
    end
  end

  describe "validations" do
    it "rejects an unknown source_type" do
      source = crew.knowledge_sources.build(source_type: "bogus", value: "v")
      expect(source).not_to be_valid
      expect(source.errors[:source_type]).to be_present
    end

    it "requires a value" do
      source = crew.knowledge_sources.build(source_type: "string", value: nil)
      expect(source).not_to be_valid
      expect(source.errors[:value]).to be_present
    end
  end

  describe "polymorphic ownership" do
    it "can belong to a crew" do
      source = crew.knowledge_sources.create!(source_type: "string", value: "hello")
      expect(source.owner).to eq(crew)
      expect(crew.knowledge_sources).to include(source)
    end

    it "can belong to an agent" do
      source = agent.knowledge_sources.create!(source_type: "string", value: "hello")
      expect(source.owner).to eq(agent)
      expect(agent.knowledge_sources).to include(source)
    end
  end

  describe "active scope" do
    it "returns only active sources" do
      keep = crew.knowledge_sources.create!(source_type: "string", value: "keep", active: true)
      crew.knowledge_sources.create!(source_type: "string", value: "drop", active: false)
      expect(crew.knowledge_sources.active).to eq([keep])
    end
  end
end
```

- [ ] **Step 3: Run the spec — confirm it fails on the missing model/association, not schema**

Run: `bundle exec rspec spec/models/knowledge_source_spec.rb`
Expected: FAIL — `NameError: uninitialized constant RcrewAI::Rails::KnowledgeSource` (model not created yet), or an association error on `crew.knowledge_sources`. No SQLite "no such table" error (the table now exists in the schema).

If you see "no such table: rcrewai_knowledge_sources", the Step 1 schema edit is wrong — fix it.

- [ ] **Step 4: Create the model**

Create `app/models/rcrewai/rails/knowledge_source.rb`:

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

- [ ] **Step 5: Add the associations to Agent and Crew**

In `app/models/rcrewai/rails/agent.rb`, add after the existing `has_many :tools, ...` line (around line 8):

```ruby
      has_many :knowledge_sources, as: :owner, class_name: "RcrewAI::Rails::KnowledgeSource", dependent: :destroy
```

In `app/models/rcrewai/rails/crew.rb`, add after the existing `has_many :executions, ...` line (around line 8):

```ruby
      has_many :knowledge_sources, as: :owner, class_name: "RcrewAI::Rails::KnowledgeSource", dependent: :destroy
```

- [ ] **Step 6: Run the model spec — expect green**

Run: `bundle exec rspec spec/models/knowledge_source_spec.rb`
Expected: PASS — all examples green.

- [ ] **Step 7: Run the full suite**

Run: `bundle exec rspec`
Expected: PASS — 82 examples, 0 failures (72 prior + 10 new).

- [ ] **Step 8: Commit**

```bash
git add spec/internal/db/schema.rb spec/models/knowledge_source_spec.rb app/models/rcrewai/rails/knowledge_source.rb app/models/rcrewai/rails/agent.rb app/models/rcrewai/rails/crew.rb
git commit -m "Add KnowledgeSource model + polymorphic ownership"
```

---

### Task 2: Forward knowledge_sources from Agent#to_rcrew_agent

**Files:**
- Modify: `spec/models/agent_spec.rb`
- Modify: `app/models/rcrewai/rails/agent.rb`

- [ ] **Step 1: Write the failing agent forwarding specs**

In `spec/models/agent_spec.rb`, add this NEW `describe` block inside the top-level `RSpec.describe RcrewAI::Rails::Agent` block (after existing examples, before the final top-level `end`):

```ruby
  describe "knowledge source forwarding" do
    let(:crew) { RcrewAI::Rails::Crew.create!(name: "C", process_type: "sequential") }

    def capture_agent_kwargs
      captured = nil
      allow(RCrewAI::Agent).to receive(:new).and_wrap_original do |orig, **kwargs|
        captured = kwargs
        orig.call(**kwargs)
      end
      yield
      captured
    end

    it "forwards active knowledge sources as core Source objects" do
      agent = crew.agents.create!(name: "a", role: "R", goal: "G")
      agent.knowledge_sources.create!(source_type: "string", value: "hello")

      captured = capture_agent_kwargs { agent.to_rcrew_agent }

      expect(captured[:knowledge_sources]).to be_an(Array)
      expect(captured[:knowledge_sources].first).to be_a(RCrewAI::Knowledge::StringSource)
    end

    it "does not forward knowledge_sources when the agent has none" do
      agent = crew.agents.create!(name: "a", role: "R", goal: "G")

      captured = capture_agent_kwargs { agent.to_rcrew_agent }

      expect(captured).not_to have_key(:knowledge_sources)
    end

    it "excludes inactive sources" do
      agent = crew.agents.create!(name: "a", role: "R", goal: "G")
      agent.knowledge_sources.create!(source_type: "string", value: "keep", active: true)
      agent.knowledge_sources.create!(source_type: "string", value: "drop", active: false)

      captured = capture_agent_kwargs { agent.to_rcrew_agent }

      expect(captured[:knowledge_sources].length).to eq(1)
    end
  end
```

- [ ] **Step 2: Run the agent spec — confirm behavioral failure**

Run: `bundle exec rspec spec/models/agent_spec.rb`
Expected: the "forwards active knowledge sources" and "excludes inactive" examples FAIL (`captured[:knowledge_sources]` is nil — not forwarded yet). The "does not forward when none" example PASSES.

- [ ] **Step 3: Add the forwarding to agent_options + a helper**

In `app/models/rcrewai/rails/agent.rb`, in the `agent_options` method, add this line immediately before the final `opts` return:

```ruby
        opts[:knowledge_sources] = rcrew_knowledge_sources if rcrew_knowledge_sources.any?
```

Then add this method right after `agent_options` (keep it public — it's a small mapper, consistent with the file's public helpers):

```ruby
      def rcrew_knowledge_sources
        knowledge_sources.active.map(&:to_rcrew_source)
      end
```

- [ ] **Step 4: Run the agent spec — expect green**

Run: `bundle exec rspec spec/models/agent_spec.rb`
Expected: PASS — all examples green.

- [ ] **Step 5: Run the full suite**

Run: `bundle exec rspec`
Expected: PASS — 85 examples, 0 failures (82 after Task 1 + 3 new).

- [ ] **Step 6: Commit**

```bash
git add spec/models/agent_spec.rb app/models/rcrewai/rails/agent.rb
git commit -m "Forward agent knowledge sources through to_rcrew_agent"
```

---

### Task 3: Forward knowledge_sources from Crew#to_rcrew

**Files:**
- Modify: `spec/models/crew_spec.rb`
- Modify: `app/models/rcrewai/rails/crew.rb`

- [ ] **Step 1: Write the failing crew forwarding specs**

In `spec/models/crew_spec.rb`, add this NEW `describe` block as a SIBLING of the existing nested describes (after the last one, before the final top-level `end`):

```ruby
  describe "knowledge source forwarding" do
    def capture_crew_kwargs
      captured = nil
      allow(RCrewAI::Crew).to receive(:new).and_wrap_original do |orig, name, **kwargs|
        captured = kwargs
        orig.call(name, **kwargs)
      end
      yield
      captured
    end

    it "forwards active knowledge sources as core Source objects" do
      c = RcrewAI::Rails::Crew.create!(name: "K", process_type: "sequential")
      c.knowledge_sources.create!(source_type: "string", value: "hello")

      captured = capture_crew_kwargs { c.to_rcrew }

      expect(captured[:knowledge_sources]).to be_an(Array)
      expect(captured[:knowledge_sources].first).to be_a(RCrewAI::Knowledge::StringSource)
    end

    it "does not forward knowledge_sources when the crew has none" do
      c = RcrewAI::Rails::Crew.create!(name: "K", process_type: "sequential")

      captured = capture_crew_kwargs { c.to_rcrew }

      expect(captured).not_to have_key(:knowledge_sources)
    end

    it "excludes inactive sources" do
      c = RcrewAI::Rails::Crew.create!(name: "K", process_type: "sequential")
      c.knowledge_sources.create!(source_type: "string", value: "keep", active: true)
      c.knowledge_sources.create!(source_type: "string", value: "drop", active: false)

      captured = capture_crew_kwargs { c.to_rcrew }

      expect(captured[:knowledge_sources].length).to eq(1)
    end
  end
```

- [ ] **Step 2: Run the crew spec — confirm behavioral failure**

Run: `bundle exec rspec spec/models/crew_spec.rb`
Expected: the "forwards active" and "excludes inactive" examples FAIL (`captured[:knowledge_sources]` nil). The "does not forward when none" example PASSES.

- [ ] **Step 3: Add the forwarding to crew_planning_options + a helper**

In `app/models/rcrewai/rails/crew.rb`, in the `crew_planning_options` method, add this line immediately before the final `opts` return:

```ruby
        opts[:knowledge_sources] = rcrew_knowledge_sources if rcrew_knowledge_sources.any?
```

Then add this method right after `crew_planning_options` (keep it public, consistent with the file):

```ruby
      def rcrew_knowledge_sources
        knowledge_sources.active.map(&:to_rcrew_source)
      end
```

- [ ] **Step 4: Run the crew spec — expect green**

Run: `bundle exec rspec spec/models/crew_spec.rb`
Expected: PASS — all examples green.

- [ ] **Step 5: Run the full suite**

Run: `bundle exec rspec`
Expected: PASS — 88 examples, 0 failures (85 after Task 2 + 3 new).

- [ ] **Step 6: Commit**

```bash
git add spec/models/crew_spec.rb app/models/rcrewai/rails/crew.rb
git commit -m "Forward crew knowledge sources through to_rcrew"
```

---

### Task 4: Ship the host-app migration

**Files:**
- Create: `db/migrate/006_create_rcrewai_knowledge_sources.rb`

- [ ] **Step 1: Write the migration**

Create `db/migrate/006_create_rcrewai_knowledge_sources.rb`:

```ruby
class CreateRcrewaiKnowledgeSources < ActiveRecord::Migration[7.0]
  def change
    create_table :rcrewai_knowledge_sources do |t|
      t.references :owner, polymorphic: true, null: false
      t.string :source_type, null: false
      t.text :value, null: false
      t.boolean :active, default: true
      t.timestamps
    end
  end
end
```

- [ ] **Step 2: Verify syntax**

Run: `ruby -c db/migrate/006_create_rcrewai_knowledge_sources.rb`
Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add db/migrate/006_create_rcrewai_knowledge_sources.rb
git commit -m "Add host-app migration for rcrewai_knowledge_sources"
```

---

### Task 5: Update the install-generator template

**Files:**
- Modify: `lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb`

- [ ] **Step 1: Add the table to the generator template**

In `lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb`, add this new `create_table` block immediately before the final `end` of the migration's `change` method (after the last existing `add_index` line). Match the block's 4-space `create_table` indentation:

```ruby
    create_table :rcrewai_knowledge_sources do |t|
      t.references :owner, polymorphic: true, null: false
      t.string :source_type, null: false
      t.text :value, null: false
      t.boolean :active, default: true

      t.timestamps
    end
```

- [ ] **Step 2: Verify syntax**

Run: `ruby -c lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb`
Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb
git commit -m "Include rcrewai_knowledge_sources in install generator"
```

---

### Task 6: Full-suite verification + schema consistency + changelog

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Run the full suite**

Run: `bundle exec rspec`
Expected: `88 examples, 0 failures`.

- [ ] **Step 2: Confirm the table is consistent across the three definitions**

Run: `grep -n "rcrewai_knowledge_sources\|source_type\|polymorphic" spec/internal/db/schema.rb db/migrate/006_create_rcrewai_knowledge_sources.rb lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb`
Expected: the table + `source_type` + polymorphic `owner` appear in all three files with matching columns.

- [ ] **Step 3: Add the changelog entry**

In `CHANGELOG.md`, under the `## [Unreleased]` → `### Added` list, add this bullet after the last existing bullet:

```markdown
- Knowledge (RAG) sources: a polymorphic `RcrewAI::Rails::KnowledgeSource`
  (owned by an Agent or a Crew) persists `{source_type, value}` for string, file,
  PDF, CSV, and URL sources. `Agent#to_rcrew_agent` / `Crew#to_rcrew` forward
  active sources as `knowledge_sources:`; the core embeds them lazily at
  execution. Emitted only when sources exist, so existing agents/crews are
  unaffected (#11).
```

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md
git commit -m "Document Group D knowledge sources in the changelog"
```

---

## Notes / Out of scope

- **Vector persistence** — core store is in-memory, built per run.
- **Custom embedder config, UrlSource `fetcher:`, pre-built `knowledge:` Base** — deferred (see spec).
- **Web UI** for managing sources — follow-up.
- **The Flows pillar** — separate Group D spec.
