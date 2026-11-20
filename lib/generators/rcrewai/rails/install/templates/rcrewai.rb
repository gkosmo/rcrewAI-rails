RcrewAI::Rails.configure do |config|
  # Who can use the dashboard and JSON API. Required: until this is set, every
  # request gets a 403, except in development. It runs before every engine
  # controller with the controller. Truthy lets the request through; anything
  # else is a 403, unless it already responded (a redirect to sign in, say).
  #
  # With Devise:
  #   config.authenticate_with = ->(controller) { controller.authenticate_user! }
  # Admins only, and everyone else sees a 404:
  #   config.authenticate_with = lambda do |controller|
  #     controller.current_user&.admin? || controller.head(:not_found)
  #   end

  # Tool classes that can be configured from the dashboard or stored on a record.
  # Nothing is allowed until you list it. Only list what you'd let anyone who
  # can reach the dashboard use.
  # config.allowed_tool_classes = ["RCrewAI::Tools::WebSearch"]

  # Tools from MCP servers for an engine agent, as a list of tools or connected
  # RCrewAI::MCP::Client instances. You own the connections.
  # DOCS_MCP = RCrewAI::MCP::Client.connect(url: "https://example.com/mcp")
  # config.agent_mcp_tools = ->(agent) { agent.name == "researcher" ? [DOCS_MCP] : [] }

  # A failed run isn't repeated by default, because it may have side effects.
  # Set attempts above 1 to retry. With checkpointing on, a retry resumes and
  # skips finished tasks. Without it, the whole run repeats, tools included.
  # config.crew_job_attempts = 1
  # config.crew_job_retry_wait = 30 # seconds, doubling each attempt
  # How many times the core gem re-runs a failed task, tools included.
  # config.task_max_retries = 0

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
  # Options: "openai", "anthropic", "google", "azure", "ollama", and (rcrewai
  # 0.8+) "openai_compatible", "bedrock", "snowflake", "openai_responses".
  #   openai_compatible - any OpenAI-format endpoint (Groq, Together,
  #                       Fireworks, vLLM, OpenRouter); needs RCrewAI's
  #                       base_url set.
  #   bedrock           - AWS Bedrock Converse API; needs aws_region.
  #   snowflake         - Snowflake Cortex; needs snowflake_account.
  config.default_llm_provider = ENV.fetch("RCREWAI_LLM_PROVIDER", "openai")

  # Default LLM model
  config.default_llm_model = ENV.fetch("RCREWAI_LLM_MODEL", "gpt-4o")

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

  # Observation engine: span-level tracing of crew executions.
  # config.observation_enabled = true
  #
  # Prompt capture: :none, :truncated (default), or :full.
  # :full stores complete prompts and completions — these can be large
  # and may contain PII.
  # config.observation_capture_prompts = :truncated
  # config.observation_prompt_max_bytes = 4_096
  #
  # :batched buffers span writes off the critical path; :immediate writes
  # each span as it opens and closes (better for live monitoring).
  # config.observation_flush_mode = :batched
  # config.observation_flush_every = 25
  #
  # Spans older than this are removed by `rake rcrewai:observation:prune`.
  # config.observation_retention_days = 30
end

# Configure the base rcrewai gem if needed. Note the capital C: RCrewAI holds
# provider settings, while RcrewAI.configure below is this engine's configuration.
# validate: false stops a missing key from failing boot in places that don't call
# an LLM, such as assets:precompile.
RCrewAI.configure(validate: false) do |config|
  # Keys are read from the environment (OPENAI_API_KEY, ANTHROPIC_API_KEY, ...)
  # automatically, so set them here only if they come from somewhere else.
  # config.openai_api_key = Rails.application.credentials.openai_api_key
  # config.anthropic_api_key = Rails.application.credentials.anthropic_api_key

  # config.openai_model = "gpt-4o"
  # config.anthropic_model = "claude-opus-5-5"

  # Current Claude models reject temperature, so leave it unset to use them.
  # config.temperature = nil
end

# More engine settings. RcrewAI.configure is the same as RcrewAI::Rails.configure.
RcrewAI.configure do |config|
  # --- Checkpointing (rcrewai 0.8+) -----------------------------------------
  # Records durable per-task state during a crew run so an interrupted run can
  # be resumed instead of re-executing (and re-paying for) completed tasks.
  # Off by default; a crew record can also opt in individually via its
  # checkpoint_enabled column.
  # config.checkpoint_enabled = true

  # Where checkpoints are stored. Defaults to the bundled ActiveRecord store
  # (the rcrewai_checkpoints table). Any object responding to
  # save/load/list/delete works.
  # config.checkpoint_store = RcrewAI::Rails::ActiveRecordCheckpointStore.new

  # --- LLM interceptors (rcrewai 0.8+) --------------------------------------
  # Hooks run around every LLM request the engine's agents make. Each receives
  # (payload, context) / (result, context); return a replacement to modify it,
  # or nil to leave it untouched. A hook that raises is reported and skipped,
  # so instrumentation can never break a run.
  #
  # config.llm_before_request = lambda do |payload, context|
  #   Rails.logger.info("[llm] -> #{context[:provider]}/#{context[:model]}")
  #   payload
  # end
  #
  # config.llm_after_response = lambda do |result, context|
  #   Rails.logger.info("[llm] <- #{context[:duration_ms]}ms")
  #   result
  # end
end
