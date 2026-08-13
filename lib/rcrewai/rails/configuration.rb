module RcrewAI
  module Rails
    class Configuration
      attr_accessor :job_queue_name, :enable_web_ui, :persistence_backend,
                    :default_llm_provider, :default_llm_model, :max_retries,
                    :timeout, :enable_logging, :log_level, :async_execution,
                    :default_memory_embedder, :default_memory_store,
                    :observation_enabled, :observation_capture_prompts,
                    :observation_prompt_max_bytes, :observation_flush_mode,
                    :observation_flush_every, :observation_retention_days

      def initialize
        @job_queue_name = "default"
        @enable_web_ui = true
        @persistence_backend = :active_record
        @default_llm_provider = "openai"
        @default_llm_model = "gpt-4"
        @max_retries = 3
        @timeout = 300 # 5 minutes
        @enable_logging = true
        @log_level = :info
        @async_execution = true # Use ActiveJob for async by default
        @default_memory_embedder = nil
        @default_memory_store = nil
        @observation_enabled = true
        @observation_capture_prompts = :truncated # :none | :truncated | :full
        @observation_prompt_max_bytes = 4_096
        @observation_flush_mode = :batched # :batched | :immediate
        @observation_flush_every = 25
        @observation_retention_days = 30
      end
    end
  end
end