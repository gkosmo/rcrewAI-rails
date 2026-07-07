# Group E (Part 2) — Agent Memory Config Forwarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Let Rails agents enable/configure rcrewai 0.6+ cognitive memory (scalars via columns, embedder/store via engine config), and remove the stale misplaced Crew memory columns.

**Architecture:** Add `default_memory_embedder`/`default_memory_store` to the engine Configuration. Add `memory_scope`/`memory_short_term_limit` columns to `rcrewai_agents` and gate a forwarded `memory:` hash on the existing `memory_enabled`. Drop the unused `rcrewai_crews.memory` + `memory_enabled` columns and all their UI/controller references. New columns + drops applied consistently across host migration (`009`), generator, and test schema.

**Tech Stack:** Ruby, Rails engine, RSpec + Combustion, rcrewai 0.7.0.

---

### Task 1: Configuration accessors

**Files:**
- Modify: `lib/rcrewai/rails/configuration.rb`
- Create: `spec/configuration_spec.rb`

- [ ] **Step 1: Write the failing spec**

Create `spec/configuration_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe RcrewAI::Rails::Configuration do
  it "defaults memory embedder and store to nil" do
    config = described_class.new
    expect(config.default_memory_embedder).to be_nil
    expect(config.default_memory_store).to be_nil
  end

  it "allows setting memory embedder and store" do
    config = described_class.new
    config.default_memory_embedder = :an_embedder
    config.default_memory_store = :a_store
    expect(config.default_memory_embedder).to eq(:an_embedder)
    expect(config.default_memory_store).to eq(:a_store)
  end
end
```

- [ ] **Step 2: Run — confirm failure**

Run: `bundle exec rspec spec/configuration_spec.rb`
Expected: FAIL — `NoMethodError: undefined method 'default_memory_embedder'`.

- [ ] **Step 3: Add the accessors**

In `lib/rcrewai/rails/configuration.rb`, add `:default_memory_embedder, :default_memory_store` to the `attr_accessor` list, and initialize both to nil in `initialize`. The result:

```ruby
module RcrewAI
  module Rails
    class Configuration
      attr_accessor :job_queue_name, :enable_web_ui, :persistence_backend,
                    :default_llm_provider, :default_llm_model, :max_retries,
                    :timeout, :enable_logging, :log_level, :async_execution,
                    :default_memory_embedder, :default_memory_store

      def initialize
        @job_queue_name = "default"
        @enable_web_ui = true
        @persistence_backend = :active_record
        @default_llm_provider = "openai"
        @default_llm_model = "gpt-4"
        @max_retries = 3
        @timeout = 300 # 5 minutes
        @enable_logging = true
        @log_level = :info
        @async_execution = true # Use ActiveJob for async by default
        @default_memory_embedder = nil
        @default_memory_store = nil
      end
    end
  end
end
```

- [ ] **Step 4: Run — expect green**

Run: `bundle exec rspec spec/configuration_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/rcrewai/rails/configuration.rb spec/configuration_spec.rb
git commit -m "Add default_memory_embedder/store to engine configuration"
```

---

### Task 2: Agent memory columns + forwarding

**Files:**
- Modify: `spec/internal/db/schema.rb`, `spec/models/agent_spec.rb`, `app/models/rcrewai/rails/agent.rb`

- [ ] **Step 1: Add the two agent columns to the test schema**

In `spec/internal/db/schema.rb`, inside the `create_table :rcrewai_agents` block, add immediately after the existing `t.boolean :memory_enabled, default: false` line:

```ruby
    t.string :memory_scope
    t.integer :memory_short_term_limit
```

- [ ] **Step 2: Write the failing specs**

In `spec/models/agent_spec.rb`, add this NEW describe block inside the top-level `RSpec.describe RcrewAI::Rails::Agent` block (sibling of existing describes, before the final top-level `end`):

```ruby
  describe "memory forwarding" do
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

    it "forwards no memory key when memory is disabled" do
      agent = crew.agents.create!(name: "a", role: "R", goal: "G", memory_enabled: false)
      captured = capture_agent_kwargs { agent.to_rcrew_agent }
      expect(captured).not_to have_key(:memory)
    end

    it "forwards an empty memory hash when enabled with no config" do
      agent = crew.agents.create!(name: "a", role: "R", goal: "G", memory_enabled: true)
      captured = capture_agent_kwargs { agent.to_rcrew_agent }
      expect(captured[:memory]).to eq({})
    end

    it "forwards memory scalars when set" do
      agent = crew.agents.create!(
        name: "a", role: "R", goal: "G",
        memory_enabled: true, memory_scope: "team", memory_short_term_limit: 7
      )
      captured = capture_agent_kwargs { agent.to_rcrew_agent }
      expect(captured[:memory]).to eq(scope: "team", short_term_limit: 7)
    end

    it "forwards embedder and store from engine config when enabled" do
      allow(RcrewAI::Rails.config).to receive(:default_memory_embedder).and_return(:emb)
      allow(RcrewAI::Rails.config).to receive(:default_memory_store).and_return(:sto)
      agent = crew.agents.create!(name: "a", role: "R", goal: "G", memory_enabled: true)

      captured = capture_agent_kwargs { agent.to_rcrew_agent }
      expect(captured[:memory][:embedder]).to eq(:emb)
      expect(captured[:memory][:store]).to eq(:sto)
    end
  end
```

