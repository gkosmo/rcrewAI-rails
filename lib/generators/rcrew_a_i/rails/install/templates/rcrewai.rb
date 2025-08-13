RcrewAI::Rails.configure do |config|
  # ActiveJob queue name for background processing
  # Default: "default"
  config.job_queue_name = ENV.fetch("RCREWAI_QUEUE", "default")

  # Enable web UI for monitoring crews
  # Default: true
  config.enable_web_ui = ENV.fetch("RCREWAI_WEB_UI", "true") == "true"

  # Use ActiveJob for async execution
  # Default: true
  config.async_execution = ENV.fetch("RCREWAI_ASYNC", "true") == "true"

  # Persistence backend (currently only :active_record supported)
  # Default: :active_record
  config.persistence_backend = :active_record

  # Default LLM provider
  # Options: "openai", "anthropic", "cohere", "groq", etc.
  config.default_llm_provider = ENV.fetch("RCREWAI_LLM_PROVIDER", "openai")

  # Default LLM model
  config.default_llm_model = ENV.fetch("RCREWAI_LLM_MODEL", "gpt-4")

  # Maximum retries for failed tasks
  # Default: 3
  config.max_retries = 3

  # Timeout for crew execution (in seconds)
  # Default: 300 (5 minutes)
  config.timeout = 300

  # Enable logging
  # Default: true
  config.enable_logging = true

  # Log level
  # Options: :debug, :info, :warn, :error
  # Default: :info
  config.log_level = :info
end

# Configure RcrewAI base gem if needed
RcrewAI.configure do |config|
  # Set your API keys here or in environment variables
  # config.openai_api_key = ENV["OPENAI_API_KEY"]
  # config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
  # config.groq_api_key = ENV["GROQ_API_KEY"]
  
  # Configure other RcrewAI settings
  # config.default_model = "gpt-4"
  # config.temperature = 0.7
end