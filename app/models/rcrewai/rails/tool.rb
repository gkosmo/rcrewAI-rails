module RcrewAI
  module Rails
    class Tool < ApplicationRecord
      self.table_name = "rcrewai_tools"
      
      belongs_to :agent

      validates :name, presence: true
      validates :tool_class, presence: true
      validate :tool_class_allowed, if: :tool_class_changed?

      serialize :config, coder: JSON

      scope :active, -> { where(active: true) }

      def instantiated_tool
        return nil if tool_class.blank?
        
        ToolAllowlist.build(tool_class, config)
      rescue NameError
        nil
      end

      private

      def tool_class_allowed
        return if tool_class.blank? || ToolAllowlist.allowed?(tool_class)

        errors.add(:tool_class, "is not an allowed tool class")
      end
    end
  end
end