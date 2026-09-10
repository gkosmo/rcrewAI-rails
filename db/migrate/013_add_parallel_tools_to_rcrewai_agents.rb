class AddParallelToolsToRcrewAIAgents < ActiveRecord::Migration[7.0]
  def change
    # Nullable on purpose: nil means "use the rcrewai default" (parallel tools
    # on), so existing agents keep the gem's behavior without a backfill.
    add_column :rcrewai_agents, :parallel_tools, :boolean
  end
end
