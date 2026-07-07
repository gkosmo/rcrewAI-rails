# Group E (Part 1) — Consensual Process + Constraint Bump Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Let Rails crews use rcrewai 0.7.0's `:consensual` process (forwarding `consensus_agents`), and require `rcrewai ~> 0.7`.

**Architecture:** Widen the Crew `process_type` validation to include `consensual`; add a nullable `consensus_agents` column (host migration + generator + test schema); forward it via the existing `crew_planning_options` helper; add the UI dropdown option + strong-params; bump the gemspec.

**Tech Stack:** Ruby, Rails engine, RSpec + Combustion, rcrewai 0.7.0 (local sibling).

---

### Task 1: Model validation + consensus_agents forwarding (schema + specs + wiring)

**Files:**
- Modify: `spec/internal/db/schema.rb`, `spec/models/crew_spec.rb`, `app/models/rcrewai/rails/crew.rb`

- [ ] **Step 1: Add the column to the test schema**

In `spec/internal/db/schema.rb`, inside the `create_table :rcrewai_crews` block, add immediately after `t.string :manager_llm`:

```ruby
    t.integer :consensus_agents
```

- [ ] **Step 2: Write failing specs**

In `spec/models/crew_spec.rb`, add inside the top-level `RSpec.describe RcrewAI::Rails::Crew` block (sibling of existing describes, before the final top-level `end`):

```ruby
  describe "consensual process" do
    it "accepts the consensual process_type" do
      crew = RcrewAI::Rails::Crew.new(name: "C", process_type: "consensual")
      expect(crew).to be_valid
    end

    it "still rejects an unknown process_type" do
      crew = RcrewAI::Rails::Crew.new(name: "C", process_type: "bogus")
      expect(crew).not_to be_valid
    end

    it "forwards consensus_agents when set" do
      c = RcrewAI::Rails::Crew.create!(name: "C", process_type: "consensual", consensus_agents: 5)
      captured = nil
      allow(RCrewAI::Crew).to receive(:new).and_wrap_original do |orig, name, **kwargs|
        captured = kwargs
        orig.call(name, **kwargs)
      end
      c.to_rcrew
      expect(captured[:consensus_agents]).to eq(5)
    end

    it "does not forward consensus_agents when nil" do
      c = RcrewAI::Rails::Crew.create!(name: "C", process_type: "sequential")
      captured = nil
      allow(RCrewAI::Crew).to receive(:new).and_wrap_original do |orig, name, **kwargs|
        captured = kwargs
        orig.call(name, **kwargs)
      end
      c.to_rcrew
      expect(captured).not_to have_key(:consensus_agents)
    end
  end
```

- [ ] **Step 3: Run — confirm behavioral failures, not schema**

Run: `bundle exec rspec spec/models/crew_spec.rb`
Expected: "accepts the consensual process_type" FAILS (validation rejects it); "forwards consensus_agents" FAILS (not forwarded). No `UnknownAttributeError`. If you see one, the Step 1 schema edit is wrong.

- [ ] **Step 4: Widen validation + forward the option**

In `app/models/rcrewai/rails/crew.rb`, change:

```ruby
      validates :process_type, inclusion: { in: %w[sequential hierarchical] }
```

to:

```ruby
      validates :process_type, inclusion: { in: %w[sequential hierarchical consensual] }
```

Then in `crew_planning_options`, add immediately before the final `opts` return:

```ruby
        opts[:consensus_agents] = consensus_agents if consensus_agents.present?
```

- [ ] **Step 5: Run — expect green**

Run: `bundle exec rspec spec/models/crew_spec.rb`
Expected: PASS.

- [ ] **Step 6: Full suite**

Run: `bundle exec rspec`
Expected: `103 examples, 0 failures` (99 + 4 new).

- [ ] **Step 7: Commit**

```bash
git add spec/internal/db/schema.rb spec/models/crew_spec.rb app/models/rcrewai/rails/crew.rb
git commit -m "Support the consensual process type in the Crew model"
```

---

### Task 2: Migration + generator + UI + strong-params

**Files:**
- Create: `db/migrate/008_add_consensus_agents_to_rcrewai_crews.rb`
- Modify: `lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb`
- Modify: `app/views/rcrewai/rails/crews/new.html.erb`, `.../edit.html.erb`
- Modify: `app/controllers/rcrewai/rails/crews_controller.rb`, `.../api/v1/crews_controller.rb`

- [ ] **Step 1: Migration**

Create `db/migrate/008_add_consensus_agents_to_rcrewai_crews.rb`:

```ruby
class AddConsensusAgentsToRcrewaiCrews < ActiveRecord::Migration[7.0]
  def change
    add_column :rcrewai_crews, :consensus_agents, :integer
  end
end
```

