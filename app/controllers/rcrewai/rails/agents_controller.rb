module RcrewAI
  module Rails
    class AgentsController < ApplicationController
      before_action :set_crew, if: -> { params[:crew_id] }
      before_action :set_agent, only: [:show, :edit, :update, :destroy]

      def index
        @agents = @crew ? @crew.agents : Agent.includes(:crew).all
      end

      def show
        @tools = @agent.tools
      end

      def new
        @agent = @crew ? @crew.agents.build : Agent.new
      end

      def create
        @agent = @crew ? @crew.agents.build(agent_params) : Agent.new(agent_params)
        
        if @agent.save
          redirect_to @agent, notice: 'Agent was successfully created.'
        else
          render :new
        end
      end

      def edit
      end

      def update
        if @agent.update(agent_params)
          redirect_to @agent, notice: 'Agent was successfully updated.'
        else
          render :edit
        end
      end

      def destroy
        crew = @agent.crew
        @agent.destroy
        redirect_to crew ? crew : agents_url, notice: 'Agent was successfully deleted.'
      end

      private

      def set_crew
        @crew = Crew.find(params[:crew_id])
      end

      def set_agent
        @agent = @crew ? @crew.agents.find(params[:id]) : Agent.find(params[:id])
      end

      def agent_params
        params.require(:agent).permit(
          :name, :role, :goal, :backstory, :verbose, :allow_delegation, 
          :max_iter, :max_execution_time, :llm_config, :tools_config, :active
        )
      end
    end
  end
end