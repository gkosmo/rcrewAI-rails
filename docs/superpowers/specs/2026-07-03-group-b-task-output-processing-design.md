# Group B — Task-level output processing (rcrewai 0.4/0.5)

**Date:** 2026-07-03
**Status:** Draft — awaiting user review
**Scope:** Second of the decomposed parity effort. Follows Group A (agent config,
merged in PR #6). Exposes the 0.4/0.5 task output-processing options through
`RcrewAI::Rails::Task`.

## Context

Group A established the pattern: add columns across three synchronized schema
definitions (host migration, install-generator template, Combustion test
schema), and forward options through a `*_options` helper that emits a key only
when meaningfully set — guaranteeing byte-identical construction for all-default
records. Group B applies the same pattern to `Task`.

The 0.4/0.5 `Task.new(**options)` accepts these output-processing options:

- `output_schema:` — a JSON-schema-subset hash. Validates/coerces agent output;
  exposed post-run via `Task#structured_output` (+ raw via `Task#raw_result`).
- `guardrail:` — a callable `->(output) { [ok, value_or_error] }`. Validates/
  transforms output, retrying up to `guardrail_max_retries` (default 3).
- `output_file:` — path to write the result to; `create_directory:` (default
  true) controls parent-dir creation; `markdown: true` prepends a heading.
- `attachments:` — array of image inputs (`{ type: :image, url: '...' }` or
  `{ type: :image, path: '...' }`) for multimodal tasks.

## Goal

Expose all of the above through `RcrewAI::Rails::Task`, persisting configuration
in the DB and forwarding it to the core `Task` at `to_rcrew_task` time, with the
same "only when set" backward-compat discipline as Group A.

## Key design decisions

### Guardrail persistence: class + method (mirrors existing callback pattern)

A `guardrail` is a callable and can't be stored in a DB row. The Task model
already solves this exact problem for `callback` via `callback_class` +
`callback_method_name` columns resolved to a lambda in `callback_method`. Group B
mirrors that: `guardrail_class` + `guardrail_method_name`, resolved to a callable
in a new `guardrail_callable` method. This keeps one convention in the model.

The resolved callable must return `[ok, value_or_error]` per the core contract —
that's the responsibility of the host app's guardrail class; the Rails layer just
resolves and forwards it.

### output_file: pass through as-is (core semantics)

Forward `output_file`/`create_directory`/`markdown` straight to the core Task,
which writes to the app-server filesystem exactly as the gem does. Documented
caveat: in a background job this writes on the worker host. Reuse the EXISTING
`output_file` column (already on `rcrewai_tasks`); do not add a duplicate.

### output_schema is the new canonical field

Add a new `output_schema` (JSON) column. Leave the legacy `output_json` /
`output_pydantic` columns untouched for backward-compat; they are not wired to
the new structured-output feature.

## Design

### Schema (new migration `003_add_output_processing_to_rcrewai_tasks.rb`)

```ruby
add_column :rcrewai_tasks, :output_schema,          :text     # JSON schema (serialized)
add_column :rcrewai_tasks, :guardrail_class,        :string
add_column :rcrewai_tasks, :guardrail_method_name,  :string
add_column :rcrewai_tasks, :guardrail_max_retries,  :integer, default: 3
add_column :rcrewai_tasks, :create_directory,       :boolean, default: true
add_column :rcrewai_tasks, :markdown,               :boolean, default: false
add_column :rcrewai_tasks, :attachments,            :text     # JSON array (serialized)
# output_file already exists — reused, not re-added.
```

Mirrored into `spec/internal/db/schema.rb` and the install-generator template,
identical names/types/defaults (Group A consistency requirement).

### Model (`app/models/rcrewai/rails/task.rb`)

Add serializers:

```ruby
serialize :output_schema, coder: JSON
serialize :attachments, coder: JSON, type: Array
```

Wire options:

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

# 0.4/0.5 task output-processing options. Emit a key only when meaningfully set.
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

private

# Resolves guardrail_class + guardrail_method_name to a callable, mirroring
# callback_method. Returns nil when not configured.
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

Backward-compat: `task_output_options` returns `{}` for an all-default record,
so `to_rcrew_task` is identical to today for existing tasks.

### Testing (TDD, mirrors Group A)

Spy on `RCrewAI::Task.new` and assert kwargs:

1. Regression guard — all-default task forwards none of the new keys.
2. `output_schema` present → forwarded as deep-symbolized hash.
3. `guardrail_class` + `guardrail_method_name` → `:guardrail` is a callable that,
   given an output, calls through to the host class (assert it returns the class's
   `[ok, value]`).
4. `guardrail_max_retries` forwarded only when a guardrail class is set.
5. `output_file` present → forwarded; `markdown`/`create_directory` forwarded per
   their flags.
6. `attachments` present → forwarded with symbolized keys and symbol `:type`.

## Out of scope (explicit)

- **Per-task result persistence.** Forwarding `output_schema` makes structured
  output *work* (coercion, guardrail retries, file output all happen in-core).
  Persisting each task's parsed `structured_output`/`raw_result` back to the DB
  is deferred: there is no task-result column today, and reaching per-task
  results out of the crew from the job layer needs its own design. Tracked as a
  follow-up.
- **Web UI controls** for the new fields.
- **Groups C (crew lifecycle) and D (Flows/RAG).**
- Legacy `output_json` / `output_pydantic` columns — left as-is.

## Risks

- **Guardrail contract is the host's responsibility.** If a host class's method
  doesn't return `[ok, value_or_error]`, the core gem will error at run time. The
  Rails layer only resolves/forwards. Acceptable — same trust model as the
  existing `callback` pattern.
- **`attachments` with `path:`** reads local files on the worker host at run
  time (core base64-encodes them). Same filesystem caveat as `output_file`.
