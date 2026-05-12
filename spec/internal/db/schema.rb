# Test-only schema snapshot. Keep in sync with:
#   lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb
#   db/migrate/001_add_agent_to_tasks.rb

ActiveRecord::Schema.define(version: 1) do
  create_table :rcrewai_crews, force: true do |t|
    t.string :name, null: false
    t.text :description
    t.string :process_type, default: "sequential"
    t.boolean :verbose, default: false
    t.boolean :memory_enabled, default: false
    t.boolean :cache_enabled, default: false
    t.integer :max_rpm
    t.string :manager_llm
    t.text :config
    t.text :memory
    t.boolean :active, default: true
    t.timestamps
  end
  add_index :rcrewai_crews, :name
  add_index :rcrewai_crews, :active

  create_table :rcrewai_agents, force: true do |t|
    t.references :crew, null: false, foreign_key: { to_table: :rcrewai_crews }
    t.string :name, null: false
    t.string :role, null: false
    t.text :goal
    t.text :backstory
    t.boolean :memory_enabled, default: false
    t.boolean :verbose, default: false
    t.boolean :allow_delegation, default: false
    t.text :tools
    t.integer :max_iterations, default: 25
    t.integer :max_rpm
    t.text :llm_config
    t.boolean :active, default: true
    t.timestamps
  end
  add_index :rcrewai_agents, :name

  create_table :rcrewai_tasks, force: true do |t|
    t.references :crew, null: false, foreign_key: { to_table: :rcrewai_crews }
    t.references :agent, foreign_key: { to_table: :rcrewai_agents }
    t.text :description, null: false
    t.text :expected_output, null: false
    t.boolean :async_execution, default: false
    t.text :context
    t.text :output_json
    t.text :output_pydantic
    t.string :output_file
    t.text :tools
    t.string :callback_class
    t.string :callback_method_name
    t.integer :position
    t.boolean :active, default: true
    t.integer :order_index, default: 0
    t.timestamps
  end
  add_index :rcrewai_tasks, :position
  add_index :rcrewai_tasks, :active

  create_table :rcrewai_task_assignments, force: true do |t|
    t.references :task, null: false, foreign_key: { to_table: :rcrewai_tasks }
    t.references :agent, null: false, foreign_key: { to_table: :rcrewai_agents }
    t.timestamps
  end
  add_index :rcrewai_task_assignments, %i[task_id agent_id], unique: true

  create_table :rcrewai_task_dependencies, force: true do |t|
    t.references :task, null: false, foreign_key: { to_table: :rcrewai_tasks }
    t.references :dependency, null: false, foreign_key: { to_table: :rcrewai_tasks }
    t.timestamps
  end
  add_index :rcrewai_task_dependencies, %i[task_id dependency_id], unique: true

  create_table :rcrewai_executions, force: true do |t|
    t.references :crew, null: false, foreign_key: { to_table: :rcrewai_crews }
    t.string :status, null: false
    t.text :inputs
    t.text :output
    t.string :error_message
    t.text :error_details
    t.datetime :started_at
    t.datetime :completed_at
    t.integer :duration_seconds
    t.timestamps
  end
  add_index :rcrewai_executions, :status
  add_index :rcrewai_executions, :created_at

  create_table :rcrewai_execution_logs, force: true do |t|
    t.references :execution, null: false, foreign_key: { to_table: :rcrewai_executions }
    t.string :level, null: false
    t.text :message, null: false
    t.text :details
    t.datetime :timestamp, null: false
    t.timestamps
  end
  add_index :rcrewai_execution_logs, :level
  add_index :rcrewai_execution_logs, :timestamp

  create_table :rcrewai_tools, force: true do |t|
    t.references :agent, null: false, foreign_key: { to_table: :rcrewai_agents }
    t.string :name, null: false
    t.text :description
    t.string :tool_class, null: false
    t.text :config
    t.boolean :active, default: true
    t.timestamps
  end
  add_index :rcrewai_tools, :active
end
