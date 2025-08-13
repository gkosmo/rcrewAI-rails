module RcrewAI
  module Rails
    class TaskDependency < ApplicationRecord
      self.table_name = "rcrewai_task_dependencies"
      
      belongs_to :task
      belongs_to :dependency, class_name: "Task"

      validates :task_id, uniqueness: { scope: :dependency_id }
      validate :no_circular_dependencies

      private

      def no_circular_dependencies
        return unless dependency

        if creates_circular_dependency?
          errors.add(:dependency, "would create a circular dependency")
        end
      end

      def creates_circular_dependency?
        visited = Set.new
        queue = [dependency_id]

        while queue.any?
          current_id = queue.shift
          return true if current_id == task_id
          
          next if visited.include?(current_id)
          visited.add(current_id)

          TaskDependency.where(task_id: current_id).pluck(:dependency_id).each do |dep_id|
            queue << dep_id
          end
        end

        false
      end
    end
  end
end