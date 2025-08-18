# RcrewAI Rails

Rails engine for integrating [RcrewAI](https://github.com/gkosmo/rcrewai-rails) into your Rails applications. Provides ActiveRecord persistence, background job integration, generators, and a web UI for managing AI crews and agents.

## Features

- **ActiveRecord Integration**: Persist crews, agents, tasks, and executions in your database
- **Background Job Support**: Works with any ActiveJob adapter (Sidekiq, Resque, Delayed Job, etc.)
- **Rails Generators**: Quickly scaffold new crews and agents
- **Web UI**: Monitor and manage crews through a built-in interface
- **Rails-Specific Tools**: Pre-built tools for ActiveRecord, ActionMailer, Rails cache, and more
- **Configuration**: Flexible configuration through Rails initializers

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
$ rails generate rcrew_a_i:rails:install
$ rails db:migrate
```

This will:
- Create the necessary database migrations
- Add an initializer file for configuration
- Mount the engine routes

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
  process_type :sequential
  memory_enabled true
  
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

## Database Models

The gem provides these ActiveRecord models:

- `RcrewAI::Rails::Crew` - Crew configurations
- `RcrewAI::Rails::Agent` - Agent definitions
- `RcrewAI::Rails::Task` - Task definitions
- `RcrewAI::Rails::Execution` - Execution history
- `RcrewAI::Rails::ExecutionLog` - Detailed execution logs

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
