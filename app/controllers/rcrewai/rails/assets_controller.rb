module RcrewAI
  module Rails
    # Serves the dashboard's CSS and JavaScript from the gem, so the dashboard
    # works whatever asset pipeline the host has, or none.
    class AssetsController < ApplicationController
      # A <script> tag isn't an XHR, and this script holds nothing private.
      skip_forgery_protection

      def stylesheet
        serve Engine.root.join("app/assets/stylesheets/rcrewai/rails/dashboard.css"), "text/css"
      end

      def turbo
        serve Turbo::Engine.root.join("app/assets/javascripts/turbo.min.js"), "text/javascript"
      end

      private

      def serve(path, type)
        expires_in 1.year
        send_file path, type: type, disposition: "inline"
      end
    end
  end
end
