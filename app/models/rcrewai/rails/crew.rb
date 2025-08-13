module RcrewAI
  module Rails
    class Crew < ApplicationRecord
      self.table_name = "rcrewai_crews"
      
      has_many :agents, dependent: :destroy
      has_many :tasks, dependent: :destroy
      has_many :executions, dependent: :destroy

      validates :name, presence: true
      validates :process_type, inclusion: { in: %w[sequential hierarchical] }

      serialize :config, coder: JSON
      serialize :memory, coder: JSON

      scope :active, -> { where(active: true) }
      scope :with_agents, -> { includes(:agents) }

      def to_rcrew
        crew = RCrewAI::Crew.new(
          name: name,
          description: description,
          process: process_type.to_sym,
          verbose: verbose,
          memory: memory_enabled,
          cache: cache_enabled,
          max_rpm: max_rpm,
          manager_llm: manager_llm
        )

        agents.each do |agent|
          crew.add_agent(agent.to_rcrew_agent)
        end

        tasks.each do |task|
          crew.add_task(task.to_rcrew_task)
        end

        crew
      end

      def execute_async(inputs = {})
        CrewExecutionJob.perform_later(self, inputs)
      end

      def execute_sync(inputs = {})
        CrewExecutionJob.perform_now(self, inputs)
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
    end
  end
end