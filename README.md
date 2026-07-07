# RcrewAI Rails

Rails engine for integrating [RcrewAI](https://github.com/gkosmo/rcrewai-rails) into your Rails applications. Provides ActiveRecord persistence, background job integration, generators, and a web UI for managing AI crews and agents.

## Features

- **ActiveRecord Integration**: Persist crews, agents, tasks, and executions in your database
- **Background Job Support**: Works with any ActiveJob adapter (Sidekiq, Resque, Delayed Job, etc.)
- **Rails Generators**: Quickly scaffold new crews and agents
- **Web UI**: Monitor and manage crews through a built-in interface
- **Rails-Specific Tools**: Pre-built tools for ActiveRecord, ActionMailer, Rails cache, and more
- **Configuration**: Flexible configuration through Rails initializers
- **Full rcrewai 0.7 feature coverage** (see [rcrewai 0.7 capabilities](#rcrewai-07-capabilities)):
  - Agent config: reasoning, per-agent LLM, rate limiting, context-window trimming, cognitive memory
  - Task output: structured output schemas, guardrails, file output, multimodal attachments
  - Crew: `before_kickoff`/`after_kickoff` hooks, planning, the `consensual` process, batch execution
  - Knowledge (RAG) sources and Flow persistence

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

## rcrewai 0.7 capabilities

This engine tracks [rcrewai](https://github.com/gkosmo/rcrewAI) `~> 0.7`. The
following capabilities are configured through columns on the persisted models and
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