- [ ] **Step 3: Run — confirm behavioral failures, not schema**

Run: `bundle exec rspec spec/models/agent_spec.rb`
Expected: the "empty memory hash", "scalars", and "embedder and store" examples FAIL (`captured[:memory]` nil — not forwarded). The "no memory key when disabled" example PASSES. No `UnknownAttributeError`. If you see one, the Step 1 schema edit is wrong.

- [ ] **Step 4: Add the forwarding to the Agent model**

In `app/models/rcrewai/rails/agent.rb`, in `agent_options`, add this line immediately before the final `opts` return:

```ruby
        opts[:memory] = memory_options if memory_enabled
```

Then add this method immediately after `agent_options` (public, matching the file's helper style):

```ruby
      # Agent memory config (rcrewai 0.6+). Scalars come from columns; embedder
      # and store come from the engine configuration (set in a host initializer).
      # May return {} — an empty hash still enables memory with core defaults.
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

- [ ] **Step 5: Run — expect green**

Run: `bundle exec rspec spec/models/agent_spec.rb`
Expected: PASS.

- [ ] **Step 6: Full suite**

Run: `bundle exec rspec`
Expected: `109 examples, 0 failures` (103 + 2 config + 4 agent = 109).

- [ ] **Step 7: Commit**

```bash
git add spec/internal/db/schema.rb spec/models/agent_spec.rb app/models/rcrewai/rails/agent.rb
git commit -m "Forward agent memory config through to_rcrew_agent"
```

---

### Task 3: Remove stale crew memory references (model, controllers, views)

**Important ordering:** this task removes all code references to the crew
`memory`/`memory_enabled` columns FIRST, so that Task 4 can safely drop those
columns from the schema without any commit going red. Do this task before Task 4.

**Files:**
- Modify: `app/models/rcrewai/rails/crew.rb`
- Modify: `app/controllers/rcrewai/rails/crews_controller.rb`, `.../api/v1/crews_controller.rb`
- Modify: `app/views/rcrewai/rails/crews/new.html.erb`, `.../edit.html.erb`, `.../show.html.erb`

- [ ] **Step 1: Remove the serialize line from the Crew model**

In `app/models/rcrewai/rails/crew.rb`, DELETE the line:

```ruby
      serialize :memory, coder: JSON
```

- [ ] **Step 2: Remove :memory_enabled from both controllers' strong params**

In `app/controllers/rcrewai/rails/crews_controller.rb` AND `app/controllers/rcrewai/rails/api/v1/crews_controller.rb`, the permit list currently reads:

```ruby
              :memory_enabled, :cache_enabled, :max_rpm, :manager_llm, :consensus_agents, :active
```

Change it to remove `:memory_enabled`:

```ruby
              :cache_enabled, :max_rpm, :manager_llm, :consensus_agents, :active
```

(Match each file's own indentation.)

- [ ] **Step 3: Remove the memory_enabled form fields from new.html.erb and edit.html.erb**

In `app/views/rcrewai/rails/crews/new.html.erb`, DELETE the two lines:

```erb
      <%= form.label :memory_enabled, class: "form-label" %>
      <%= form.check_box :memory_enabled, class: "form-checkbox" %>
```

If those two lines are wrapped in a containing element (e.g. a `<div class="form-group">...</div>`), delete the whole wrapping group for the memory field. Read the surrounding lines and remove the complete field block so no empty/broken markup remains.

Do the same in `app/views/rcrewai/rails/crews/edit.html.erb` (delete its `form.label :memory_enabled` + `form.check_box :memory_enabled` field block).

- [ ] **Step 4: Remove the memory display from show.html.erb**

In `app/views/rcrewai/rails/crews/show.html.erb`, DELETE the line (and its wrapping element if it has one):

```erb
      <strong>Memory:</strong> <%= @crew.memory_enabled ? "Enabled" : "Disabled" %>
```

- [ ] **Step 5: Confirm no stray crew memory references remain**

Run: `grep -rn "memory_enabled\|serialize :memory\|@crew.memory\|:memory\b" app/models/rcrewai/rails/crew.rb app/controllers/rcrewai/rails/crews_controller.rb app/controllers/rcrewai/rails/api/v1/crews_controller.rb app/views/rcrewai/rails/crews/`
Expected: NO matches (all crew memory references removed). Note: `agent`-side `memory_enabled` references are fine and out of this grep's scope.

- [ ] **Step 6: Full suite + syntax**

Run: `bundle exec rspec`
Expected: `109 examples, 0 failures`.
Run: `ruby -c app/models/rcrewai/rails/crew.rb app/controllers/rcrewai/rails/crews_controller.rb app/controllers/rcrewai/rails/api/v1/crews_controller.rb`
Expected: `Syntax OK`.

- [ ] **Step 7: Commit**

```bash
git add app/models/rcrewai/rails/crew.rb app/controllers/rcrewai/rails/crews_controller.rb app/controllers/rcrewai/rails/api/v1/crews_controller.rb app/views/rcrewai/rails/crews/new.html.erb app/views/rcrewai/rails/crews/edit.html.erb app/views/rcrewai/rails/crews/show.html.erb
git commit -m "Remove stale crew memory references from model, controllers, and views"
```

---

### Task 4: Migration + generator (add agent columns, drop crew columns)

**Ordering:** Task 3 already removed all code references to the crew memory
columns, so dropping the columns here keeps every commit green.

**Files:**
- Create: `db/migrate/009_add_memory_config_to_agents_and_clean_crews.rb`
- Modify: `lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb`
- Modify: `spec/internal/db/schema.rb`

- [ ] **Step 1: Write the migration**

Create `db/migrate/009_add_memory_config_to_agents_and_clean_crews.rb`:

```ruby
class AddMemoryConfigToAgentsAndCleanCrews < ActiveRecord::Migration[7.0]
  def change
    add_column :rcrewai_agents, :memory_scope, :string
    add_column :rcrewai_agents, :memory_short_term_limit, :integer

    # Core memory is agent-level; these crew columns were never used.
    remove_column :rcrewai_crews, :memory_enabled, :boolean, default: false
    remove_column :rcrewai_crews, :memory, :text
  end
end
```

Verify: `ruby -c db/migrate/009_add_memory_config_to_agents_and_clean_crews.rb` → `Syntax OK`.

- [ ] **Step 2: Update the generator template**

In `lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb`:

(a) In the `create_table :rcrewai_agents` block, add after `t.boolean :memory_enabled, default: false`:

```ruby
      t.string :memory_scope
      t.integer :memory_short_term_limit
```

(b) In the `create_table :rcrewai_crews` block, DELETE these two lines:

```ruby
      t.boolean :memory_enabled, default: false
      t.text :memory
```

Verify syntax with `ruby -c`.

- [ ] **Step 3: Drop the crew columns from the test schema**

In `spec/internal/db/schema.rb`, in the `create_table :rcrewai_crews` block, DELETE these two lines:

```ruby
    t.boolean :memory_enabled, default: false
    t.text :memory
```

(The agent memory_scope / memory_short_term_limit columns were already added to the test schema in Task 2 Step 1.)

- [ ] **Step 4: Full suite**

Run: `bundle exec rspec`
Expected: `109 examples, 0 failures`. Because Task 3 removed the crew-side references, dropping the columns here leaves the suite green.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/009_add_memory_config_to_agents_and_clean_crews.rb lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb spec/internal/db/schema.rb
git commit -m "Migration + generator: add agent memory columns, drop crew memory columns"
```

---

### Task 5: Verification + changelog

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Full suite**

Run: `bundle exec rspec`
Expected: `109 examples, 0 failures`.

- [ ] **Step 2: Confirm agent memory columns consistent across the 3 schema definitions**

Run: `grep -n "memory_scope\|memory_short_term_limit" spec/internal/db/schema.rb db/migrate/009_add_memory_config_to_agents_and_clean_crews.rb lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb`
Expected: both columns appear in all three files.

- [ ] **Step 3: Confirm crew memory columns are gone from schema + generator**

Run: `grep -rn "memory_enabled\|t.text :memory\|:memory," spec/internal/db/schema.rb lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb | grep -i crew || echo "no crew memory columns remain"`
Expected: no crew memory column definitions remain (agent `memory_enabled` still present is fine).

- [ ] **Step 4: Changelog**

In `CHANGELOG.md` under `## [Unreleased]` (append to the existing `### Added` if present, else create it; add a `### Removed` section):

```markdown
### Added
- Agent memory configuration: enable rcrewai 0.6+ cognitive memory per agent via
  the existing `memory_enabled` flag, with `memory_scope` / `memory_short_term_limit`
  columns forwarded to the core agent. The embedder and store come from
  `RcrewAI::Rails.config.default_memory_embedder` / `default_memory_store` (set in
  a host initializer). Memory is off by default, so existing agents are unaffected.

### Removed
- Dropped the unused `memory_enabled` and `memory` columns from `rcrewai_crews`.
  Core memory is agent-level; these crew columns were never wired to anything.
  **Migration note:** the `009` migration removes them (reversible).
```

- [ ] **Step 5: Commit**

```bash
git add CHANGELOG.md
git commit -m "Document agent memory config and crew column cleanup"
```

---

## Notes / Out of scope

- `entity_extractor` config, crew-level memory (core has none), web UI for the new agent memory fields — deferred.
- The core gem's cognitive internals (importance scoring, consolidation) live in rcrewai, not this engine.
