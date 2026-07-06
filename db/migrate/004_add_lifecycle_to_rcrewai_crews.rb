class AddLifecycleToRcrewaiCrews < ActiveRecord::Migration[7.0]
  def change
    add_column :rcrewai_crews, :planning, :boolean, default: false, null: false
    add_column :rcrewai_crews, :planning_llm, :string
    add_column :rcrewai_crews, :before_kickoff_class, :string
    add_column :rcrewai_crews, :before_kickoff_method, :string
    add_column :rcrewai_crews, :after_kickoff_class, :string
    add_column :rcrewai_crews, :after_kickoff_method, :string
  end
end
