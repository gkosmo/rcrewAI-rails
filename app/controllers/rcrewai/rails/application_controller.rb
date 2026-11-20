module RcrewAI
  module Rails
    class ApplicationController < ActionController::Base
      protect_from_forgery with: :exception

      before_action :check_web_ui_enabled
      # Prepended, so nothing else runs for a request that isn't allowed in.
      prepend_before_action :authenticate_engine_request

      private

      def authenticate_engine_request
        hook = RcrewAI::Rails.config.authenticate_with
        return refuse_until_configured if hook.nil?

        allowed = hook.call(self)
        head :forbidden unless allowed || performed?
      end

      def refuse_until_configured
        return if ::Rails.env.development?

        render plain: "RcrewAI needs config.authenticate_with set in config/initializers/rcrewai.rb before it can serve requests.",
               status: :forbidden
      end

      def check_web_ui_enabled
        unless RcrewAI::Rails.config.enable_web_ui
          render plain: "RcrewAI Web UI is disabled", status: :forbidden
        end
      end
    end
  end
end