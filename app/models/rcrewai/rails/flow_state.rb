module RcrewAI
  module Rails
    class FlowState < ApplicationRecord
      self.table_name = "rcrewai_flow_states"

      serialize :data, coder: JSON

      validates :state_id, presence: true, uniqueness: true
    end
  end
end
