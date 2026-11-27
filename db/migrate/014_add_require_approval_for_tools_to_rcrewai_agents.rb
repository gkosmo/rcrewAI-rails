class AddRequireApprovalForToolsToRcrewAIAgents < ActiveRecord::Migration[7.0]
  def change
    add_column :rcrewai_agents, :require_approval_for_tools, :boolean, default: false, null: false
  end
end
