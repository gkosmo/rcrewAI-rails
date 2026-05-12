require "rails_helper"

RSpec.describe RcrewAI::Rails::Crew, type: :model do
  describe "#to_rcrew" do
    let(:crew) do
      described_class.create!(
        name: "Research Crew",
        process_type: "sequential",
        verbose: true
      )
    end

    it "returns a configured RCrewAI::Crew" do
      rcrew = crew.to_rcrew
      expect(rcrew).to be_a(RCrewAI::Crew)
      expect(rcrew.name).to eq("Research Crew")
      expect(rcrew.process_type).to eq(:sequential)
      expect(rcrew.verbose).to be true
    end

    it "adds each agent and task from the association" do
      agent = crew.agents.create!(name: "researcher", role: "Researcher", max_iterations: 5)
      crew.tasks.create!(description: "Investigate", expected_output: "Report", agent: agent)

      rcrew = crew.to_rcrew
      expect(rcrew.agents.length).to eq(1)
      expect(rcrew.agents.first.name).to eq("researcher")
      expect(rcrew.tasks.length).to eq(1)
      expect(rcrew.tasks.first.description).to eq("Investigate")
    end
  end
end
