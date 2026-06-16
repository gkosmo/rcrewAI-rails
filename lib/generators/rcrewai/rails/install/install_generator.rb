require "rails/generators"

module RcrewAI
  module Rails
    module Generators
      class InstallGenerator < ::Rails::Generators::Base
        source_root File.expand_path("templates", __dir__)

        def create_initializer
          create_file "config/initializers/rcrewai.rb", <<~RUBY
            RcrewAI.configure do |config|
              # Configure your LLM settings
              # config.default_llm = :openai
              # config.openai_api_key = ENV['OPENAI_API_KEY']
              
              # Rails specific configuration
              config.job_queue_name = ENV.fetch("RCREWAI_QUEUE", "default")
              config.enable_web_ui = ENV.fetch("RCREWAI_WEB_UI", "true") == "true"
              config.async_execution = ENV.fetch("RCREWAI_ASYNC", "true") == "true"
            end
          RUBY
        end

        def display_post_install_message
          say "\n✅ RcrewAI Rails has been installed!", :green
          say "\nNext steps:", :yellow
          say "  1. Configure your settings in config/initializers/rcrewai.rb"
          say "  2. Set your LLM API keys in environment variables"
          say "  3. Start building AI crews with RcrewAI!"
          say "\n"
        end
      end
    end
  end
end