# Group B — Task Output Processing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose rcrewai 0.4/0.5 task output-processing options (`output_schema`, `guardrail`, `output_file`/`markdown`/`create_directory`, multimodal `attachments`) through `RcrewAI::Rails::Task#to_rcrew_task`, persisting config in the DB.

**Architecture:** Add seven columns to `rcrewai_tasks` (host migration + install-generator template + Combustion test schema, kept identical). Thread the options through a public `task_output_options` helper that emits a key only when meaningfully set — guaranteeing byte-identical construction for all-default records. The `guardrail` callable is resolved from `guardrail_class` + `guardrail_method_name` columns, mirroring the model's existing `callback_method` pattern.

**Tech Stack:** Ruby, Rails engine, RSpec + Combustion (schema loaded from `spec/internal/db/schema.rb`, not migrations), rcrewai 0.5.0.

---

## File Structure

- **Modify** `spec/internal/db/schema.rb` — add 7 columns to the `rcrewai_tasks` block (test DB).
- **Modify** `spec/models/task_spec.rb` — add forwarding specs.
- **Modify** `app/models/rcrewai/rails/task.rb` — serializers + `task_output_options` + `guardrail_callable` + `normalized_attachments`, wire into `to_rcrew_task`.
- **Create** `db/migrate/003_add_output_processing_to_rcrewai_tasks.rb` — host migration.
- **Modify** `lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb` — generator template.

**New columns** (identical across all three schema definitions), anchored immediately after the existing `t.string :output_file` line in each `rcrewai_tasks` block:

```ruby
t.text :output_schema
t.string :guardrail_class
t.string :guardrail_method_name
t.integer :guardrail_max_retries, default: 3
t.boolean :create_directory, default: true
t.boolean :markdown, default: false
t.text :attachments
```

`output_file` already exists in all three — reused, not re-added.

**Test strategy:** Spy on `RCrewAI::Task.new` via `and_wrap_original`, capturing kwargs, exactly like the Group A agent specs. For the guardrail, assert the forwarded `:guardrail` value is callable and, when invoked, returns what the host class's method returns.

---

### Task 1: Add columns to the test schema + failing specs

**Files:**
- Modify: `spec/internal/db/schema.rb` (the `create_table :rcrewai_tasks` block)
- Modify: `spec/models/task_spec.rb`

- [ ] **Step 1: Add the columns to the Combustion test schema**

In `spec/internal/db/schema.rb`, inside the `create_table :rcrewai_tasks, force: true do |t|` block, add these seven lines immediately after the existing `t.string :output_file` line:

```ruby
    t.text :output_schema
    t.string :guardrail_class
    t.string :guardrail_method_name
    t.integer :guardrail_max_retries, default: 3
    t.boolean :create_directory, default: true
    t.boolean :markdown, default: false
    t.text :attachments
```

- [ ] **Step 2: Write the failing specs**

Read `spec/models/task_spec.rb` first to see the existing `let(:crew)` / setup and the existing describe structure. Then add this NEW `describe` block inside the top-level `RSpec.describe RcrewAI::Rails::Task` block (after the existing examples, still inside the top-level describe). It defines its own guardrail host class as a top-level constant via a `before`—actually define it as a real constant at the top of the file (below `require "rails_helper"`), because `constantize` needs a resolvable name:

At the top of `spec/models/task_spec.rb`, directly below `require "rails_helper"`, add:

```ruby
class GroupBTestGuardrail
  # Returns the core guardrail contract shape: [ok, value_or_error]
  def check(output)
    [true, output.to_s.upcase]
  end
end
```

Then add the describe block inside the top-level describe:

