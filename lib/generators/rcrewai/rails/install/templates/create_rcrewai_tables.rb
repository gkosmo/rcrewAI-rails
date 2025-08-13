class CreateRcrewaiTables < ActiveRecord::Migration[7.0]
  def change
    create_table :rcrewai_crews do |t|
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

    create_table :rcrewai_agents do |t|
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

    add_index :rcrewai_agents, :crew_id
    add_index :rcrewai_agents, :name

    create_table :rcrewai_tasks do |t|
      t.references :crew, null: false, foreign_key: { to_table: :rcrewai_crews }
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

      t.timestamps
    end

    add_index :rcrewai_tasks, :crew_id
    add_index :rcrewai_tasks, :position

    create_table :rcrewai_task_assignments do |t|
      t.references :task, null: false, foreign_key: { to_table: :rcrewai_tasks }
      t.references :agent, null: false, foreign_key: { to_table: :rcrewai_agents }

      t.timestamps
    end

    add_index :rcrewai_task_assignments, [:task_id, :agent_id], unique: true

    create_table :rcrewai_task_dependencies do |t|
      t.references :task, null: false, foreign_key: { to_table: :rcrewai_tasks }
      t.references :dependency, null: false, foreign_key: { to_table: :rcrewai_tasks }

      t.timestamps
    end

    add_index :rcrewai_task_dependencies, [:task_id, :dependency_id], unique: true

    create_table :rcrewai_executions do |t|
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

    add_index :rcrewai_executions, :crew_id
    add_index :rcrewai_executions, :status
    add_index :rcrewai_executions, :created_at

    create_table :rcrewai_execution_logs do |t|
      t.references :execution, null: false, foreign_key: { to_table: :rcrewai_executions }
      t.string :level, null: false
      t.text :message, null: false
      t.text :details
      t.datetime :timestamp, null: false

      t.timestamps
    end

    add_index :rcrewai_execution_logs, :execution_id
    add_index :rcrewai_execution_logs, :level
    add_index :rcrewai_execution_logs, :timestamp
  end
end