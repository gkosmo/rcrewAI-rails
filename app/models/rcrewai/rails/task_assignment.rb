module RcrewAI
  module Rails
    class TaskAssignment < ApplicationRecord
      self.table_name = "rcrewai_task_assignments"
      
      belongs_to :task
      belongs_to :agent

      validates :task_id, uniqueness: { scope: :agent_id }
    end
  end
end