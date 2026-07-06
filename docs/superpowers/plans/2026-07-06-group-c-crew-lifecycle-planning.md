# Group C — Crew Lifecycle Hooks + Planning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose rcrewai 0.5.0 crew `before_kickoff`/`after_kickoff` lifecycle hooks and `planning`/`planning_llm` options through `RcrewAI::Rails::Crew#to_rcrew`.

**Architecture:** Add six columns to `rcrewai_crews` (host migration + install-generator template + Combustion test schema, kept identical). Thread `planning`/`planning_llm` through a `crew_planning_options` helper (emit only when set), and register kickoff hooks resolved from `*_class`/`*_method` columns via a `hook_callable` helper mirroring the guardrail/callback pattern. No job-layer change — hooks run inside the core `#execute`, which the job already calls.

**Tech Stack:** Ruby, Rails engine, RSpec + Combustion (schema from `spec/internal/db/schema.rb`, not migrations), rcrewai 0.5.0.

---

## File Structure

- **Modify** `spec/internal/db/schema.rb` — add 6 columns to the `rcrewai_crews` block.
- **Modify** `spec/models/crew_spec.rb` — add forwarding + hook-registration specs.
- **Modify** `app/models/rcrewai/rails/crew.rb` — `crew_planning_options` + `register_kickoff_hooks` + `hook_callable`, wire into `to_rcrew`.
- **Create** `db/migrate/004_add_lifecycle_to_rcrewai_crews.rb` — host migration.
- **Modify** `lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb` — generator template.

**New columns** (identical across all three definitions), anchored immediately after the existing `t.string :manager_llm` line in each `rcrewai_crews` block:

```ruby
t.boolean :planning, default: false, null: false
t.string :planning_llm
t.string :before_kickoff_class
t.string :before_kickoff_method
t.string :after_kickoff_class
t.string :after_kickoff_method
```

**Test strategy:** For planning, spy on `RCrewAI::Crew.new` via `and_wrap_original`, capturing the positional name + kwargs. For hooks, spy on the built crew's `before_kickoff`/`after_kickoff` to capture the registered block, then invoke it and assert it calls through to the host class.

---

### Task 1: Add columns to the test schema + failing specs

**Files:**
- Modify: `spec/internal/db/schema.rb` (the `create_table :rcrewai_crews` block)
- Modify: `spec/models/crew_spec.rb`

- [ ] **Step 1: Add the columns to the Combustion test schema**

In `spec/internal/db/schema.rb`, inside the `create_table :rcrewai_crews, force: true do |t|` block, add these six lines immediately after the existing `t.string :manager_llm` line:

```ruby
    t.boolean :planning, default: false, null: false
    t.string :planning_llm
    t.string :before_kickoff_class
    t.string :before_kickoff_method
    t.string :after_kickoff_class
    t.string :after_kickoff_method
```

- [ ] **Step 2: Write the failing specs**

First READ `spec/models/crew_spec.rb` to see its existing structure (top-level `RSpec.describe RcrewAI::Rails::Crew` and any `let`/setup).

At the TOP of `spec/models/crew_spec.rb`, directly below `require "rails_helper"`, add these host classes (needed because hook resolution uses `constantize`, which needs resolvable names):

```ruby
class GroupCBeforeHook
  def call(inputs)
    inputs.merge(seen: true)
  end
end

class GroupCAfterHook
  def call(result)
    "wrapped: #{result}"
  end
end
```

Then add this NEW `describe` block. Placement matters: the file has a top-level `RSpec.describe RcrewAI::Rails::Crew, type: :model do` containing a single nested `describe "#to_rcrew" do ... end`. Add your new block as a SIBLING of `#to_rcrew` — i.e. AFTER the `#to_rcrew` block's closing `end`, but BEFORE the final top-level `end`. Your block defines its own `build_crew` helper and does not use the `#to_rcrew` block's `let(:crew)`.

