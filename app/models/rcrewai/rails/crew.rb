module RcrewAI
  module Rails
    class Crew < ApplicationRecord
      self.table_name = "rcrewai_crews"
      
      has_many :agents, dependent: :destroy
      has_many :tasks, dependent: :destroy
      has_many :executions, dependent: :destroy
      has_many :knowledge_sources, as: :owner, class_name: "RcrewAI::Rails::KnowledgeSource", dependent: :destroy

      validates :name, presence: true
      validates :process_type, inclusion: { in: %w[sequential hierarchical] }

      serialize :config, coder: JSON
      serialize :memory, coder: JSON

      scope :active, -> { where(active: true) }
      scope :with_agents, -> { includes(:agents) }

      def to_rcrew
        crew = RCrewAI::Crew.new(
          name,
          process: process_type.to_sym,
          verbose: verbose,
          **crew_planning_options
        )

        agents.each do |agent|
          crew.add_agent(agent.to_rcrew_agent)
        end

        tasks.each do |task|
          crew.add_task(task.to_rcrew_task)
        end

        register_kickoff_hooks(crew)
        crew
      end

      # rcrewai 0.5.0 planning options. Emit a key only when meaningfully set, so
      # an all-default crew constructs exactly as it did before.
      def crew_planning_options
        opts = {}
        opts[:planning] = planning if planning
        opts[:planning_llm] = planning_llm.to_sym if planning_llm.present?
        sources = rcrew_knowledge_sources
        opts[:knowledge_sources] = sources if sources.any?
        opts
      end

      def rcrew_knowledge_sources
        knowledge_sources.active.map(&:to_rcrew_source)
      end

      def execute_async(inputs = {})
        CrewExecutionJob.perform_later(self, inputs)
      end

      def execute_sync(inputs = {})
        CrewExecutionJob.perform_now(self, inputs)
      end

      def execute_batch_async(inputs_list)
        batch_id = SecureRandom.uuid
        normalize_batch_inputs(inputs_list).each do |inputs|
          CrewExecutionJob.perform_later(self, inputs, batch_id: batch_id)
        end
        batch_id
      end

      def execute_batch_sync(inputs_list)
        batch_id = SecureRandom.uuid
        normalize_batch_inputs(inputs_list).each do |inputs|
          CrewExecutionJob.perform_now(self, inputs, batch_id: batch_id)
        end
        { batch_id: batch_id, executions: batch_executions(batch_id).to_a }
      end

      def batch_executions(batch_id)
        executions.where(batch_id: batch_id).order(:created_at, :id)
      end

      def last_execution
        executions.order(created_at: :desc).first
      end

      def execution_stats
        {
          total: executions.count,
          successful: executions.successful.count,
          failed: executions.failed.count,
          pending: executions.pending.count,
          average_duration: executions.successful.average(:duration_seconds)
        }
      end

      private

      # Wraps a single inputs hash into a one-element array; leaves an array of
      # hashes as-is. Avoids Array()'s hash-destructuring (Array({a:1}) => [[:a,1]]).
      def normalize_batch_inputs(inputs_list)
        inputs_list.is_a?(Hash) ? [inputs_list] : Array(inputs_list)
      end

      # Registers before/after kickoff hooks resolved from *_class + *_method
      # columns, mirroring the guardrail/callback pattern. No-op when unconfigured.
      def register_kickoff_hooks(crew)
        if (before = hook_callable(before_kickoff_class, before_kickoff_method))
          crew.before_kickoff { |inputs| before.call(inputs) }
        end

        if (after = hook_callable(after_kickoff_class, after_kickoff_method))
          crew.after_kickoff { |result| after.call(result) }
        end
      end

      # Resolves a *_class + *_method pair to a callable; nil when either is blank.
      def hook_callable(class_name, method_name)
        return nil unless class_name.present? && method_name.present?

        klass = class_name.constantize
        ->(arg) { klass.new.send(method_name, arg) }
      end
    end
  end
end