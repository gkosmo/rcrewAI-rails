require "rails_helper"

RSpec.describe "tool approval on engine agents" do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "C", process_type: "sequential") }

  def build_agent(attrs = {})
    crew.agents.create!({ name: "a", role: "R", goal: "G" }.merge(attrs))
  end

  def forwarded_options(record)
    captured = nil
    allow(RCrewAI::Agent).to receive(:new).and_wrap_original do |original, **kwargs|
      captured = kwargs
      original.call(**kwargs)
    end
    record.to_rcrew_agent
    captured
  end

  it "is off by default and forwards nothing" do
    record = build_agent

    expect(record.require_approval_for_tools).to be false
    expect(forwarded_options(record)).not_to have_key(:require_approval_for_tools)
  end

  context "with an rcrewai that enforces approval", if: defined?(RCrewAI::ToolApproval) do
    it "forwards the setting to the core agent" do
      agent = build_agent(require_approval_for_tools: true).to_rcrew_agent

      expect(agent.require_approval_for_tools?).to be true
    end

    it "forwards it from the AgentBuilder DSL" do
      builder = Class.new do
        include RcrewAI::Rails::AgentBuilder
        require_approval_for_tools true
      end

      expect(builder.new(name: "b").to_agent.require_approval_for_tools?).to be true
    end

    it "keeps it on in subclasses of a builder that requires it" do
      base = Class.new do
        include RcrewAI::Rails::AgentBuilder
        require_approval_for_tools true
      end

      expect(Class.new(base).new(name: "b").to_agent.require_approval_for_tools?).to be true
    end

    it "lets an AgentBuilder instance turn it on" do
      builder = Class.new { include RcrewAI::Rails::AgentBuilder }

      expect(builder.new(name: "b", require_approval_for_tools: true).to_agent.require_approval_for_tools?).to be true
    end
  end

  context "with an rcrewai that would run tools without asking" do
    before { hide_const("RCrewAI::ToolApproval") if defined?(RCrewAI::ToolApproval) }

    it "refuses to build the agent" do
      record = build_agent(require_approval_for_tools: true)

      expect { record.to_rcrew_agent }.to raise_error(RcrewAI::Rails::UnsupportedOption, /rcrewai 0\.12/)
    end

    it "refuses to build it from the AgentBuilder DSL" do
      builder = Class.new { include RcrewAI::Rails::AgentBuilder }

      expect { builder.new(require_approval_for_tools: true) }.to raise_error(RcrewAI::Rails::UnsupportedOption)
    end

    it "still builds agents that don't ask for approval" do
      expect { build_agent.to_rcrew_agent }.not_to raise_error
    end
  end
end
