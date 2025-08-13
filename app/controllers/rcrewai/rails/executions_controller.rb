module RcrewAI
  module Rails
    class ExecutionsController < ApplicationController
      before_action :set_execution, only: [:show, :cancel, :logs]

      def index
        @executions = Execution.includes(:crew)
        @executions = @executions.where(crew_id: params[:crew_id]) if params[:crew_id]
        @executions = @executions.where(status: params[:status]) if params[:status]
        @executions = @executions.recent.limit(20)
      end

      def show
        @logs = @execution.execution_logs.recent.limit(50)
        
        respond_to do |format|
          format.html
          format.json { render json: execution_json }
          format.turbo_stream if request.headers["Turbo-Frame"]
        end
      end

      def cancel
        if @execution.running?
          @execution.cancel!
          redirect_to @execution, notice: 'Execution was cancelled.'
        else
          redirect_to @execution, alert: 'Execution cannot be cancelled.'
        end
      end

      def logs
        @logs = @execution.execution_logs
        @logs = @logs.where(level: params[:level]) if params[:level]
        @logs = @logs.recent.limit(params[:limit] || 100)
        
        respond_to do |format|
          format.json { render json: @logs }
          format.turbo_stream
        end
      end

      private

      def set_execution
        @execution = Execution.find(params[:id])
      end

      def execution_json
        {
          id: @execution.id,
          crew_name: @execution.crew.name,
          status: @execution.status,
          started_at: @execution.started_at,
          completed_at: @execution.completed_at,
          duration_seconds: @execution.duration_seconds,
          inputs: @execution.inputs,
          output: @execution.output,
          error_message: @execution.error_message,
          logs_count: @execution.execution_logs.count
        }
      end
    end
  end
end