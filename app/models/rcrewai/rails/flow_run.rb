module RcrewAI
  module Rails
    class FlowRun < ApplicationRecord
      self.table_name = "rcrewai_flow_runs"

      serialize :inputs, coder: JSON
      serialize :result, coder: JSON

      validates :flow_class, presence: true
      validates :status, inclusion: { in: %w[pending running completed failed] }

      scope :successful, -> { where(status: "completed") }
      scope :failed, -> { where(status: "failed") }

      # Runs a Flow subclass (a Class or its String name) with an AR-backed state
      # store, wrapped in a run record. Returns the run. Re-raises on failure
      # after recording it.
      def self.execute(flow_class, inputs: {})
        klass = flow_class.is_a?(String) ? flow_class.constantize : flow_class
        run = create!(flow_class: klass.name, status: "pending", inputs: inputs)
        run.run!(klass, inputs)
        run
      end

      def run!(klass, inputs)
        update!(status: "running", started_at: Time.current)
        flow = klass.new(state_store: ActiveRecordStateStore.new)
        state = flow.kickoff(inputs: inputs)
        update!(
          status: "completed",
          state_id: state.id,
          result: state.to_h,
          completed_at: Time.current
        )
      rescue => e
        update!(status: "failed", error_message: e.message, completed_at: Time.current)
        raise
      end
    end
  end
end
