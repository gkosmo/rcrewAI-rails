module RcrewAI
  module Rails
    module Tools
      class ActionMailerTool < RCrewAI::Tools::Base
        tool_name "action_mailer_send"
        description "Send emails using a Rails Action Mailer. Choose the mailer class, the mailer method, and the delivery strategy."

        param :mailer_method, type: :string, required: true,
              description: "Name of the mailer method to invoke (e.g. 'welcome_email')."
        param :mailer, type: :string, required: false,
              description: "Mailer class name with or without the 'Mailer' suffix (e.g. 'User' or 'UserMailer'). Defaults to the mailer configured on the tool."
        param :params, type: :object, required: false,
              description: "Keyword arguments to pass to the mailer method."
        param :deliver_method, type: :enum, required: false,
              values: %w[deliver_now deliver_later deliver_later_at],
              description: "How to send: deliver_now, deliver_later, or deliver_later_at."
        param :at, type: :string, required: false,
              description: "ISO8601 timestamp for deliver_later_at. Required when deliver_method is deliver_later_at."

        def initialize(mailer_class: nil, allowed_methods: [])
          super()
          @mailer_class = mailer_class
          @allowed_methods = allowed_methods.map(&:to_sym)
        end

        def execute(mailer_method:, mailer: nil, params: {}, deliver_method: "deliver_later", at: nil)
          method_sym = mailer_method.to_sym
          validate_mailer_method!(method_sym)

          mailer_klass = resolve_mailer_class(mailer)
          mailer_params = (params || {}).transform_keys(&:to_sym)
          mail = mailer_klass.public_send(method_sym, **mailer_params)

          case deliver_method.to_sym
          when :deliver_now
            mail.deliver_now
            { status: "sent", method: method_sym, delivered_at: Time.current }
          when :deliver_later
            job = mail.deliver_later
            { status: "queued", method: method_sym, job_id: job.job_id }
          when :deliver_later_at
            delivery_time = at.present? ? Time.iso8601(at) : 1.hour.from_now
            job = mail.deliver_later(wait_until: delivery_time)
            { status: "scheduled", method: method_sym, job_id: job.job_id, scheduled_for: delivery_time }
          else
            { error: "Unknown delivery method: #{deliver_method}" }
          end
        rescue => e
          { error: "Failed to send email", message: e.message }
        end

        private

        def validate_mailer_method!(method)
          return if @allowed_methods.empty? || @allowed_methods.include?(method)

          raise ArgumentError, "Mailer method '#{method}' is not allowed"
        end

        def resolve_mailer_class(mailer_name)
          return @mailer_class if mailer_name.nil? && @mailer_class
          raise ArgumentError, "No mailer specified" if mailer_name.nil?

          mailer_name = mailer_name.to_s
          mailer_name = "#{mailer_name.camelize}Mailer" unless mailer_name.end_with?("Mailer")
          mailer_name.constantize
        rescue NameError
          raise ArgumentError, "Mailer class '#{mailer_name}' not found"
        end
      end
    end
  end
end
