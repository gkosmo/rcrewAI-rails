require "rails/generators"

module RcrewAI
  module Rails
    module Generators
      class CrewGenerator < ::Rails::Generators::NamedBase
        source_root File.expand_path("templates", __dir__)

        argument :process_type, type: :string, default: "sequential", banner: "sequential|hierarchical"

        class_option :agents, type: :array, default: [], desc: "List of agents to create"
        class_option :description, type: :string, desc: "Crew description"

        def create_crew_file
          template "crew.rb.erb", "app/crews/#{file_name}_crew.rb"
        end

        def create_agent_files
          options[:agents].each do |agent_name|
            @agent_name = agent_name
            template "agent.rb.erb", "app/crews/agents/#{agent_name.underscore}_agent.rb"
          end
        end

        def display_next_steps
          say "\n✅ Created #{class_name}Crew!", :green
          say "\nNext steps:", :yellow
          say "  1. Configure your crew in app/crews/#{file_name}_crew.rb"
          say "  2. Define tasks for your crew"
          say "  3. Run your crew with: #{class_name}Crew.new.execute"
          say "\n"
        end

        private

        def crew_description
          options[:description] || "#{class_name} crew for AI task orchestration"
        end
      end
    end
  end
end