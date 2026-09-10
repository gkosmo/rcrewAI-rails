class CreateRcrewAICheckpoints < ActiveRecord::Migration[7.0]
  def change
    create_table :rcrewai_checkpoints do |t|
      t.string :run_id, null: false
      t.string :parent_run_id
      t.string :crew_name
      t.text :data, null: false
      t.datetime :checkpoint_updated_at

      t.timestamps
    end

    add_index :rcrewai_checkpoints, :run_id, unique: true
    add_index :rcrewai_checkpoints, :parent_run_id

    add_column :rcrewai_crews, :checkpoint_enabled, :boolean

    add_column :rcrewai_executions, :run_id, :string
    add_column :rcrewai_executions, :parent_run_id, :string
    add_index :rcrewai_executions, :run_id
  end
end
