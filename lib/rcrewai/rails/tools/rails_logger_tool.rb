module RcrewAI
  module Rails
    module Tools
      class RailsLoggerTool < RCrewAI::Tools::Base
        def initialize(tag: "RcrewAI")
          @tag = tag
          super(
            name: "Rails Logger Tool",
            description: "Log messages to Rails logger"
          )
        end

        def execute(level, message, metadata = {})
          logger = ::Rails.logger
          
          # Format the message with metadata
          formatted_message = format_message(message, metadata)
          
          case level.to_sym
          when :debug
            logger.debug(formatted_message)
          when :info
            logger.info(formatted_message)
          when :warn
            logger.warn(formatted_message)
          when :error
            logger.error(formatted_message)
          when :fatal
            logger.fatal(formatted_message)
          else
            return { error: "Unknown log level: #{level}" }
          end

          # Also instrument for monitoring
          ActiveSupport::Notifications.instrument("log.rcrewai", {
            level: level,
            message: message,
            metadata: metadata,
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