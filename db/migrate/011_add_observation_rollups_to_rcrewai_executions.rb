class AddObservationRollupsToRcrewAIExecutions < ActiveRecord::Migration[7.0]
  def change
    add_column :rcrewai_executions, :total_cost_usd, :decimal, precision: 12, scale: 6
    add_column :rcrewai_executions, :total_tokens, :integer
    add_column :rcrewai_executions, :span_count, :integer, default: 0, null: false
    add_column :rcrewai_executions, :error_count, :integer, default: 0, null: false
  end
end
