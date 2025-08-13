module RcrewAI
  module Rails
    module Api
      module V1
        class ExecutionsController < ApplicationController
          skip_before_action :check_web_ui_enabled
          before_action :set_execution, only: [:show, :status, :logs]

          def index
            @executions = Execution.includes(:crew)
            @executions = @executions.where(crew_id: params[:crew_id]) if params[:crew_id]
            @executions = @executions.where(status: params[:status]) if params[:status]
            @executions = @executions.recent.limit(params[:limit] || 50)
            
            render json: @executions.as_json(include: :crew)
          end

          def show
            render json: @execution.as_json(
              include: :crew,
              methods: [:duration_seconds]
            )
          end

          def status
            render json: {
              id: @execution.id,
              status: @execution.status,
              started_at: @execution.started_at,
              completed_at: @execution.completed_at,
              duration_seconds: @execution.duration_seconds
            }
          end

          def logs
            @logs = @execution.execution_logs
            @logs = @logs.where(level: params[:level]) if params[:level]
            @logs = @logs.recent.limit(params[:limit] || 100)
            
            render json: @logs.as_json(only: [:id, :level, :message, :details, :timestamp])
          end

          private

          def set_execution
            @execution = Execution.find(params[:id])
          end
        end
      end
    end
  end
end