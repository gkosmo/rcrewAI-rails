module RcrewAI
  module Rails
    class Task < ApplicationRecord
      self.table_name = "rcrewai_tasks"
      
      belongs_to :crew
      belongs_to :agent, optional: true
      has_many :task_dependencies, foreign_key: :task_id, dependent: :destroy
      has_many :dependencies, through: :task_dependencies, source: :dependency

      validates :description, presence: true
      validates :expected_output, presence: true

      serialize :context, coder: JSON, type: Array
      serialize :output_json, coder: JSON
      serialize :output_pydantic, coder: JSON
      serialize :tools, coder: JSON, type: Array

      scope :ordered, -> { order(:order_index) }

      def to_rcrew_task
        RCrewAI::Task.new(
          name: rcrew_task_name,
          description: description,
          expected_output: expected_output,
          agent: agent&.to_rcrew_agent,
          context: context,
          async: async_execution,
          tools: instantiated_tools,
          callback: callback_method
        )
      end


      def instantiated_tools
        return [] if tools.blank?

        tools.map do |tool_config|
          tool_class = tool_config["class"].constantize
          tool_params = tool_config["params"] || {}
          tool_class.new(**tool_params.symbolize_keys)
        end
      end

      def add_dependency(other_task)
        task_dependencies.create!(dependency: other_task)
      end

      def remove_dependency(other_task)
        task_dependencies.where(dependency: other_task).destroy_all
      end

      private

      def rcrew_task_name
        return "task_#{id}" if id
        return description.to_s.parameterize.first(40).presence || "task" if description.present?

        "task"
      end

      def callback_method
        return nil unless callback_class.present? && callback_method_name.present?
        
        klass = callback_class.constantize
        ->(output) { klass.new.send(callback_method_name, output) }
      end
    end
  end
end