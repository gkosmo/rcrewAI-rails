module RcrewAI
  module Rails
    class Execution < ApplicationRecord
      self.table_name = "rcrewai_executions"
      
      belongs_to :crew
      has_many :execution_logs, dependent: :destroy

      validates :status, inclusion: { in: %w[pending running completed failed cancelled] }

      serialize :inputs, coder: JSON
      serialize :output, coder: JSON
      serialize :error_details, coder: JSON

      scope :successful, -> { where(status: "completed") }
      scope :failed, -> { where(status: "failed") }
      scope :pending, -> { where(status: "pending") }
      scope :running, -> { where(status: "running") }
      scope :recent, -> { order(created_at: :desc) }

      before_create :set_initial_status

      def start!
        update!(
          status: "running",
          started_at: Time.current
        )
      end

      def complete!(result)
        update!(
          status: "completed",
          output: result,
          completed_at: Time.current,
          duration_seconds: calculate_duration
        )
      end

      def fail!(error)
        update!(
          status: "failed",
          error_message: error.message,
          error_details: {
            class: error.class.name,
            message: error.message,
            backtrace: error.backtrace&.first(10)
          },
          completed_at: Time.current,
          duration_seconds: calculate_duration
        )
      end

      def cancel!
        update!(
          status: "cancelled",
          completed_at: Time.current,
          duration_seconds: calculate_duration
        )
      end

      def running?
        status == "running"
      end

      def completed?
        status == "completed"
      end

      def failed?
        status == "failed"
      end

      def finished?
        %w[completed failed cancelled].include?(status)
      end

      def log(level, message, details = {})
        execution_logs.create!(
          level: level,
          message: message,
          details: details,
          timestamp: Time.current
        )
      end

      private

      def set_initial_status
        self.status ||= "pending"
      end

      def calculate_duration
        return nil unless started_at.present?
        (Time.current - started_at).to_i
      end
    end
  end
end