```ruby
  describe "0.5.0 lifecycle + planning forwarding" do
    def build_crew(attrs = {})
      RcrewAI::Rails::Crew.create!({ name: "C", process_type: "sequential" }.merge(attrs))
    end

    it "forwards no planning options and registers no hooks for an all-default crew" do
      captured = nil
      allow(RCrewAI::Crew).to receive(:new).and_wrap_original do |orig, name, **kwargs|
        captured = kwargs
        orig.call(name, **kwargs)
      end

      crew = build_crew.to_rcrew

      expect(captured).not_to have_key(:planning)
      expect(captured).not_to have_key(:planning_llm)
      # Core Crew stores registered hooks in these ivars; none should be present.
      expect(crew.instance_variable_get(:@before_kickoff_hooks)).to be_empty
      expect(crew.instance_variable_get(:@after_kickoff_hooks)).to be_empty
    end

    it "forwards planning and planning_llm (as a symbol) when set" do
      captured = nil
      allow(RCrewAI::Crew).to receive(:new).and_wrap_original do |orig, name, **kwargs|
        captured = kwargs
        orig.call(name, **kwargs)
      end

      build_crew(planning: true, planning_llm: "anthropic").to_rcrew

      expect(captured[:planning]).to be true
      expect(captured[:planning_llm]).to eq(:anthropic)
    end

    it "registers a before_kickoff hook that calls through to the host class" do
      captured_block = nil
      allow_any_instance_of(RCrewAI::Crew).to receive(:before_kickoff) do |_crew, &blk|
        captured_block = blk
      end

      build_crew(before_kickoff_class: "GroupCBeforeHook", before_kickoff_method: "call").to_rcrew

      expect(captured_block).not_to be_nil
      expect(captured_block.call({ a: 1 })).to eq({ a: 1, seen: true })
    end

    it "registers an after_kickoff hook that calls through to the host class" do
      captured_block = nil
      allow_any_instance_of(RCrewAI::Crew).to receive(:after_kickoff) do |_crew, &blk|
        captured_block = blk
      end

      build_crew(after_kickoff_class: "GroupCAfterHook", after_kickoff_method: "call").to_rcrew

      expect(captured_block).not_to be_nil
      expect(captured_block.call("done")).to eq("wrapped: done")
    end

    it "does not register a hook when only the class is set (method blank)" do
      crew = build_crew(before_kickoff_class: "GroupCBeforeHook").to_rcrew

      expect(crew.instance_variable_get(:@before_kickoff_hooks)).to be_empty
    end
  end
```

- [ ] **Step 3: Run the specs — confirm they fail on BEHAVIOR, not schema**

Run: `bundle exec rspec spec/models/crew_spec.rb`
Expected: NO `ActiveModel::UnknownAttributeError` (schema now has the columns). The planning-forwarding and hook-registration examples FAIL because the model doesn't forward/register yet. The "all-default" example PASSES (nothing forwarded/registered yet). The "only class set" example PASSES (still nothing registered).

If you see `UnknownAttributeError`, the Step 1 schema edit is wrong — fix it before continuing. Do NOT implement the model change (that is Task 2).

- [ ] **Step 4: Commit**

```bash
git add spec/internal/db/schema.rb spec/models/crew_spec.rb
git commit -m "Add failing specs + test schema for crew 0.5.0 lifecycle options"
```

---

### Task 2: Wire planning + hooks into `to_rcrew`

**Files:**
- Modify: `app/models/rcrewai/rails/crew.rb`

- [ ] **Step 1: Replace `to_rcrew` and add the helpers**

In `app/models/rcrewai/rails/crew.rb`, replace the existing `to_rcrew` method:

```ruby
      def to_rcrew
        crew = RCrewAI::Crew.new(
          name,
          process: process_type.to_sym,
          verbose: verbose
        )

        agents.each do |agent|
          crew.add_agent(agent.to_rcrew_agent)
        end

        tasks.each do |task|
          crew.add_task(task.to_rcrew_task)
        end

        crew
      end
```

with:

```ruby
      def to_rcrew
        crew = RCrewAI::Crew.new(
          name,
          process: process_type.to_sym,
          verbose: verbose,
          **crew_planning_options
        )

        agents.each do |agent|
          crew.add_agent(agent.to_rcrew_agent)
        end

        tasks.each do |task|
          crew.add_task(task.to_rcrew_task)
        end

        register_kickoff_hooks(crew)
        crew
      end

      # rcrewai 0.5.0 planning options. Emit a key only when meaningfully set, so
      # an all-default crew constructs exactly as it did before.
      def crew_planning_options
        opts = {}
        opts[:planning] = planning if planning
        opts[:planning_llm] = planning_llm.to_sym if planning_llm.present?
        opts
      end
```

- [ ] **Step 2: Add the private hook helpers**

Add a `private` section (or extend the existing one if present) to `app/models/rcrewai/rails/crew.rb` with these two methods:

