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
        sources = rcrew_knowledge_sources
        opts[:knowledge_sources] = sources if sources.any?
        opts[:memory] = memory_options if memory_enabled
        opts
      end

      # Agent memory config (rcrewai 0.6+). Scalars come from columns; embedder
      # and store come from the engine configuration (set in a host initializer).
      # May return {} — an empty hash still enables memory with core defaults.
      def memory_options
        m = {}
        m[:scope] = memory_scope if memory_scope.present?
        m[:short_term_limit] = memory_short_term_limit if memory_short_term_limit.present?
        embedder = RcrewAI::Rails.config.default_memory_embedder
        store = RcrewAI::Rails.config.default_memory_store
        m[:embedder] = embedder if embedder
        m[:store] = store if store
        m
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