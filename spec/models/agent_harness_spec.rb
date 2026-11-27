require "rails_helper"

RSpec.describe "harnesses on engine agents" do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "C", process_type: "sequential") }
  let(:record) { crew.agents.create!(name: "writer", role: "R", goal: "G") }

  after { RcrewAI::Rails.config.agent_harness = nil }

  def forwarded_options(agent_record)
    captured = nil
    allow(RCrewAI::Agent).to receive(:new).and_wrap_original do |original, **kwargs|
      captured = kwargs
      original.call(**kwargs)
    end
    agent_record.to_rcrew_agent
    captured
  end

  it "forwards nothing when config.agent_harness isn't set" do
    expect(forwarded_options(record)).not_to have_key(:harness)
  end

  context "with an rcrewai that has harnesses", if: defined?(RCrewAI::Harness) do
    let(:harness) { RCrewAI::Harness.new { allow :file_reader } }

    it "gives the agent the harness the host returns for its record" do
      seen = []
      RcrewAI::Rails.config.agent_harness = lambda do |agent_record|
        seen << agent_record
        harness
      end

      expect(record.to_rcrew_agent.harness).to equal(harness)
      expect(seen).to eq([record])
    end

    [nil, false].each do |none|
      it "adds no harness when the hook returns #{none.inspect}" do
        RcrewAI::Rails.config.agent_harness = ->(_) { none }

        expect(forwarded_options(record)).not_to have_key(:harness)
      end
    end

    it "doesn't build the agent when the hook raises" do
      RcrewAI::Rails.config.agent_harness = ->(_) { raise "no harness for you" }

      expect { record.to_rcrew_agent }.to raise_error("no harness for you")
    end

    it "doesn't build the agent when the hook returns something else" do
      RcrewAI::Rails.config.agent_harness = ->(_) { { allow: :all } }

      expect { record.to_rcrew_agent }.to raise_error(ArgumentError, /harness/i)
    end

    it "applies to the agents of a whole crew and of its tasks" do
      RcrewAI::Rails.config.agent_harness = ->(_) { harness }
      task = crew.tasks.create!(description: "d", expected_output: "e", agent: record)

      expect(crew.reload.to_rcrew.agents.map(&:harness)).to all(equal(harness))
      expect(task.to_rcrew_task.agent.harness).to equal(harness)
    end

    describe "AgentBuilder" do
      let(:other) { RCrewAI::Harness.new }

      def builder_class(&body)
        Class.new do
          include RcrewAI::Rails::AgentBuilder
          class_eval(&body) if body
        end
      end

      it "uses the class's harness" do
        shared = harness
        builder = builder_class { harness shared }

        expect(builder.new(name: "b").to_agent.harness).to equal(shared)
      end

      it "keeps it in subclasses" do
        shared = harness
        base = builder_class { harness shared }

        expect(Class.new(base).new(name: "b").to_agent.harness).to equal(shared)
      end

      it "doesn't let `harness false` in a subclass drop it" do
        shared = harness
        base = builder_class { harness shared }
        child = Class.new(base) { harness false }

        expect(child.new(name: "b").to_agent.harness).to equal(shared)
      end

      it "lets an instance pass its own, which replaces the class's" do
        shared = harness
        builder = builder_class { harness shared }

        expect(builder.new(name: "b", harness: other).to_agent.harness).to equal(other)
      end

      it "keeps the class's when the instance passes nil" do
        shared = harness
        builder = builder_class { harness shared }

        expect(builder.new(name: "b", harness: nil).to_agent.harness).to equal(shared)
      end

      it "has none by default, even with config.agent_harness set" do
        RcrewAI::Rails.config.agent_harness = ->(_) { harness }

        expect(builder_class.new(name: "b").to_agent.harness).to be_nil
      end
    end
  end

  # Core before the harness ignores a harness: option, which would leave every
  # tool unchecked.
  context "with an rcrewai that has no harnesses" do
    before { hide_const("RCrewAI::Harness") if defined?(RCrewAI::Harness) }

    it "refuses to build a record's agent when config.agent_harness is set" do
      RcrewAI::Rails.config.agent_harness = ->(_) { Object.new }

      expect { record.to_rcrew_agent }.to raise_error(RcrewAI::Rails::UnsupportedOption, /harness/)
    end

    it "refuses to build an AgentBuilder agent given a harness" do
      builder = Class.new { include RcrewAI::Rails::AgentBuilder }

      expect { builder.new(harness: Object.new) }.to raise_error(RcrewAI::Rails::UnsupportedOption, /harness/)
    end

    it "builds agents that don't ask for one" do
      expect { record.to_rcrew_agent }.not_to raise_error
    end
  end
end
