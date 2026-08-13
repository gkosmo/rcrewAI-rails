require "rails/generators"
require "rails/generators/migration"
require "rails/generators/active_record"

module RcrewAI
  module Rails
    module Generators
      class InstallGenerator < ::Rails::Generators::Base
        include ::Rails::Generators::Migration

        source_root File.expand_path("templates", __dir__)

        MOUNT_PATH = "/rcrewai".freeze

        # Required by Rails::Generators::Migration so the copied migration gets
        # a real timestamped filename instead of colliding on every install.
        def self.next_migration_number(dirname)
          ::ActiveRecord::Generators::Base.next_migration_number(dirname)
        end

        def create_initializer
          template "rcrewai.rb", "config/initializers/rcrewai.rb"
        end

        def create_migration_file
          migration_template "create_rcrewai_tables.rb",
                             "db/migrate/create_rcrewai_tables.rb"
        end

        def mount_engine
          route "mount RcrewAI::Rails::Engine => '#{MOUNT_PATH}'"
        end

        def display_post_install_message
          say "\n✅ RcrewAI Rails has been installed!", :green
          say "\nNext steps:", :yellow
          say "  1. Run `rails db:migrate` to create the RcrewAI tables"
          say "  2. Configure your settings in config/initializers/rcrewai.rb"
          say "  3. Set your LLM API keys in environment variables"
          say "  4. Visit #{MOUNT_PATH} to monitor your crews"
          say "  5. Start building AI crews with RcrewAI!"
          say "\n"
        end
      end
    end
  end
end
