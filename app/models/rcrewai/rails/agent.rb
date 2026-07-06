module RcrewAI
  module Rails
    class Agent < ApplicationRecord
      self.table_name = "rcrewai_agents"
      
      belongs_to :crew
      has_many :tasks, dependent: :nullify
      has_many :tools, class_name: 'RcrewAI::Rails::Tool', dependent: :destroy
      has_many :knowledge_sources, as: :owner, class_name: "RcrewAI::Rails::KnowledgeSource", dependent: :destroy

      validates :name, presence: true
      validates :role, presence: true

      serialize :tools, coder: JSON, type: Array
      serialize :llm_config, coder: JSON

      scope :active, -> { where(active: true) }

      def to_rcrew_agent
        RCrewAI::Agent.new(
          name: name,
          role: role,
          goal: goal,
          backstory: backstory,
          verbose: verbose,
          allow_delegation: allow_delegation,
          tools: instantiated_tools,
          max_iterations: max_iterations,
          **agent_options
        )
      end

      # rcrewai 0.5.0 agent options. Only emit a key when it is meaningfully
      # set, so an all-default record constructs exactly as it did pre-0.5.
      def agent_options
        opts = {}
        opts[:max_rpm] = max_rpm if max_rpm.present? && max_rpm.positive?
        opts[:reasoning] = reasoning if reasoning
        opts[:max_reasoning_attempts] = max_reasoning_attempts if reasoning && max_reasoning_attempts
        opts[:respect_context_window] = respect_context_window if respect_context_window
        opts[:llm] = llm_config.symbolize_keys if llm_config.present?
        opts[:knowledge_sources] = rcrew_knowledge_sources if rcrew_knowledge_sources.any?
        opts
      end

      def rcrew_knowledge_sources
        knowledge_sources.active.map(&:to_rcrew_source)
      end

      def instantiated_tools
        return [] if tools.blank?

        tools.map do |tool_config|
          tool_class = tool_config["class"].constantize
          tool_params = tool_config["params"] || {}
          tool_class.new(**tool_params.symbolize_keys)
        end
      end

      def add_tool(tool_class, params = {})
        self.tools ||= []
        self.tools << {
          "class" => tool_class.to_s,
          "params" => params
        }
        save
      end

      def remove_tool(tool_class)
        self.tools = tools.reject { |t| t["class"] == tool_class.to_s }
        save
      end
    end
  end
end