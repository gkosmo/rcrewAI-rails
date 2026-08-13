class CreateRcrewAISpans < ActiveRecord::Migration[7.0]
  def change
    create_table :rcrewai_spans do |t|
      t.references :execution, null: false, foreign_key: { to_table: :rcrewai_executions }
      t.bigint :parent_span_id
      t.string :trace_id, null: false
      t.string :kind, null: false
      t.string :name, null: false
      t.string :status, null: false, default: "running"
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.integer :duration_ms
      t.integer :prompt_tokens
      t.integer :completion_tokens
      t.integer :total_tokens
      t.decimal :cost_usd, precision: 12, scale: 6
      t.text :attributes_json
      t.integer :sequence, null: false

      t.timestamps
    end

    add_index :rcrewai_spans, :parent_span_id
    add_index :rcrewai_spans, :trace_id
    add_index :rcrewai_spans, :kind
    add_index :rcrewai_spans, :status
    add_index :rcrewai_spans, %i[execution_id sequence]

    create_table :rcrewai_span_events do |t|
      t.references :span, null: false, foreign_key: { to_table: :rcrewai_spans }
      t.string :level, null: false, default: "info"
      t.string :name, null: false
      t.text :details
      t.datetime :timestamp, null: false

      t.timestamps
    end

    add_index :rcrewai_span_events, :level
    add_index :rcrewai_span_events, :timestamp
  end
end
