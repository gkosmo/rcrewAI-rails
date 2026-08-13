class AddOutputProcessingToRcrewAITasks < ActiveRecord::Migration[7.0]
  def change
    # output_file already exists on rcrewai_tasks from the original create
    # table; only the new 0.4/0.5 output-processing options are added here.
    add_column :rcrewai_tasks, :output_schema, :text
    add_column :rcrewai_tasks, :guardrail_class, :string
    add_column :rcrewai_tasks, :guardrail_method_name, :string
    add_column :rcrewai_tasks, :guardrail_max_retries, :integer, default: 3
    add_column :rcrewai_tasks, :create_directory, :boolean, default: true
    add_column :rcrewai_tasks, :markdown, :boolean, default: false
    add_column :rcrewai_tasks, :attachments, :text
  end
end
