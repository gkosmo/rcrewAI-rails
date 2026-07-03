# Group A — Agent-level Config Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose rcrewai 0.5.0's agent-level options (`max_rpm`, `reasoning`, `respect_context_window`, per-agent `llm:`) through `RcrewAI::Rails::Agent#to_rcrew_agent`, and fix the latent bug where existing `max_rpm`/`llm_config` columns are never forwarded.

**Architecture:** Add three columns to `rcrewai_agents` (engine migration + Combustion test schema), then thread all agent options through `to_rcrew_agent` via a private `agent_options` helper that only emits keys that are meaningfully set — guaranteeing byte-identical construction for all-default records. Also bump the gemspec to `rcrewai ~> 0.5`.

**Tech Stack:** Ruby, Rails engine, RSpec + Combustion (schema loaded from `spec/internal/db/schema.rb`, not migrations), rcrewai 0.5.0.

---

## File Structure

- **Modify** `rcrewai-rails.gemspec` — bump core dep to `~> 0.5`.
- **Create** `db/migrate/002_add_config_to_rcrewai_agents.rb` — shipped migration for host apps.
- **Modify** `spec/internal/db/schema.rb` — add the three columns so the test DB has them (Combustion loads schema, not migrations).
- **Modify** `app/models/rcrewai/rails/agent.rb` — add `serialize :llm_config`? (already serialized) + `agent_options` helper + wire into `to_rcrew_agent`.
- **Modify** `spec/models/agent_spec.rb` — regression guard + per-option forwarding specs.

**Test strategy note:** The built `RCrewAI::Agent` only exposes `max_rpm` indirectly (via a non-nil `#rate_limiter`); `reasoning`/`respect_context_window`/`max_reasoning_attempts` have no public readers. So flag-forwarding is verified by spying on `RCrewAI::Agent.new` and asserting kwargs; `max_rpm` also gets one real-construction check via `#rate_limiter`.

---

### Task 1: Bump gemspec to rcrewai ~> 0.5

**Files:**
- Modify: `rcrewai-rails.gemspec` (the `spec.add_dependency "rcrewai"` line)

- [ ] **Step 1: Change the constraint**

In `rcrewai-rails.gemspec`, change:

```ruby
  spec.add_dependency "rcrewai", "~> 0.3"
```

to:

```ruby
  spec.add_dependency "rcrewai", "~> 0.5"
```

- [ ] **Step 2: Re-resolve and run the full suite to confirm nothing broke**

Run: `bundle install && bundle exec rspec`
Expected: `bundle install` resolves `rcrewai 0.5.0`; suite reports `43 examples, 0 failures`.

- [ ] **Step 3: Commit**

```bash
git add rcrewai-rails.gemspec Gemfile.lock 2>/dev/null; git add rcrewai-rails.gemspec
git commit -m "Require rcrewai ~> 0.5"
```

---

### Task 2: Add config columns to the test schema (failing-test setup)

**Files:**
- Modify: `spec/internal/db/schema.rb` (the `create_table :rcrewai_agents` block, around line 23)
- Test: `spec/models/agent_spec.rb`

- [ ] **Step 1: Write the failing test**

Add inside the top-level `describe RcrewAI::Rails::Agent` block in `spec/models/agent_spec.rb`, as a new `describe`:

