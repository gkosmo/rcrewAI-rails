class AddConfigToRcrewaiAgents < ActiveRecord::Migration[7.0]
  def change
    # max_rpm and llm_config already exist on rcrewai_agents from the
    # original create table; only the 0.5.0 additions are new.
    add_column :rcrewai_agents, :reasoning, :boolean, default: false, null: false
    add_column :rcrewai_agents, :max_reasoning_attempts, :integer, default: 3
    add_column :rcrewai_agents, :respect_context_window, :boolean, default: false, null: false
  end
end
