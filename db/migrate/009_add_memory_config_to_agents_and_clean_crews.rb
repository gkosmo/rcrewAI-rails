class AddMemoryConfigToAgentsAndCleanCrews < ActiveRecord::Migration[7.0]
  def change
    add_column :rcrewai_agents, :memory_scope, :string
    add_column :rcrewai_agents, :memory_short_term_limit, :integer

    # Core memory is agent-level; these crew columns were never used.
    remove_column :rcrewai_crews, :memory_enabled, :boolean, default: false
    remove_column :rcrewai_crews, :memory, :text
  end
end
