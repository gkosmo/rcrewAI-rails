module RcrewAI
  module Rails
    module CrewBuilder
      extend ActiveSupport::Concern

      included do
        attr_reader :crew
      end

      class_methods do
        def crew_name(name = nil)
          if name
            @crew_name = name
          else
            @crew_name || self.name.underscore.gsub(/_crew$/, '')
          end
        end

        def crew_description(description = nil)
          @crew_description = description if description
          @crew_description
        end

        def process_type(type = nil)
          @process_type = type if type
          @process_type || :sequential
        end

        def memory_enabled(enabled = nil)
          @memory_enabled = enabled unless enabled.nil?
          @memory_enabled || false
        end

        def cache_enabled(enabled = nil)
          @cache_enabled = enabled unless enabled.nil?
          @cache_enabled || true
        end
      end

      def initialize
        @crew = find_or_create_crew
        setup_agents
        setup_tasks
        setup_callbacks
      end

      def execute(inputs = {})
        if RcrewAI::Rails.config.async_execution
          @crew.execute_async(inputs)
        else
          @crew.execute_sync(inputs)
        end
      end

      def execute_async(inputs = {})
        @crew.execute_async(inputs)
      end

      def execute_sync(inputs = {})
        @crew.execute_sync(inputs)
      end

      protected

      def find_or_create_crew
        RcrewAI::Rails::Crew.find_or_create_by(name: self.class.crew_name) do |crew|
          crew.description = self.class.crew_description
          crew.process_type = self.class.process_type.to_s
          crew.memory_enabled = self.class.memory_enabled
          crew.cache_enabled = self.class.cache_enabled
          crew.verbose = verbose?
        end
      end

      def setup_agents
        # Override in subclass
      end

      def setup_tasks
        # Override in subclass
      end

      def setup_callbacks
        # Override in subclass
      end

      def verbose?
        ::Rails.env.development? || ENV['RCREWAI_VERBOSE'] == 'true'
      end

      def create_agent(name, attributes = {})
        @crew.agents.find_or_create_by(name: name) do |agent|
          agent.assign_attributes(attributes)
        end
      end

      def create_task(description, attributes = {})
        @crew.tasks.find_or_create_by(description: description) do |task|
          task.assign_attributes(attributes)
        end
      end

      def assign_agent_to_task(agent, task)
        task.agents << agent unless task.agents.include?(agent)
      end

      def add_task_dependency(task, dependency)
        task.add_dependency(dependency)
      end
    end
  end
end