```ruby
  describe "0.4/0.5 output-processing option forwarding" do
    let(:crew) { RcrewAI::Rails::Crew.create!(name: "C", process_type: "sequential") }

    def build_task(attrs = {})
      crew.tasks.create!({ description: "d", expected_output: "e" }.merge(attrs))
    end

    def capture_task_kwargs
      captured = nil
      allow(RCrewAI::Task).to receive(:new).and_wrap_original do |orig, **kwargs|
        captured = kwargs
        orig.call(**kwargs)
      end
      yield
      captured
    end

    it "forwards none of the new options for an all-default task" do
      captured = capture_task_kwargs { build_task.to_rcrew_task }

      expect(captured).not_to have_key(:output_schema)
      expect(captured).not_to have_key(:guardrail)
      expect(captured).not_to have_key(:guardrail_max_retries)
      expect(captured).not_to have_key(:output_file)
      expect(captured).not_to have_key(:markdown)
      expect(captured).not_to have_key(:attachments)
    end

    it "forwards output_schema as a deep-symbolized hash" do
      schema = { "type" => "object", "properties" => { "name" => { "type" => "string" } } }
      captured = capture_task_kwargs { build_task(output_schema: schema).to_rcrew_task }

      expect(captured[:output_schema]).to eq(
        type: "object", properties: { name: { type: "string" } }
      )
    end

    it "resolves guardrail_class + guardrail_method_name to a working callable" do
      captured = capture_task_kwargs do
        build_task(guardrail_class: "GroupBTestGuardrail", guardrail_method_name: "check").to_rcrew_task
      end

      expect(captured[:guardrail]).to respond_to(:call)
      expect(captured[:guardrail].call("hi")).to eq([true, "HI"])
    end

    it "forwards guardrail_max_retries only when a guardrail class is set" do
      with_guardrail = capture_task_kwargs do
        build_task(
          guardrail_class: "GroupBTestGuardrail",
          guardrail_method_name: "check",
          guardrail_max_retries: 5
        ).to_rcrew_task
      end
      expect(with_guardrail[:guardrail_max_retries]).to eq(5)

      without_guardrail = capture_task_kwargs do
        build_task(guardrail_max_retries: 5).to_rcrew_task
      end
      expect(without_guardrail).not_to have_key(:guardrail_max_retries)
      expect(without_guardrail).not_to have_key(:guardrail)
    end

    it "forwards output_file, markdown, and create_directory" do
      captured = capture_task_kwargs do
        build_task(output_file: "/tmp/out.md", markdown: true, create_directory: false).to_rcrew_task
      end

      expect(captured[:output_file]).to eq("/tmp/out.md")
      expect(captured[:markdown]).to be true
      expect(captured[:create_directory]).to be false
    end

    it "forwards attachments with symbolized keys and a symbol :type" do
      captured = capture_task_kwargs do
        build_task(attachments: [{ "type" => "image", "url" => "http://x/y.png" }]).to_rcrew_task
      end

      expect(captured[:attachments]).to eq([{ type: :image, url: "http://x/y.png" }])
    end
  end
```

- [ ] **Step 3: Run the specs — confirm they fail on BEHAVIOR, not schema**

Run: `bundle exec rspec spec/models/task_spec.rb`
Expected: NO `ActiveModel::UnknownAttributeError` (schema now has the columns). The new positive-forwarding examples FAIL because the model doesn't forward yet (`captured[:output_schema]` nil, `captured[:guardrail]` nil, etc.). The "forwards none of the new options" example PASSES (model forwards nothing yet).

If you see `UnknownAttributeError`, the schema edit in Step 1 is wrong — fix it before continuing.

- [ ] **Step 4: Commit**

```bash
git add spec/internal/db/schema.rb spec/models/task_spec.rb
git commit -m "Add failing specs + test schema for task 0.4/0.5 output options"
```

---

### Task 2: Wire options through `to_rcrew_task`

**Files:**
- Modify: `app/models/rcrewai/rails/task.rb`

- [ ] **Step 1: Add serializers for the two JSON columns**

In `app/models/rcrewai/rails/task.rb`, alongside the existing `serialize` lines (`serialize :context, ...` etc.), add:

```ruby
      serialize :output_schema, coder: JSON
      serialize :attachments, coder: JSON, type: Array
```

- [ ] **Step 2: Wire `task_output_options` into `to_rcrew_task`**

Replace the existing `to_rcrew_task` method:

```ruby
      def to_rcrew_task
        RCrewAI::Task.new(
          name: rcrew_task_name,
          description: description,
          expected_output: expected_output,
          agent: agent&.to_rcrew_agent,
          context: context,
          async: async_execution,
          tools: instantiated_tools,
          callback: callback_method
        )
      end
```

with:

```ruby
      def to_rcrew_task
        RCrewAI::Task.new(
          name: rcrew_task_name,
          description: description,
          expected_output: expected_output,
          agent: agent&.to_rcrew_agent,
          context: context,
          async: async_execution,
          tools: instantiated_tools,
          callback: callback_method,
          **task_output_options
        )
      end

      # rcrewai 0.4/0.5 task output-processing options. Only emit a key when it
      # is meaningfully set, so an all-default record constructs exactly as it
      # did before these options existed.
      def task_output_options
        opts = {}
        opts[:output_schema] = output_schema.deep_symbolize_keys if output_schema.present?
        opts[:guardrail] = guardrail_callable if guardrail_callable
        opts[:guardrail_max_retries] = guardrail_max_retries if guardrail_class.present? && guardrail_max_retries
        opts[:output_file] = output_file if output_file.present?
        opts[:create_directory] = create_directory unless create_directory.nil?
        opts[:markdown] = markdown if markdown
        opts[:attachments] = normalized_attachments if attachments.present?
        opts
      end
```

