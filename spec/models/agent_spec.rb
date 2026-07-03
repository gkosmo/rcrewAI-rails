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

  describe "0.5.0 option forwarding" do
    def build_agent(attrs = {})
      crew.agents.create!({ name: "a", role: "R", goal: "G" }.merge(attrs))
    end

    it "does not forward any new options for an all-default agent" do
      captured = nil
      allow(RCrewAI::Agent).to receive(:new).and_wrap_original do |orig, **kwargs|
        captured = kwargs
        orig.call(**kwargs)
      end

      build_agent.to_rcrew_agent

      expect(captured).not_to have_key(:max_rpm)
      expect(captured).not_to have_key(:reasoning)
      expect(captured).not_to have_key(:max_reasoning_attempts)
      expect(captured).not_to have_key(:respect_context_window)
      expect(captured).not_to have_key(:llm)
    end

    it "forwards max_rpm and builds a rate limiter" do
      agent = build_agent(max_rpm: 30).to_rcrew_agent
      expect(agent.rate_limiter).not_to be_nil
    end

    it "does not forward max_rpm when it is zero" do
      captured = nil
      allow(RCrewAI::Agent).to receive(:new).and_wrap_original do |orig, **kwargs|
        captured = kwargs
        orig.call(**kwargs)
      end

      build_agent(max_rpm: 0).to_rcrew_agent

      expect(captured).not_to have_key(:max_rpm)
    end

    it "forwards reasoning and max_reasoning_attempts when reasoning is on" do
      captured = nil
      allow(RCrewAI::Agent).to receive(:new).and_wrap_original do |orig, **kwargs|
        captured = kwargs
        orig.call(**kwargs)
      end

      build_agent(reasoning: true, max_reasoning_attempts: 5).to_rcrew_agent

      expect(captured[:reasoning]).to be true
      expect(captured[:max_reasoning_attempts]).to eq(5)
    end

    it "does not forward reasoning attempts when reasoning is off" do
      captured = nil
      allow(RCrewAI::Agent).to receive(:new).and_wrap_original do |orig, **kwargs|
        captured = kwargs
        orig.call(**kwargs)
      end

      build_agent(reasoning: false, max_reasoning_attempts: 5).to_rcrew_agent

      expect(captured).not_to have_key(:reasoning)
      expect(captured).not_to have_key(:max_reasoning_attempts)
    end

    it "forwards respect_context_window when enabled" do
      captured = nil
      allow(RCrewAI::Agent).to receive(:new).and_wrap_original do |orig, **kwargs|
        captured = kwargs
        orig.call(**kwargs)
      end

      build_agent(respect_context_window: true).to_rcrew_agent

      expect(captured[:respect_context_window]).to be true
    end

    it "forwards llm_config as a symbolized llm: hash" do
      captured = nil
      allow(RCrewAI::Agent).to receive(:new).and_wrap_original do |orig, **kwargs|
        captured = kwargs
        orig.call(**kwargs)
      end

      build_agent(llm_config: { "provider" => "anthropic", "model" => "claude-sonnet-5" }).to_rcrew_agent

      expect(captured[:llm]).to eq(provider: "anthropic", model: "claude-sonnet-5")
    end
  end
end
