module RcrewAI
  module Rails
    class CrewExecutionJob < ActiveJob::Base
      queue_as { RcrewAI::Rails.config.job_queue_name }

      retry_on StandardError, wait: :exponentially_longer, attempts: 3

      def perform(crew, inputs = {}, batch_id: nil)
        execution = crew.executions.create!(
          status: "pending",
          inputs: inputs,
          batch_id: batch_id
        )
        collector = nil

        begin
          execution.start!
          execution.log("info", "Starting crew execution", { crew_id: crew.id, inputs: inputs })

          rcrew = crew.to_rcrew

          collector = collector_for(execution)
          collector&.start_crew_span(crew_name: crew.name)

          result = rcrew.execute(stream: collector)

          # Close agent spans as successful before finish!, which treats
          # anything still open as an aborted run.
          collector&.finish_open_agent_spans(status: "ok")
          collector&.finish_crew_span(status: "ok")
          collector&.finish!

          execution.complete!(result)
          execution.log("info", "Crew execution completed", { result: result })

          notify_completion(crew, execution, result)

          result
        rescue => e
          collector&.finish!
          execution.fail!(e)
          execution.log("error", "Crew execution failed", {
            error: e.message,
            backtrace: e.backtrace&.first(5)
          })

          raise
        end
      end

      private

      # Translates rcrewai events into the span tree. Returns nil when
      # observation is disabled so no sink is attached at all.
      def collector_for(execution)
        return nil unless RcrewAI::Rails.config.observation_enabled

        RcrewAI::Rails::Observation::Collector.new(execution: execution)
      end

      def notify_completion(crew, execution, result)
        if crew.respond_to?(:notification_webhook_url) && crew.notification_webhook_url.present?
          NotificationJob.perform_later(
            crew.notification_webhook_url,
            {
              crew_id: crew.id,
              execution_id: execution.id,
              status: "completed",
              result: result
            }
          )
        end

        ActiveSupport::Notifications.instrument("crew_execution.completed", {
          crew: crew,
          execution: execution,
          result: result
        })
      end
    end
  end
end
