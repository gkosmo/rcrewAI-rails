module RcrewAI
  module Rails
    class TasksController < ApplicationController
      before_action :set_crew, if: -> { params[:crew_id] }
      before_action :set_task, only: [:show, :edit, :update, :destroy, :add_dependency, :remove_dependency]

      def index
        @tasks = @crew ? @crew.tasks.ordered : Task.includes(:crew, :agent).ordered
      end

      def show
        @dependencies = @task.dependencies
      end

      def new
        @task = @crew ? @crew.tasks.build : Task.new
      end

      def create
        @task = @crew ? @crew.tasks.build(task_params) : Task.new(task_params)
        
        if @task.save
          redirect_to @task, notice: 'Task was successfully created.'
        else
          render :new
        end
      end

      def edit
      end

      def update
        if @task.update(task_params)
          redirect_to @task, notice: 'Task was successfully updated.'
        else
          render :edit
        end
      end

      def destroy
        crew = @task.crew
        @task.destroy
        redirect_to crew ? crew : tasks_url, notice: 'Task was successfully deleted.'
      end

      def add_dependency
        dependency = Task.find(params[:dependency_id])
        @task.dependencies << dependency unless @task.dependencies.include?(dependency)
        redirect_to @task, notice: 'Dependency added successfully.'
      end

      def remove_dependency
        dependency = @task.dependencies.find(params[:dependency_id])
        @task.dependencies.delete(dependency)
        redirect_to @task, notice: 'Dependency removed successfully.'
      end

      private

      def set_crew
        @crew = Crew.find(params[:crew_id])
      end

      def set_task
        @task = @crew ? @crew.tasks.find(params[:id]) : Task.find(params[:id])
      end

      def task_params
        params.require(:task).permit(
          :description, :expected_output, :agent_id, :async_execution, 
          :context, :config, :tools_config, :output_file, :active, :order_index
        )
      end
    end
  end
end