module RcrewAI
  module Rails
    class Configuration
      attr_accessor :job_queue_name, :enable_web_ui, :persistence_backend,
                    :default_llm_provider, :default_llm_model, :max_retries,
                    :timeout, :enable_logging, :log_level, :async_execution,
                    :default_memory_embedder, :default_memory_store,
                    :observation_enabled, :observation_capture_prompts,
                    :observation_prompt_max_bytes, :observation_flush_mode,
                    :observation_flush_every, :observation_retention_days,
                    :checkpoint_enabled, :checkpoint_store,
                    :llm_before_request, :llm_after_response

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
        # Checkpointing (rcrewai 0.8+). Off by default: it writes a row per
        # task settlement, which an app should opt into rather than inherit.
        @checkpoint_enabled = false
        # Defaults to ActiveRecordCheckpointStore when checkpointing is on.
        # Set to any object responding to save/load/list/delete to override.
        @checkpoint_store = nil
        # LLM interceptor hooks (rcrewai 0.8+). Each is a callable, or an
        # array of callables, applied to every client the engine builds.
        @llm_before_request = nil
        @llm_after_response = nil
      end
    end
  end
end