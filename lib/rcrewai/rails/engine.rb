module RcrewAI
  module Rails
    class Engine < ::Rails::Engine
      isolate_namespace RcrewAI::Rails

      config.generators do |g|
        g.test_framework :rspec
        g.fixture_replacement :factory_bot
        g.factory_bot dir: 'spec/factories'
      end

      initializer "rcrewai_rails.assets" do |app|
        app.config.assets.paths << root.join("app/assets/stylesheets")
        app.config.assets.paths << root.join("app/assets/javascripts")
      end

      initializer "rcrewai_rails.load_models" do
        ActiveSupport.on_load(:active_record) do
          Dir[Engine.root.join("app/models/rcrewai/rails/*.rb")].each { |f| require f }
        end
      end

      initializer "rcrewai_rails.load_jobs" do
        ActiveSupport.on_load(:active_job) do
          Dir[Engine.root.join("app/jobs/rcrewai/rails/*.rb")].each { |f| require f }
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