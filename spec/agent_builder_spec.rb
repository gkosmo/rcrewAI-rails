require "spec_helper"
require "support/rails_stubs"
require "rcrewai/rails/agent_builder"

RSpec.describe RcrewAI::Rails::AgentBuilder do
  # Stub the LLM provider lookup so we don't reach out for real keys.
  let(:stub_llm) do
    Class.new do
      def chat(messages:, tools: nil, tool_choice: :auto, stream: nil, **_)
        { content: "FINAL_ANSWER[ok]", finish_reason: :stop,
          usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 } }
      end
      def supports_native_tools?(model: nil); false; end
    end.new
  end

  before do
    allow(RCrewAI::LLMClient).to receive(:for_provider).and_return(stub_llm)
    Rails.env = Class.new { def development?; false; end }.new unless Rails.env
  end

  context "when included in a class with class-level DSL" do
    let(:builder_class) do
      stub_const("DataAnalystAgent", Class.new do
        include RcrewAI::Rails::AgentBuilder

        agent_role "Data Analyst"
        agent_goal "Analyze app data"
        agent_backstory "Backstory"
        max_iterations 7
      end)
    end

    it "derives the rcrew agent name from the class name" do
      agent = builder_class.new.to_rcrew_agent
      expect(agent).to be_a(RCrewAI::Agent)
      expect(agent.name).to eq("data_analyst_agent")
      expect(agent.role).to eq("Data Analyst")
      expect(agent.goal).to eq("Analyze app data")
      expect(agent.max_iterations).to eq(7)
    end

    it "lets per-instance attributes override class-level DSL" do
      agent = builder_class.new(name: "custom", role: "Override", max_iterations: 3).to_rcrew_agent
      expect(agent.name).to eq("custom")
      expect(agent.role).to eq("Override")
      expect(agent.max_iterations).to eq(3)
    end

    it "passes tools through the constructor (not via a writer)" do
      builder_class.tools(RCrewAI::Tools::WebSearch)
      agent = builder_class.new.to_rcrew_agent
      expect(agent.tools.first).to be_a(RCrewAI::Tools::WebSearch)
    end
  end

  it "falls back to a generic name when the including class is anonymous" do
    klass = Class.new { include RcrewAI::Rails::AgentBuilder }
    agent = klass.new.to_rcrew_agent
    expect(agent.name).to eq("agent")
  end
end
