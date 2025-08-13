module RcrewAI
  module Rails
    class ExecutionLog < ApplicationRecord
      self.table_name = "rcrewai_execution_logs"
      
      belongs_to :execution

      validates :level, inclusion: { in: %w[debug info warn error] }
      validates :message, presence: true

      serialize :details, coder: JSON

      scope :errors, -> { where(level: "error") }
      scope :warnings, -> { where(level: "warn") }
      scope :recent, -> { order(timestamp: :desc) }
    end
  end
end