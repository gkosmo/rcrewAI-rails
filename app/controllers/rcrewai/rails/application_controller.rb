module RcrewAI
  module Rails
    class ApplicationController < ActionController::Base
      protect_from_forgery with: :exception
      
      before_action :check_web_ui_enabled

      private

      def check_web_ui_enabled
        unless RcrewAI::Rails.config.enable_web_ui
          render plain: "RcrewAI Web UI is disabled", status: :forbidden
        end
      end
    end
  end
end