```ruby
      private

      # Registers before/after kickoff hooks resolved from *_class + *_method
      # columns, mirroring the guardrail/callback pattern. No-op when unconfigured.
      def register_kickoff_hooks(crew)
        if (before = hook_callable(before_kickoff_class, before_kickoff_method))
          crew.before_kickoff { |inputs| before.call(inputs) }
        end

        if (after = hook_callable(after_kickoff_class, after_kickoff_method))
          crew.after_kickoff { |result| after.call(result) }
        end
      end

      # Resolves a *_class + *_method pair to a callable; nil when either is blank.
      def hook_callable(class_name, method_name)
        return nil unless class_name.present? && method_name.present?

        klass = class_name.constantize
        ->(arg) { klass.new.send(method_name, arg) }
      end
```

Note: check whether `crew.rb` already has a `private` keyword. The current file's methods (`to_rcrew`, `execute_async`, `execute_sync`, `last_execution`, `execution_stats`) are all public and there is NO `private` section. So ADD a `private` keyword before these two new methods, placing them after the existing public methods and before the final `end`s. `crew_planning_options` stays PUBLIC (matching the Group A/B convention where the `*_options` helper is public).

- [ ] **Step 3: Run the crew specs — expect green**

Run: `bundle exec rspec spec/models/crew_spec.rb`
Expected: PASS — all examples green, including the all-default regression guard.

- [ ] **Step 4: Run the full suite**

Run: `bundle exec rspec`
Expected: PASS — 62 examples, 0 failures (57 prior + 5 new).

- [ ] **Step 5: Commit**

```bash
git add app/models/rcrewai/rails/crew.rb
git commit -m "Forward crew planning + register lifecycle hooks in to_rcrew"
```

---

### Task 3: Ship the host-app migration

**Files:**
- Create: `db/migrate/004_add_lifecycle_to_rcrewai_crews.rb`

- [ ] **Step 1: Write the migration**

Create `db/migrate/004_add_lifecycle_to_rcrewai_crews.rb`:

```ruby
class AddLifecycleToRcrewaiCrews < ActiveRecord::Migration[7.0]
  def change
    add_column :rcrewai_crews, :planning, :boolean, default: false, null: false
    add_column :rcrewai_crews, :planning_llm, :string
    add_column :rcrewai_crews, :before_kickoff_class, :string
    add_column :rcrewai_crews, :before_kickoff_method, :string
    add_column :rcrewai_crews, :after_kickoff_class, :string
    add_column :rcrewai_crews, :after_kickoff_method, :string
  end
end
```

- [ ] **Step 2: Verify syntax**

Run: `ruby -c db/migrate/004_add_lifecycle_to_rcrewai_crews.rb`
Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add db/migrate/004_add_lifecycle_to_rcrewai_crews.rb
git commit -m "Add host-app migration for crew 0.5.0 lifecycle columns"
```

---

### Task 4: Update the install-generator template

**Files:**
- Modify: `lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb` (the `create_table :rcrewai_crews` block)

- [ ] **Step 1: Add the columns to the generator template**

In the `create_table :rcrewai_crews do |t|` block of `lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb`, add these six lines immediately after the existing `t.string :manager_llm` line (matching the block's 6-space indentation):

```ruby
      t.boolean :planning, default: false, null: false
      t.string :planning_llm
      t.string :before_kickoff_class
      t.string :before_kickoff_method
      t.string :after_kickoff_class
      t.string :after_kickoff_method
```

- [ ] **Step 2: Verify syntax**

Run: `ruby -c lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb`
Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb
git commit -m "Include crew 0.5.0 lifecycle columns in install generator"
```

---

### Task 5: Full-suite verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full suite**

Run: `bundle exec rspec`
Expected: `62 examples, 0 failures`.

- [ ] **Step 2: Confirm schema consistency across the three definitions**

Run: `grep -E "planning|before_kickoff|after_kickoff" spec/internal/db/schema.rb db/migrate/004_add_lifecycle_to_rcrewai_crews.rb lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb`
Expected: the six new column names appear with identical types/defaults in all three files (allowing for `add_column ...` vs `t.<type>` syntax). No commit — this is a check.

---

## Notes / Out of scope

- **Batch (`kickoff_for_each`), train/test** — deferred to a later spec (Group C2); need Execution-record modeling decisions.
- **Web UI controls** for the new fields — follow-up.
- **Group D** (Flows / Knowledge-RAG) — separate spec.
