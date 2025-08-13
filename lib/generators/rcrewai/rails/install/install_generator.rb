require "rails/generators"
require "rails/generators/migration"

module RcrewAI
  module Rails
    module Generators
      class InstallGenerator < ::Rails::Generators::Base
        include ::Rails::Generators::Migration

        source_root File.expand_path("templates", __dir__)

        def self.next_migration_number(dirname)
          Time.now.utc.strftime("%Y%m%d%H%M%S")
        end

        def create_migration_file
          migration_template "create_rcrewai_tables.rb", "db/migrate/create_rcrewai_tables.rb"
        end

        def create_initializer
          template "rcrewai.rb", "config/initializers/rcrewai.rb"
        end

        def add_routes
          route "mount RcrewAI::Rails::Engine => '/rcrewai'"
        end

        def display_post_install_message
          say "\n✅ RcrewAI Rails has been installed!", :green
          say "\nNext steps:", :yellow
          say "  1. Run migrations: rails db:migrate"
          say "  2. Configure your settings in config/initializers/rcrewai.rb"
          say "  3. Set your LLM API keys in environment variables"
          say "  4. Visit /rcrewai for the web UI (if enabled)"
          say "\n"
        end
      end
    end
  end
end