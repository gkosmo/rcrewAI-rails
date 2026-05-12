require "rails_helper"

RSpec.describe RcrewAI::Rails::Agent, type: :model do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "C", process_type: "sequential") }

  describe "#to_rcrew_agent" do
    it "passes name, role, goal, backstory, verbose, allow_delegation, max_iterations" do
      record = crew.agents.create!(
        name: "researcher",
        role: "Researcher",
        goal: "Find facts",
        backstory: "Lifelong librarian",
        verbose: true,
        allow_delegation: false,
        max_iterations: 8
      )

      rcrew = record.to_rcrew_agent
      expect(rcrew).to be_a(RCrewAI::Agent)
      expect(rcrew.name).to eq("researcher")
      expect(rcrew.role).to eq("Researcher")
      expect(rcrew.goal).to eq("Find facts")
      expect(rcrew.backstory).to eq("Lifelong librarian")
      expect(rcrew.verbose).to be true
      expect(rcrew.allow_delegation).to be false
      expect(rcrew.max_iterations).to eq(8)
    end

    # NOTE: The Agent model declares both `has_many :tools` (the join model)
    # and `serialize :tools` (the JSON column). The association wins and the
    # JSON column is effectively unreachable — pre-existing engine bug, not
    # in scope for this branch. When that's untangled, add a spec here that
    # round-trips a serialized tool config through Agent#instantiated_tools.
  end
end