Verify: `ruby -c db/migrate/008_add_consensus_agents_to_rcrewai_crews.rb` → `Syntax OK`.

- [ ] **Step 2: Generator template**

In `lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb`, in the `create_table :rcrewai_crews` block, add immediately after `t.string :manager_llm`:

```ruby
      t.integer :consensus_agents
```

Verify syntax with `ruby -c`.

- [ ] **Step 3: UI dropdowns**

In BOTH `app/views/rcrewai/rails/crews/new.html.erb` and `app/views/rcrewai/rails/crews/edit.html.erb`, the `form.select :process_type` options array currently is:

```erb
            ['Sequential', 'sequential'],
            ['Hierarchical', 'hierarchical']
```

Add a third entry so it reads:

```erb
            ['Sequential', 'sequential'],
            ['Hierarchical', 'hierarchical'],
            ['Consensual', 'consensual']
```

- [ ] **Step 4: Strong params (both controllers)**

In `app/controllers/rcrewai/rails/crews_controller.rb` AND `app/controllers/rcrewai/rails/api/v1/crews_controller.rb`, the `crew_params` permit list ends with `:manager_llm, :active`. Add `:consensus_agents`:

```ruby
              :memory_enabled, :cache_enabled, :max_rpm, :manager_llm, :consensus_agents, :active
```

- [ ] **Step 5: Full suite + syntax**

Run: `bundle exec rspec`
Expected: `103 examples, 0 failures`.
Run: `ruby -c app/controllers/rcrewai/rails/crews_controller.rb app/controllers/rcrewai/rails/api/v1/crews_controller.rb` → `Syntax OK` for both.

- [ ] **Step 6: Commit**

```bash
git add db/migrate/008_add_consensus_agents_to_rcrewai_crews.rb lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb app/views/rcrewai/rails/crews/new.html.erb app/views/rcrewai/rails/crews/edit.html.erb app/controllers/rcrewai/rails/crews_controller.rb app/controllers/rcrewai/rails/api/v1/crews_controller.rb
git commit -m "Expose consensual process in migration, generator, UI, and params"
```

---

### Task 3: Bump the rcrewai constraint + CI ref + changelog

**Files:**
- Modify: `rcrewai-rails.gemspec`, `.github/workflows/ci.yml`, `CHANGELOG.md`

- [ ] **Step 1: Bump the constraint**

In `rcrewai-rails.gemspec`, change `spec.add_dependency "rcrewai", "~> 0.5"` to `spec.add_dependency "rcrewai", "~> 0.7"`.

- [ ] **Step 2: Bump the CI rcrewAI checkout ref (REQUIRED — else CI fails to resolve)**

The CI workflow checks out the sibling `gkosmo/rcrewAI` repo at a pinned tag so the `path: "../rcrewAI"` Gemfile dep resolves. It currently pins `ref: v0.5.0`, which does NOT satisfy `~> 0.7`. In `.github/workflows/ci.yml`, change:

```yaml
          ref: v0.5.0
```

to:

```yaml
          ref: v0.7.0
```

(The `v0.7.0` tag exists on the rcrewAI remote — verified.)

- [ ] **Step 3: Re-resolve locally + full suite**

The LOCAL `../rcrewAI` sibling is already at 0.7.0, so:
Run: `bundle install && bundle exec rspec`
Expected: bundle resolves rcrewai 0.7.0; `103 examples, 0 failures`.

- [ ] **Step 4: Changelog**

In `CHANGELOG.md` under `## [Unreleased]`, add:

```markdown
### Added
- Support the rcrewai 0.7.0 `:consensual` crew process: `process_type:
  "consensual"` is now valid, a nullable `consensus_agents` column is forwarded to
  the core crew (defaulting to the core's 3 when unset), and the web UI + API
  permit it. Existing sequential/hierarchical crews are unaffected.

### Changed
- Require `rcrewai ~> 0.7` (was `~> 0.5`).
```

- [ ] **Step 5: Commit**

```bash
git add rcrewai-rails.gemspec .github/workflows/ci.yml CHANGELOG.md
git commit -m "Require rcrewai ~> 0.7 and document consensual support"
```

---

## Notes / Out of scope

- **Memory config forwarding** (0.6.0/0.6.1) + stale `memory`/`memory_enabled` column cleanup — Part 2, separate spec.
- The `consensus_agents` CI runs against the local `../rcrewAI` v0.7.0 sibling (the CI workflow checks out a pinned rcrewAI ref — confirm it points at a 0.7.x tag, or bump it, since `~> 0.7` requires it).
