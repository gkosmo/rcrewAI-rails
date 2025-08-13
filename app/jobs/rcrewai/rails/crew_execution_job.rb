module RcrewAI
  module Rails
    class CrewExecutionJob < ActiveJob::Base
      queue_as { RcrewAI::Rails.config.job_queue_name }

      retry_on StandardError, wait: :exponentially_longer, attempts: 3

      def perform(crew, inputs = {})
        execution = crew.executions.create!(
          status: "pending",
          inputs: inputs
        )

        begin
          execution.start!
          execution.log("info", "Starting crew execution", { crew_id: crew.id })

          # Convert Rails models to RcrewAI objects
          rcrew = crew.to_rcrew
          
          # Execute the crew with logging
          result = execute_with_logging(rcrew, inputs, execution)
          
          execution.complete!(result)
          execution.log("info", "Crew execution completed successfully", { result: result })
          
          # Trigger callbacks if configured
          notify_completion(crew, execution, result)
          
          result
        rescue => e
          execution.fail!(e)
          execution.log("error", "Crew execution failed", { 
            error: e.message,
            backtrace: e.backtrace.first(5)
          })
          
          # Re-raise for ActiveJob retry mechanism
          raise
        end
      end

      private

      def execute_with_logging(rcrew, inputs, execution)
        # Set up logging callbacks
        rcrew.before_task do |task|
          execution.log("info", "Starting task: #{task.description}")
        end

        rcrew.after_task do |task, output|
          execution.log("info", "Completed task: #{task.description}", { output: output })
        end

        # Execute the crew
        rcrew.kickoff(inputs)
      end

      def notify_completion(crew, execution, result)
        # Send notifications if configured
        if crew.notification_webhook_url.present?
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

        # Trigger Rails events
        ActiveSupport::Notifications.instrument("crew_execution.completed", {
          crew: crew,
          execution: execution,
          result: result
        })
      end
    end
  end
end