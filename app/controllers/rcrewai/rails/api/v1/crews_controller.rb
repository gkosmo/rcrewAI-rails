module RcrewAI
  module Rails
    module Api
      module V1
        class CrewsController < ApplicationController
          skip_before_action :check_web_ui_enabled
          before_action :set_crew, only: [:show, :execute]

          def index
            @crews = Crew.includes(:agents, :tasks).all
            render json: @crews.as_json(include: [:agents, :tasks])
          end

          def show
            render json: @crew.as_json(include: [:agents, :tasks, :executions])
          end

          def create
            @crew = Crew.new(crew_params)
            
            if @crew.save
              render json: @crew, status: :created
            else
              render json: { errors: @crew.errors }, status: :unprocessable_entity
            end
          end

          def execute
            inputs = params[:inputs] || {}
            execution = @crew.execute_async(inputs)
            
            render json: {
              execution_id: execution.id,
              status: execution.status,
              message: 'Crew execution started successfully'
            }
          end

          private

          def set_crew
            @crew = Crew.find(params[:id])
          end

          def crew_params
            params.require(:crew).permit(
              :name, :description, :process_type, :verbose,
              :memory_enabled, :cache_enabled, :max_rpm, :manager_llm, :active
            )
          end
        end
      end
    end
  end
end