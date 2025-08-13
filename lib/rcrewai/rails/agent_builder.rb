module RcrewAI
  module Rails
    module AgentBuilder
      extend ActiveSupport::Concern

      included do
        attr_reader :agent
      end

      class_methods do
        def agent_role(role = nil)
          @agent_role = role if role
          @agent_role || "AI Assistant"
        end

        def agent_goal(goal = nil)
          @agent_goal = goal if goal
          @agent_goal || "Complete assigned tasks efficiently"
        end

        def agent_backstory(backstory = nil)
          @agent_backstory = backstory if backstory
          @agent_backstory || "You are a helpful AI assistant."
        end

        def memory_enabled(enabled = nil)
          @memory_enabled = enabled unless enabled.nil?
          @memory_enabled || true
        end

        def allow_delegation(allowed = nil)
          @allow_delegation = allowed unless allowed.nil?
          @allow_delegation || false
        end

        def max_iterations(iterations = nil)
          @max_iterations = iterations if iterations
          @max_iterations || 25
        end

        def tools(*tool_classes)
          @tools ||= []
          @tools.concat(tool_classes) if tool_classes.any?
          @tools
        end

        def llm_config(config = nil)
          @llm_config = config if config
          @llm_config || default_llm_config
        end

        private

        def default_llm_config
          {
            provider: RcrewAI::Rails.config.default_llm_provider,
            model: RcrewAI::Rails.config.default_llm_model
          }
        end
      end

      def initialize(attributes = {})
        @attributes = attributes
        @agent = build_agent
        setup_tools
        configure_agent
      end

      def to_agent
        @agent
      end

      def to_rcrew_agent
        @agent
      end

      protected

      def build_agent
        RCrewAI::Agent.new(
          role: @attributes[:role] || self.class.agent_role,
          goal: @attributes[:goal] || self.class.agent_goal,
          backstory: @attributes[:backstory] || self.class.agent_backstory,
          memory: @attributes[:memory] || self.class.memory_enabled,
          verbose: verbose?,
          allow_delegation: @attributes[:allow_delegation] || self.class.allow_delegation,
          max_iter: @attributes[:max_iterations] || self.class.max_iterations,
          llm: @attributes[:llm_config] || self.class.llm_config
        )
      end

      def setup_tools
        tools = instantiate_tools
        @agent.tools = tools if tools.any?
      end

      def instantiate_tools
        tool_classes = @attributes[:tools] || self.class.tools
        tool_classes.map do |tool_class|
          case tool_class
          when Class
            tool_class.new
          when Hash
            klass = tool_class[:class] || tool_class["class"]
            params = tool_class[:params] || tool_class["params"] || {}
            klass = klass.constantize if klass.is_a?(String)
            klass.new(**params.symbolize_keys)
          else
            tool_class
          end
        end
      end

      def configure_agent
        # Override in subclass for additional configuration
      end

      def verbose?
        ::Rails.env.development? || ENV['RCREWAI_VERBOSE'] == 'true'
      end
    end
  end
end