- [ ] **Step 3: Add the private helpers next to `callback_method`**

In the `private` section of the same file (where `rcrew_task_name` and `callback_method` live), add these two methods:

```ruby
      # Resolves guardrail_class + guardrail_method_name to a callable returning
      # the core [ok, value_or_error] contract. Mirrors callback_method. nil when
      # not configured.
      def guardrail_callable
        return nil unless guardrail_class.present? && guardrail_method_name.present?

        klass = guardrail_class.constantize
        ->(output) { klass.new.send(guardrail_method_name, output) }
      end

      # Symbolizes each attachment hash so { "type" => "image", "url" => ... }
      # becomes { type: :image, url: ... } as the core Multimodal builder expects.
      def normalized_attachments
        attachments.map do |att|
          att.symbolize_keys.tap { |h| h[:type] = h[:type].to_sym if h[:type] }
        end
      end
```

Note: `guardrail_callable` is called twice in `task_output_options` (once in the condition, once for the value). That is intentional and cheap — it just builds a lambda. Do not memoize; keep it simple.

- [ ] **Step 4: Run the task specs — expect green**

Run: `bundle exec rspec spec/models/task_spec.rb`
Expected: PASS — all examples green, including the all-default regression guard.

- [ ] **Step 5: Run the full suite**

Run: `bundle exec rspec`
Expected: PASS — 56 examples, 0 failures (50 prior + 6 new).

- [ ] **Step 6: Commit**

```bash
git add app/models/rcrewai/rails/task.rb
git commit -m "Forward rcrewai 0.4/0.5 task output options through to_rcrew_task"
```

---

### Task 3: Ship the host-app migration

**Files:**
- Create: `db/migrate/003_add_output_processing_to_rcrewai_tasks.rb`

- [ ] **Step 1: Write the migration**

Create `db/migrate/003_add_output_processing_to_rcrewai_tasks.rb`:

```ruby
class AddOutputProcessingToRcrewaiTasks < ActiveRecord::Migration[7.0]
  def change
    # output_file already exists on rcrewai_tasks from the original create
    # table; only the new 0.4/0.5 output-processing options are added here.
    add_column :rcrewai_tasks, :output_schema, :text
    add_column :rcrewai_tasks, :guardrail_class, :string
    add_column :rcrewai_tasks, :guardrail_method_name, :string
    add_column :rcrewai_tasks, :guardrail_max_retries, :integer, default: 3
    add_column :rcrewai_tasks, :create_directory, :boolean, default: true
    add_column :rcrewai_tasks, :markdown, :boolean, default: false
    add_column :rcrewai_tasks, :attachments, :text
  end
end
```

- [ ] **Step 2: Verify syntax**

Run: `ruby -c db/migrate/003_add_output_processing_to_rcrewai_tasks.rb`
Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add db/migrate/003_add_output_processing_to_rcrewai_tasks.rb
git commit -m "Add host-app migration for task 0.4/0.5 output columns"
```

---

### Task 4: Update the install-generator template

**Files:**
- Modify: `lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb` (the `create_table :rcrewai_tasks` block)

- [ ] **Step 1: Add the columns to the generator template**

In the `create_table :rcrewai_tasks do |t|` block of `lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb`, add these seven lines immediately after the existing `t.string :output_file` line (matching the block's 6-space indentation):

```ruby
      t.text :output_schema
      t.string :guardrail_class
      t.string :guardrail_method_name
      t.integer :guardrail_max_retries, default: 3
      t.boolean :create_directory, default: true
      t.boolean :markdown, default: false
      t.text :attachments
```

- [ ] **Step 2: Verify syntax**

Run: `ruby -c lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb`
Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb
git commit -m "Include task 0.4/0.5 output columns in install generator"
```

---

### Task 5: Full-suite verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full suite**

Run: `bundle exec rspec`
Expected: `56 examples, 0 failures`.

- [ ] **Step 2: Confirm schema consistency across the three definitions**

Run: `grep -A2 "output_file" spec/internal/db/schema.rb db/migrate/003_add_output_processing_to_rcrewai_tasks.rb lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb`
Expected: the seven new column names appear with identical types/defaults in all three files (allowing for `add_column ...` vs `t.<type>` syntax differences). No commit needed — this is a check.

---

## Notes / Out of scope

- **Per-task result persistence** (`structured_output`/`raw_result` back to DB rows) — deferred; see the Group B spec "Out of scope" section.
- **Web UI controls** for the new fields — follow-up.
- **Groups C/D** — separate specs.
- Legacy `output_json` / `output_pydantic` columns — left untouched.
