class AddConsensusAgentsToRcrewAICrews < ActiveRecord::Migration[7.0]
  def change
    add_column :rcrewai_crews, :consensus_agents, :integer
  end
end
