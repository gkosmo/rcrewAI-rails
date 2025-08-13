module RcrewAI
  module Rails
    module Tools
      class ActionMailerTool < RCrewAI::Tools::Base
        def initialize(mailer_class: nil, allowed_methods: [])
          @mailer_class = mailer_class
          @allowed_methods = allowed_methods
          super(
            name: "Action Mailer Tool",
            description: "Send emails using Rails Action Mailer"
          )
        end

        def execute(mailer_method, params = {}, deliver_method = :deliver_later)
          validate_mailer_method!(mailer_method)
          
          mailer = get_mailer_class(params.delete(:mailer) || @mailer_class)
          
          # Build the mail object
          mail = mailer.send(mailer_method, **params)
          
          # Deliver based on specified method
          case deliver_method.to_sym
          when :deliver_now
            mail.deliver_now
            { status: "sent", method: mailer_method, delivered_at: Time.current }
          when :deliver_later
            job = mail.deliver_later
            { status: "queued", method: mailer_method, job_id: job.job_id }
          when :deliver_later_at
            delivery_time = params.delete(:at) || 1.hour.from_now
            job = mail.deliver_later(wait_until: delivery_time)
            { status: "scheduled", method: mailer_method, job_id: job.job_id, scheduled_for: delivery_time }
          else
            { error: "Unknown delivery method: #{deliver_method}" }
          end
        rescue => e
          { error: "Failed to send email", message: e.message }
        end

        private

        def validate_mailer_method!(method)
          if @allowed_methods.any? && !@allowed_methods.include?(method.to_sym)
            raise ArgumentError, "Mailer method '#{method}' is not allowed"
          end
        end

        def get_mailer_class(mailer_name)
          return @mailer_class if @mailer_class && mailer_name.nil?
          
          mailer_name = "#{mailer_name.to_s.camelize}Mailer" unless mailer_name.to_s.end_with?("Mailer")
          mailer_name.constantize
        rescue NameError
          raise ArgumentError, "Mailer class '#{mailer_name}' not found"
        end
      end
    end
  end
end