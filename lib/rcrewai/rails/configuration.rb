module RcrewAI
  module Rails
    class Configuration
      attr_accessor :job_queue_name, :enable_web_ui, :persistence_backend,
                    :default_llm_provider, :default_llm_model, :max_retries,
                    :timeout, :enable_logging, :log_level, :async_execution

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
      end
    end
  end
end