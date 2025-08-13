class AddAgentToTasks < ActiveRecord::Migration[7.0]
  def change
    add_reference :rcrewai_tasks, :agent, null: true, foreign_key: { to_table: :rcrewai_agents }
    add_column :rcrewai_tasks, :active, :boolean, default: true
    add_column :rcrewai_tasks, :order_index, :integer, default: 0
    
    add_index :rcrewai_tasks, :agent_id
    add_index :rcrewai_tasks, :active

    # Create tools table
    create_table :rcrewai_tools do |t|
      t.references :agent, null: false, foreign_key: { to_table: :rcrewai_agents }
      t.string :name, null: false
      t.text :description
      t.string :tool_class, null: false
      t.text :config
      t.boolean :active, default: true

      t.timestamps
    end

    add_index :rcrewai_tools, :agent_id
    add_index :rcrewai_tools, :active
  end
end