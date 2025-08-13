module RcrewAI
  module Rails
    class CrewsController < ApplicationController
      before_action :set_crew, only: [:show, :edit, :update, :destroy, :execute]

      def index
        @crews = Crew.includes(:agents, :tasks).page(params[:page])
      end

      def show
        @recent_executions = @crew.executions.recent.limit(10)
        @agents = @crew.agents
        @tasks = @crew.tasks.ordered
      end

      def new
        @crew = Crew.new
      end

      def create
        @crew = Crew.new(crew_params)
        
        if @crew.save
          redirect_to @crew, notice: 'Crew was successfully created.'
        else
          render :new
        end
      end

      def edit
      end

      def update
        if @crew.update(crew_params)
          redirect_to @crew, notice: 'Crew was successfully updated.'
        else
          render :edit
        end
      end

      def destroy
        @crew.destroy
        redirect_to crews_url, notice: 'Crew was successfully destroyed.'
      end

      def execute
        inputs = params[:inputs] || {}
        execution = @crew.execute_async(inputs)
        
        redirect_to execution_path(execution), notice: 'Crew execution started.'
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