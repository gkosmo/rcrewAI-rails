module RcrewAI
  module Rails
    class Tool < ApplicationRecord
      self.table_name = "rcrewai_tools"
      
      belongs_to :agent

      validates :name, presence: true
      validates :tool_class, presence: true

      serialize :config, coder: JSON

      scope :active, -> { where(active: true) }

      def instantiated_tool
        return nil if tool_class.blank?
        
        klass = tool_class.constantize
        params = config || {}
        klass.new(**params.symbolize_keys)
      rescue NameError
        nil
      end
    end
  end
end