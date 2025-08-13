module RcrewAI
  module Rails
    class ToolsController < ApplicationController
      before_action :set_agent
      before_action :set_tool, only: [:show, :edit, :update, :destroy]

      def index
        @tools = @agent.tools
      end

      def show
      end

      def new
        @tool = @agent.tools.build
      end

      def create
        @tool = @agent.tools.build(tool_params)
        
        if @tool.save
          redirect_to [@agent, @tool], notice: 'Tool was successfully created.'
        else
          render :new
        end
      end

      def edit
      end

      def update
        if @tool.update(tool_params)
          redirect_to [@agent, @tool], notice: 'Tool was successfully updated.'
        else
          render :edit
        end
      end

      def destroy
        @tool.destroy
        redirect_to @agent, notice: 'Tool was successfully deleted.'
      end

      private

      def set_agent
        @agent = Agent.find(params[:agent_id])
      end

      def set_tool
        @tool = @agent.tools.find(params[:id])
      end

      def tool_params
        params.require(:tool).permit(
          :name, :description, :tool_class, :config, :active
        )
      end
    end
  end
end