```ruby
  describe "0.5.0 option forwarding" do
    def build_agent(attrs = {})
      crew.agents.create!({ name: "a", role: "R", goal: "G" }.merge(attrs))
    end

    it "does not forward any new options for an all-default agent" do
      captured = nil
      allow(RCrewAI::Agent).to receive(:new).and_wrap_original do |orig, **kwargs|
        captured = kwargs
        orig.call(**kwargs)
      end

      build_agent.to_rcrew_agent

      expect(captured).not_to have_key(:max_rpm)
      expect(captured).not_to have_key(:reasoning)
      expect(captured).not_to have_key(:max_reasoning_attempts)
      expect(captured).not_to have_key(:respect_context_window)
      expect(captured).not_to have_key(:llm)
    end

    it "forwards max_rpm and builds a rate limiter" do
      agent = build_agent(max_rpm: 30).to_rcrew_agent
      expect(agent.rate_limiter).not_to be_nil
    end

    it "forwards reasoning and max_reasoning_attempts when reasoning is on" do
      captured = nil
      allow(RCrewAI::Agent).to receive(:new).and_wrap_original do |orig, **kwargs|
        captured = kwargs
        orig.call(**kwargs)
      end

      build_agent(reasoning: true, max_reasoning_attempts: 5).to_rcrew_agent

      expect(captured[:reasoning]).to be true
      expect(captured[:max_reasoning_attempts]).to eq(5)
    end

    it "does not forward reasoning attempts when reasoning is off" do
      captured = nil
      allow(RCrewAI::Agent).to receive(:new).and_wrap_original do |orig, **kwargs|
        captured = kwargs
        orig.call(**kwargs)
      end

      build_agent(reasoning: false, max_reasoning_attempts: 5).to_rcrew_agent

      expect(captured).not_to have_key(:reasoning)
      expect(captured).not_to have_key(:max_reasoning_attempts)
    end

    it "forwards respect_context_window when enabled" do
      captured = nil
      allow(RCrewAI::Agent).to receive(:new).and_wrap_original do |orig, **kwargs|
        captured = kwargs
        orig.call(**kwargs)
      end

      build_agent(respect_context_window: true).to_rcrew_agent

      expect(captured[:respect_context_window]).to be true
    end

    it "forwards llm_config as a symbolized llm: hash" do
      captured = nil
      allow(RCrewAI::Agent).to receive(:new).and_wrap_original do |orig, **kwargs|
        captured = kwargs
        orig.call(**kwargs)
      end

      build_agent(llm_config: { "provider" => "anthropic", "model" => "claude-sonnet-5" }).to_rcrew_agent

      expect(captured[:llm]).to eq(provider: "anthropic", model: "claude-sonnet-5")
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail on the missing columns**

Run: `bundle exec rspec spec/models/agent_spec.rb`
Expected: FAIL — `create!` raises `ActiveModel::UnknownAttributeError: unknown attribute 'reasoning'` (schema doesn't have the columns yet).

- [ ] **Step 3: Add the columns to the Combustion test schema**

In `spec/internal/db/schema.rb`, inside the `create_table :rcrewai_agents, force: true do |t|` block, add these three lines immediately after the existing `t.text :llm_config` line (`max_rpm` and `llm_config` are already present in this block):

```ruby
    t.boolean :reasoning, default: false, null: false
    t.integer :max_reasoning_attempts, default: 3
    t.boolean :respect_context_window, default: false, null: false
```

- [ ] **Step 4: Run the tests to see them fail on behavior, not schema**

Run: `bundle exec rspec spec/models/agent_spec.rb`
Expected: The all-default and forwarding examples now FAIL on expectations (e.g. `captured[:reasoning]` is nil / options not forwarded), NOT on `UnknownAttributeError`. This confirms the schema is fixed and the model change is what's missing.

- [ ] **Step 5: Commit the schema + specs**

```bash
git add spec/internal/db/schema.rb spec/models/agent_spec.rb
git commit -m "Add failing specs + test schema for agent 0.5.0 options"
```

---

### Task 3: Wire agent options through `to_rcrew_agent`

**Files:**
- Modify: `app/models/rcrewai/rails/agent.rb`

- [ ] **Step 1: Add the `agent_options` helper and call it from `to_rcrew_agent`**

In `app/models/rcrewai/rails/agent.rb`, replace the existing `to_rcrew_agent` method:

```ruby
      def to_rcrew_agent
        RCrewAI::Agent.new(
          name: name,
          role: role,
          goal: goal,
          backstory: backstory,
          verbose: verbose,
          allow_delegation: allow_delegation,
          tools: instantiated_tools,
          max_iterations: max_iterations
        )
      end
