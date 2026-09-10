# RcrewAI Rails

Rails engine for integrating [RcrewAI](https://github.com/gkosmo/rcrewai-rails) into your Rails applications. Provides ActiveRecord persistence, background job integration, generators, and a web UI for managing AI crews and agents.

## Features

- **ActiveRecord Integration**: Persist crews, agents, tasks, and executions in your database
- **Background Job Support**: Works with any ActiveJob adapter (Sidekiq, Resque, Delayed Job, etc.)
- **Rails Generators**: Quickly scaffold new crews and agents
- **Web UI**: Monitor and manage crews through a built-in interface
- **Rails-Specific Tools**: Pre-built tools for ActiveRecord, ActionMailer, Rails cache, and more
- **Configuration**: Flexible configuration through Rails initializers
- **Full rcrewai 0.8 feature coverage** (see [rcrewai 0.8 capabilities](#rcrewai-08-capabilities) and [rcrewai 0.7 capabilities](#rcrewai-07-capabilities)):
  - Agent config: reasoning, per-agent LLM, rate limiting, context-window trimming, cognitive memory
  - Task output: structured output schemas, guardrails, file output, multimodal attachments
  - Crew: `before_kickoff`/`after_kickoff` hooks, planning, the `consensual` process, batch execution
  - Knowledge (RAG) sources and Flow persistence
  - Checkpointing with resume, LLM interceptors, and the Bedrock / Snowflake / OpenAI-compatible providers

## Observation Engine

Every crew execution is traced as a tree of spans — crew, agent, task, LLM call, and
tool call — carrying timings, token counts, and cost.

- **Trace view** at `/rcrewai/executions/:id/observation`: a waterfall of the run, with
  prompts, tool arguments, and errors on each span.
- **Cost and performance** at `/rcrewai/observations/costs`: spend and token totals
  across recent executions.
- **Live monitoring**: the trace view updates over Turbo Streams while a run is in progress.

Configure it in `config/initializers/rcrewai.rb`:

```ruby
config.observation_enabled = true
config.observation_capture_prompts = :truncated  # :none | :truncated | :full
config.observation_prompt_max_bytes = 4_096
config.observation_flush_mode = :batched         # :batched | :immediate
config.observation_retention_days = 30
```

Prompt text is truncated by default: full prompts can be large and may contain personal
data. Set `:full` only when you need lossless replay.

Prune old spans with the bundled rake task:

```bash
rake rcrewai:observation:prune        # uses observation_retention_days
rake rcrewai:observation:prune DAYS=7
```

### Limitations

Token and cost data depend on rcrewai's **streaming** execution path. `Usage` events are
only emitted when an agent runs via `ToolRunner`, which passes a `stream:` to the LLM
client — not via `LegacyReactRunner`, which does not. `ToolRunner` is selected when the
tools have JSON schemas **and** the LLM client reports `supports_native_tools?`. OpenAI,
Anthropic, and Google all report true, so cost capture works normally with them. With a
provider or configuration that falls back to `LegacyReactRunner` (for example Ollama
without native tools), **the cost dashboard will be empty rather than showing an error**.

Agent-level tracing requires **rcrewai >= 0.7.1**, the version that threads the event
stream down to agent execution. On earlier versions traces contain only crew-level spans.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'rcrewai-rails'
```

And then execute:

```bash
$ bundle install
```

Run the installation generator:

```bash
$ rails generate rcrewai:rails:install
$ rails db:migrate
```

This will:
- Create the necessary database migrations
- Add an initializer file for configuration
- Mount the engine routes in `config/routes.rb`

### Upgrading an existing install

The install generator above is for **new** installs — it creates every table, so
running it against an app that already has the RcrewAI tables will fail on
duplicates.

If you are already running rcrewai-rails, pull in only the migrations you are
missing using the standard Rails engine task:

```bash
$ rails rcrew_ai_rails:install:migrations
$ rails db:migrate
```

(The task name comes from the engine's railtie name, `rcrew_ai_rails`.)

Rails copies only the migrations your app does not already have. Upgrading to
0.8.0 from 0.7.x adds one:

| Migration | Purpose |
|---|---|
| `012_create_rcrewai_checkpoints` | `rcrewai_checkpoints`, `rcrewai_crews.checkpoint_enabled`, and `run_id`/`parent_run_id` on executions — checkpointing and resume |

Upgrading from 0.6.x adds two more:

| Migration | Purpose |
|---|---|
| `010_create_rcrewai_spans` | `rcrewai_spans` and `rcrewai_span_events` — the observation engine's trace tree |
| `011_add_observation_rollups_to_rcrewai_executions` | `total_cost_usd`, `total_tokens`, `span_count`, `error_count` on executions |

All are additive: no existing column or table is changed, and nothing is
dropped. Existing crews, agents, tasks, and executions are unaffected, and
observation is enabled by default once the tables exist. To upgrade the gem
without turning tracing on, set `config.observation_enabled = false` in
`config/initializers/rcrewai.rb` before migrating.

If your schema was created by hand (the install generator did not copy a
migration before 0.7.0, so this is likely), review the copied migrations before
running `db:migrate` and delete any whose tables you already have.

### Manual Routes Setup

If you need to mount the routes manually, add this to your `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  mount RcrewAI::Rails::Engine => '/rcrewai'
  # Your other routes...
end
```

This makes the web UI available at `/rcrewai` and API endpoints at `/rcrewai/api/v1/`.

## Configuration

Configure RcrewAI Rails in `config/initializers/rcrewai.rb`:

```ruby
RcrewAI::Rails.configure do |config|
  # ActiveJob queue for background processing
  config.job_queue_name = "default"
  
  # Enable/disable web UI
  config.enable_web_ui = true
  
  # Use async execution by default
  config.async_execution = true
  
  # Default LLM settings
  config.default_llm_provider = "openai"
  config.default_llm_model = "gpt-4"
  
  # Logging
  config.enable_logging = true
  config.log_level = :info
end

# Configure the base RcrewAI gem
RcrewAI.configure do |config|
  config.openai_api_key = ENV["OPENAI_API_KEY"]
  # Add other LLM provider keys as needed
end
```

## Usage

### Creating a Crew with Generators

Generate a new crew with agents:

```bash
$ rails generate rcrewai:rails:crew research_team sequential \
    --agents researcher analyst writer \
    --description "Research team for market analysis"
```

This creates a crew class in `app/crews/research_team_crew.rb`.

### Creating a Crew Programmatically

```ruby
class ResearchCrew
  include RcrewAI::Rails::CrewBuilder
  
  crew_name "research_team"
  crew_description "AI-powered research team"
  process_type :sequential # :sequential, :hierarchical, or :consensual
  
  def setup_agents
    @researcher = create_agent("researcher",
      role: "Senior Research Analyst",
      goal: "Uncover insights and trends",
      backstory: "Expert researcher with years of experience"
    )
    
    @writer = create_agent("writer", 
      role: "Content Writer",
      goal: "Create compelling reports",
      backstory: "Skilled writer specializing in technical content"
    )
  end
  
  def setup_tasks
    @research_task = create_task("Research latest AI trends",
      expected_output: "Comprehensive research report",
      position: 1
    )
    assign_agent_to_task(@researcher, @research_task)
    
    @writing_task = create_task("Write executive summary",
      expected_output: "2-page executive summary",
      position: 2  
    )
    assign_agent_to_task(@writer, @writing_task)
    add_task_dependency(@writing_task, @research_task)
  end
end

# Execute the crew
crew = ResearchCrew.new
execution = crew.execute(topic: "AI in Healthcare")
```

### Using Rails-Specific Tools

```ruby
class DataAnalystAgent
  include RcrewAI::Rails::AgentBuilder
  
  agent_role "Data Analyst"
  agent_goal "Analyze application data"
  
  tools [
    RcrewAI::Rails::Tools::ActiveRecordTool.new(
      model_class: User,
      allowed_methods: [:count, :where, :pluck]
    ),
    RcrewAI::Rails::Tools::RailsCacheTool.new,
    RcrewAI::Rails::Tools::ActionMailerTool.new(
      mailer_class: ReportMailer,
      allowed_methods: [:send_report]
    )
  ]
end
```

### Monitoring Executions

Access the web UI at `/rcrewai` to:
- View all crews and their configurations
- Monitor execution status and logs
- Start new executions
- View execution history and results

### Using with ActiveJob

Executions run through ActiveJob by default, using whatever adapter your Rails app is configured with:

```ruby
# Async execution (default)
crew.execute_async(inputs)

# Sync execution
crew.execute_sync(inputs)

# Custom job options
CrewExecutionJob.set(wait: 5.minutes).perform_later(crew, inputs)
```

## rcrewai 0.8 capabilities

This engine tracks [rcrewai](https://github.com/gkosmo/rcrewAI) `~> 0.8`.

### Checkpointing and resume

A crew run can record durable per-task state, so an interrupted run resumes
instead of re-executing (and re-paying for) the tasks that already finished.
Checkpoints are written to `rcrewai_checkpoints` after each task settles.

```ruby
# Globally, in config/initializers/rcrewai.rb
config.checkpoint_enabled = true

# ...or per crew
crew.update!(checkpoint_enabled: true)

execution = crew.executions.order(:id).last
execution.run_id          # => the checkpointed run

# Resume it: completed tasks are replayed, the rest execute.
crew.resume_sync(execution)     # or resume_async(execution)
crew.resumable_executions       # executions that recorded a run id
```

A resumed run gets its own `run_id` and records the original in
`parent_run_id`, leaving the first run's record intact:

```ruby
store = RcrewAI::Rails::ActiveRecordCheckpointStore.new
RCrewAI::Checkpoint.lineage(store, resumed.run_id)
# => ["<original run id>", "<resumed run id>"]
```

Any object responding to `save`/`load`/`list`/`delete` can replace the store via
`config.checkpoint_store`.

### LLM interceptors

Hooks that run around every LLM request the engine's agents make — useful for
logging, request tagging, or signing (AWS SigV4 for Bedrock, for instance).
Return a replacement value to modify the payload or result, or `nil` to leave it
untouched. A hook that raises is reported and skipped, so instrumentation can
never break a run.

```ruby
config.llm_before_request = lambda do |payload, context|
  Rails.logger.info("[llm] -> #{context[:provider]}/#{context[:model]}")
  payload
end

config.llm_after_response = lambda do |result, context|
  Rails.logger.info("[llm] <- #{context[:duration_ms]}ms")
  result
end
```

### Providers

Alongside `openai`, `anthropic`, `google`, `azure` and `ollama`, rcrewai 0.8
adds four, set as an agent's `llm_config` provider (or
`config.default_llm_provider`):

| Provider | Notes |
|---|---|
| `openai_compatible` | Any OpenAI-format endpoint (Groq, Together, Fireworks, vLLM, OpenRouter, a self-hosted gateway). Requires RCrewAI's `base_url`. |
| `bedrock` | AWS Bedrock via the Converse API. Requires `aws_region`. |
| `snowflake` | Snowflake Cortex inference. Requires `snowflake_account`. |
| `openai_responses` | OpenAI's Responses API. Non-streaming only. |

### Tracing accuracy

rcrewai 0.8 stamps every event with the id of its enclosing run span, and the
observation collector uses it to keep concurrent runs of the *same* agent apart.
Previously both runs shared one span stack, so one run's tool call could nest
under the other's iteration.

## rcrewai 0.7 capabilities

These capabilities are configured through columns on the persisted models and
forwarded to the core objects at build time. All are **off/absent by default**, so
existing records are unaffected — set only what you need.

### Agent configuration (`RcrewAI::Rails::Agent`)

| Column | Effect |
|---|---|
| `max_rpm` | Rate-limit the agent's LLM calls (requests per minute) |
| `reasoning` / `max_reasoning_attempts` | Run a planning/reasoning pass before answering |
| `respect_context_window` | Trim history to fit the model's context window |
| `llm_config` (JSON) | Per-agent LLM override, e.g. `{ "provider": "anthropic", "model": "claude-sonnet-5" }` |
| `memory_enabled` + `memory_scope` + `memory_short_term_limit` | Enable cognitive memory (see below) |

```ruby
agent = crew.agents.create!(
  name: "researcher", role: "Researcher", goal: "Find facts",
  reasoning: true,
  max_rpm: 30,
  llm_config: { provider: "anthropic", model: "claude-sonnet-5" },
  memory_enabled: true, memory_scope: "research", memory_short_term_limit: 20
)
```

**Agent memory** (rcrewai 0.6+): set `memory_enabled: true` to turn on cognitive
memory. `memory_scope` isolates an agent's memories; `memory_short_term_limit`
caps recent-execution recall. The embedder and store are objects, so configure
them once in the initializer:

```ruby
RcrewAI::Rails.configure do |config|
  config.default_memory_embedder = RCrewAI::Knowledge::Embedder.new
  config.default_memory_store     = RCrewAI::Memory::SqliteStore.new(path: "db/rcrewai_memory.sqlite3")
end
```

### Task output processing (`RcrewAI::Rails::Task`)

| Column | Effect |
|---|---|
| `output_schema` (JSON) | Validate/coerce the result against a JSON schema (structured output) |
| `guardrail_class` + `guardrail_method_name` + `guardrail_max_retries` | Validate/transform output, retrying on failure |
| `output_file` + `create_directory` + `markdown` | Write the result to disk |
| `attachments` (JSON) | Multimodal image inputs, e.g. `[{ "type": "image", "url": "https://…" }]` |

A guardrail is resolved from a host class: `guardrail_class` names a class whose
`guardrail_method_name` accepts the output and returns `[ok, value_or_error]`.

### Crew orchestration (`RcrewAI::Rails::Crew`)

| Column | Effect |
|---|---|
| `process_type` | `"sequential"`, `"hierarchical"`, or `"consensual"` |
| `consensus_agents` | Number of proposers for the `consensual` process (default 3) |
| `planning` / `planning_llm` | Run a planner pass before execution |
| `before_kickoff_class`/`_method`, `after_kickoff_class`/`_method` | Lifecycle hooks resolved from host classes |

**Batch execution** (rcrewai `kickoff_for_each` parity) runs the crew once per
input set, one `Execution` per input grouped by a shared `batch_id`:

```ruby
result = crew.execute_batch_sync([{ topic: "a" }, { topic: "b" }])
crew.batch_executions(result[:batch_id]) # the runs, in order
crew.execute_batch_async(inputs_list)     # enqueue N jobs, returns the batch_id
```

### Knowledge (RAG)

Attach sources to an agent (role-specific) or a crew (shared with all its agents):

```ruby
agent.knowledge_sources.create!(source_type: "url",    value: "https://example.com/doc")
crew.knowledge_sources.create!(source_type: "string", value: "Reference text…")
# source_type: "string" | "file" | "pdf" | "csv" | "url"
```

Active sources are embedded lazily at execution. See the memory initializer above
for embedder configuration.

### Flows

Define Flow subclasses in your app (Ruby); the engine persists their state and
runs. Pass `RcrewAI::Rails::ActiveRecordStateStore` so flows resume from the DB,
and use `FlowRun.execute` to track a kickoff:

```ruby
run = RcrewAI::Rails::FlowRun.execute(MyFlow, inputs: { topic: "ruby" })
run.status     # "completed" / "failed"
run.result     # the final flow state
RcrewAI::Rails::FlowState.find_by(state_id: run.state_id) # the persisted state
```

## Database Models

The gem provides these ActiveRecord models:

- `RcrewAI::Rails::Crew` - Crew configurations
- `RcrewAI::Rails::Agent` - Agent definitions
- `RcrewAI::Rails::Task` - Task definitions
- `RcrewAI::Rails::Execution` - Execution history
- `RcrewAI::Rails::ExecutionLog` - Detailed execution logs
- `RcrewAI::Rails::KnowledgeSource` - Knowledge (RAG) sources, owned by an agent or a crew
- `RcrewAI::Rails::FlowState` - Persisted rcrewai Flow state (resume flows across restarts)
- `RcrewAI::Rails::FlowRun` - Flow-run tracking (status, inputs, result, timing)
- `RcrewAI::Rails::Span` / `SpanEvent` - The observation engine's trace tree
- `RcrewAI::Rails::Checkpoint` - Persisted crew checkpoints (resume and lineage)

## API Endpoints

The engine provides JSON API endpoints:

```
GET    /rcrewai/api/v1/crews
GET    /rcrewai/api/v1/crews/:id
POST   /rcrewai/api/v1/crews/:id/execute
GET    /rcrewai/api/v1/executions
GET    /rcrewai/api/v1/executions/:id
GET    /rcrewai/api/v1/executions/:id/status
GET    /rcrewai/api/v1/executions/:id/logs
```

## Development

After checking out the repo, run:

```bash
$ bundle install
$ bundle exec rspec
```

To install this gem onto your local machine:

```bash
$ bundle exec rake install
```

## Contributing

Bug reports and pull requests are welcome on GitHub.

## License

The gem is available as open source under the terms of the MIT License.
