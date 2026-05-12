module RcrewAI
  module Rails
    module Tools
      class RailsLoggerTool < RCrewAI::Tools::Base
        tool_name "rails_logger"
        description "Log a message to the Rails logger at the given level and emit an ActiveSupport notification."

        param :level, type: :enum, required: true,
              values: %w[debug info warn error fatal],
              description: "Log level."
        param :message, type: :string, required: true,
              description: "Message to log."
        param :metadata, type: :object, required: false,
              description: "Additional metadata appended as JSON to the log line."

        def initialize(tag: "RcrewAI")
          super()
          @tag = tag
        end

        def execute(level:, message:, metadata: {})
          logger = ::Rails.logger
          meta = metadata || {}
          formatted_message = format_message(message, meta)

          case level.to_sym
          when :debug then logger.debug(formatted_message)
          when :info  then logger.info(formatted_message)
          when :warn  then logger.warn(formatted_message)
          when :error then logger.error(formatted_message)
          when :fatal then logger.fatal(formatted_message)
          else
            return { error: "Unknown log level: #{level}" }
          end

          ActiveSupport::Notifications.instrument("log.rcrewai", {
            level: level,
            message: message,
            metadata: meta,
            tag: @tag
          })

          { logged: true, level: level, message: message }
        rescue => e
          { error: "Logging failed", message: e.message }
        end

        private

        def format_message(message, metadata)
          return "[#{@tag}] #{message}" if metadata.empty?

          "[#{@tag}] #{message} | #{metadata.to_json}"
        end
      end
    end
  end
end