```

with:

```ruby
      def to_rcrew_agent
        RCrewAI::Agent.new(
          name: name,
          role: role,
          goal: goal,
          backstory: backstory,
          verbose: verbose,
          allow_delegation: allow_delegation,
          tools: instantiated_tools,
          max_iterations: max_iterations,
          **agent_options
        )
      end

      # rcrewai 0.5.0 agent options. Only emit a key when it is meaningfully
      # set, so an all-default record constructs exactly as it did pre-0.5.
      def agent_options
        opts = {}
        opts[:max_rpm] = max_rpm if max_rpm.present?
        opts[:reasoning] = reasoning if reasoning
        opts[:max_reasoning_attempts] = max_reasoning_attempts if reasoning && max_reasoning_attempts
        opts[:respect_context_window] = respect_context_window if respect_context_window
        opts[:llm] = llm_config.symbolize_keys if llm_config.present?
        opts
      end
```

- [ ] **Step 2: Run the agent specs to verify they pass**

Run: `bundle exec rspec spec/models/agent_spec.rb`
Expected: PASS — all examples green, including the all-default regression guard.

- [ ] **Step 3: Run the full suite to confirm no regressions**

Run: `bundle exec rspec`
Expected: PASS — `49 examples, 0 failures` (43 prior + 6 new).

- [ ] **Step 4: Commit**

```bash
git add app/models/rcrewai/rails/agent.rb
git commit -m "Forward rcrewai 0.5.0 agent options through to_rcrew_agent"
```

---

### Task 4: Ship the host-app migration

**Files:**
- Create: `db/migrate/002_add_config_to_rcrewai_agents.rb`

- [ ] **Step 1: Write the migration**

Create `db/migrate/002_add_config_to_rcrewai_agents.rb`:

```ruby
class AddConfigToRcrewaiAgents < ActiveRecord::Migration[7.0]
  def change
    # max_rpm and llm_config already exist on rcrewai_agents from the
    # original create table; only the 0.5.0 additions are new.
    add_column :rcrewai_agents, :reasoning, :boolean, default: false, null: false
    add_column :rcrewai_agents, :max_reasoning_attempts, :integer, default: 3
    add_column :rcrewai_agents, :respect_context_window, :boolean, default: false, null: false
  end
end
```

- [ ] **Step 2: Verify it loads (syntax + AR migration validity)**

Run: `ruby -c db/migrate/002_add_config_to_rcrewai_agents.rb`
Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add db/migrate/002_add_config_to_rcrewai_agents.rb
git commit -m "Add host-app migration for agent 0.5.0 config columns"
```

---

### Task 5: Update the install-generator table template (keep fresh installs in sync)

**Files:**
- Modify: `lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb` (the `create_table :rcrewai_agents` block)

- [ ] **Step 1: Add the new columns to the generator template**

In the `create_table :rcrewai_agents do |t|` block of `lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb`, add alongside the existing `t.integer :max_rpm` line:

```ruby
      t.boolean :reasoning, default: false, null: false
      t.integer :max_reasoning_attempts, default: 3
      t.boolean :respect_context_window, default: false, null: false
```

- [ ] **Step 2: Verify syntax**

Run: `ruby -c lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb`
Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb
git commit -m "Include agent 0.5.0 config columns in install generator"
```

---

## Notes / Out of scope

- **Schema drift (pre-existing):** the repo references a `Tool` model + `rcrewai_tools` table created only in `db/migrate/001_add_agent_to_tasks.rb` and not in the install template; `Agent` also has a `has_many :tools` / `serialize :tools` conflict (documented in `agent_spec.rb`). NOT addressed here — separate change.
- **Web UI controls** for the new fields — follow-up.
- **Groups B/C/D** — separate specs.
