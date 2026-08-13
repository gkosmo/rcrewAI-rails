class CreateRcrewAIFlows < ActiveRecord::Migration[7.0]
  def change
    create_table :rcrewai_flow_states do |t|
      t.string :state_id, null: false
      t.text :data, null: false
      t.timestamps
    end
    add_index :rcrewai_flow_states, :state_id, unique: true

    create_table :rcrewai_flow_runs do |t|
      t.string :flow_class, null: false
      t.string :state_id
      t.string :status, null: false
      t.text :inputs
      t.text :result
      t.string :error_message
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :rcrewai_flow_runs, :status
    add_index :rcrewai_flow_runs, :state_id
  end
end
