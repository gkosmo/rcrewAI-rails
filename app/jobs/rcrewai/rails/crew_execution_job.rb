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
          execution.log("info", "Starting crew execution", { crew_id: crew.id, inputs: inputs })

          rcrew = crew.to_rcrew

          result = rcrew.execute(stream: stream_sink_for(execution))

          execution.complete!(result)
          execution.log("info", "Crew execution completed", { result: result })

          notify_completion(crew, execution, result)

          result
        rescue => e
          execution.fail!(e)
          execution.log("error", "Crew execution failed", {
            error: e.message,
            backtrace: e.backtrace&.first(5)
          })

          raise
        end
      end

      private

      # Build a stream sink that translates rcrewai events into ExecutionLog rows.
      # Note: the gem currently builds the sink but does not yet thread it down
      # to per-agent execution, so this is wired up for forward-compatibility.
      def stream_sink_for(execution)
        lambda do |event|
          case event
          when RCrewAI::Events::IterationStart
            execution.log("debug", "Iteration #{event.iteration_index} start", { agent: event.agent })
          when RCrewAI::Events::IterationEnd
            execution.log("debug", "Iteration end", { agent: event.agent, finish_reason: event.finish_reason })
          when RCrewAI::Events::ToolCallStart
            execution.log("info", "Tool call: #{event.tool}", { args: event.args, agent: event.agent })
          when RCrewAI::Events::ToolCallResult
            execution.log("info", "Tool result: #{event.tool}", { duration_ms: event.duration_ms, agent: event.agent })
          when RCrewAI::Events::ToolCallError
            execution.log("error", "Tool error: #{event.tool}", { error: event.error, agent: event.agent })
          when RCrewAI::Events::Usage
            execution.log("debug", "Usage", {
              prompt_tokens: event.prompt_tokens,
              completion_tokens: event.completion_tokens,
              total_tokens: event.total_tokens,
              cost_usd: event.cost_usd,
              agent: event.agent
            })
          when RCrewAI::Events::Error
            execution.log("error", "Crew error", { error: event.error, agent: event.agent })
          end
        end
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
