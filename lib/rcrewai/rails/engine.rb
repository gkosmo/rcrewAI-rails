module RcrewAI
  module Rails
    class Engine < ::Rails::Engine
      isolate_namespace RcrewAI::Rails
      
      # Fix inflector for RcrewAI constant
      ActiveSupport::Inflector.inflections(:en) do |inflect|
        inflect.acronym 'AI'
        inflect.acronym 'RcrewAI'
      end
      
      config.autoload_paths += %W[
        #{config.root}/app
        #{config.root}/lib
      ]
      
      config.eager_load_paths += %W[
        #{config.root}/app
        #{config.root}/lib
      ]

      # Tell Zeitwerk to ignore generator files - they aren't meant to be autoloaded
      initializer "rcrewai_rails.zeitwerk" do |app|
        ::Rails.autoloaders.main.ignore("#{root}/lib/generators")
      end

      config.generators do |g|
        g.test_framework :rspec
        g.fixture_replacement :factory_bot
        g.factory_bot dir: 'spec/factories'
      end

      initializer "rcrewai_rails.assets" do |app|
        if app.config.respond_to?(:assets)
          app.config.assets.paths << root.join("app/assets/stylesheets")
          app.config.assets.paths << root.join("app/assets/javascripts")
        end
      end



      initializer "rcrewai_rails.configure" do |app|
        RcrewAI::Rails.configure do |config|
          config.job_queue_name = ENV.fetch("RCREWAI_QUEUE", "default")
          config.enable_web_ui = ENV.fetch("RCREWAI_WEB_UI", "true") == "true"
          config.async_execution = ENV.fetch("RCREWAI_ASYNC", "true") == "true"
        end
      end
    end
  end
end