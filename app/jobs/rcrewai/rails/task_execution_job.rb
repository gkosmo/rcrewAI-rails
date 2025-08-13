module RcrewAI
  module Rails
    class TaskExecutionJob < ActiveJob::Base
      queue_as { RcrewAI::Rails.config.job_queue_name }

      retry_on StandardError, wait: 5.seconds, attempts: 3

      def perform(task, agent, inputs = {})
        execution_log = {
          task_id: task.id,
          agent_id: agent.id,
          started_at: Time.current
        }

        begin
          # Convert to RcrewAI objects
          rcrew_task = task.to_rcrew_task
          rcrew_agent = agent.to_rcrew_agent

          # Execute the task
          result = rcrew_agent.execute_task(rcrew_task, context: inputs)

          execution_log[:completed_at] = Time.current
          execution_log[:status] = "completed"
          execution_log[:result] = result

          # Save result if configured
          if task.output_file.present?
            save_output_to_file(task.output_file, result)
          end

          # Log success
          ::Rails.logger.info "Task #{task.id} completed successfully by agent #{agent.id}"

          result
        rescue => e
          execution_log[:completed_at] = Time.current
          execution_log[:status] = "failed"
          execution_log[:error] = e.message

          ::Rails.logger.error "Task #{task.id} failed: #{e.message}"
          
          raise
        ensure
          # Could save execution log to database if needed
          log_task_execution(execution_log)
        end
      end

      private

      def save_output_to_file(filename, content)
        output_path = ::Rails.root.join("tmp", "rcrewai_outputs", filename)
        FileUtils.mkdir_p(File.dirname(output_path))
        File.write(output_path, content)
      end

      def log_task_execution(log_data)
        ActiveSupport::Notifications.instrument("task_execution.rcrewai", log_data)
      end
    end
  end
end