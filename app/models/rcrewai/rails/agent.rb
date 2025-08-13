module RcrewAI
  module Rails
    class Agent < ApplicationRecord
      self.table_name = "rcrewai_agents"
      
      belongs_to :crew
      has_many :task_assignments, dependent: :destroy
      has_many :tasks, through: :task_assignments

      validates :name, presence: true
      validates :role, presence: true

      serialize :tools, coder: JSON, type: Array
      serialize :llm_config, coder: JSON

      scope :active, -> { where(active: true) }

      def to_rcrew_agent
        RCrewAI::Agent.new(
          role: role,
          goal: goal,
          backstory: backstory,
          memory: memory_enabled,
          verbose: verbose,
          allow_delegation: allow_delegation,
          tools: instantiated_tools,
          max_iter: max_iterations,
          max_rpm: max_rpm,
          llm: llm_config
        )
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