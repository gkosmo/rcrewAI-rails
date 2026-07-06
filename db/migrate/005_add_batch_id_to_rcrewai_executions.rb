class AddBatchIdToRcrewaiExecutions < ActiveRecord::Migration[7.0]
  def change
    add_column :rcrewai_executions, :batch_id, :string
    add_index :rcrewai_executions, :batch_id
  end
end
