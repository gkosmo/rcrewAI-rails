require "rails_helper"

RSpec.describe RcrewAI::Rails::CrewExecutionJob, type: :job do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "C", process_type: "sequential") }

  before do
    # Stub the LLM provider so the gem's runner has something to call.
    fake_llm = double("LLMClient")
    allow(fake_llm).to receive(:chat).and_return(
      content: "FINAL_ANSWER[done]",
      finish_reason: :stop,
      usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 }
    )
    allow(fake_llm).to receive(:supports_native_tools?).and_return(false)
    allow(RCrewAI::LLMClient).to receive(:for_provider).and_return(fake_llm)
  end

  it "marks the execution completed and stores the gem's result hash on output" do
    agent = crew.agents.create!(name: "a", role: "Worker")
    crew.tasks.create!(description: "do it", expected_output: "ok", agent: agent)

    described_class.new.perform(crew)

    execution = crew.executions.order(:id).last
    expect(execution.status).to eq("completed")
    expect(execution.output).to include("total_tasks" => 1, "completed_tasks" => 1)
    expect(execution.execution_logs.where(level: "info")).to be_present
  end

  it "records the failure when the crew raises" do
    agent = crew.agents.create!(name: "a", role: "Worker")
    crew.tasks.create!(description: "do it", expected_output: "ok", agent: agent)
    allow_any_instance_of(RCrewAI::Crew).to receive(:execute).and_raise("boom")

    expect { described_class.new.perform(crew) }.to raise_error("boom")
    execution = crew.executions.order(:id).last
    expect(execution.status).to eq("failed")
    expect(execution.error_message).to eq("boom")
    expect(execution.execution_logs.where(level: "error")).to be_present
  end

  it "stamps batch_id on the execution when given one" do
    agent = crew.agents.create!(name: "a", role: "Worker")
    crew.tasks.create!(description: "do it", expected_output: "ok", agent: agent)

    described_class.new.perform(crew, {}, batch_id: "batch-xyz")

    execution = crew.executions.order(:id).last
    expect(execution.batch_id).to eq("batch-xyz")
  end

  it "leaves batch_id nil for a normal run" do
    agent = crew.agents.create!(name: "a", role: "Worker")
    crew.tasks.create!(description: "do it", expected_output: "ok", agent: agent)

    described_class.new.perform(crew)

    execution = crew.executions.order(:id).last
    expect(execution.batch_id).to be_nil
  end

  describe "observation" do
    def build_observable_crew(name)
      observed = RcrewAI::Rails::Crew.create!(name: name, process_type: "sequential")
      agent = observed.agents.create!(name: "writer", role: "Writer", goal: "Write", backstory: "A writer")
      observed.tasks.create!(description: "Write a line", expected_output: "A line", agent: agent)
      observed
    end

    it "nests spans into a single crew-rooted tree" do
      crew = build_observable_crew("nested")
      described_class.perform_now(crew, {})
      execution = crew.executions.order(:created_at).last

      roots = execution.spans.roots.to_a
      expect(roots.size).to eq(1)
      expect(roots.first.kind).to eq("crew")

      agent_span = roots.first.children.first
      expect(agent_span.kind).to eq("agent")
      expect(agent_span.name).to eq("writer")

      expect(agent_span.children.map(&:kind)).to include("llm_call")
    end

    it "attributes every non-root span to a parent" do
      crew = build_observable_crew("parented")
      described_class.perform_now(crew, {})
      execution = crew.executions.order(:created_at).last

      orphans = execution.spans.where(parent_span_id: nil).where.not(kind: "crew")
      expect(orphans).to be_empty
    end

    it "records spans for the execution" do
      crew = build_observable_crew("observed")
      described_class.perform_now(crew, {})
      execution = crew.executions.order(:created_at).last
      expect(execution.spans.count).to be > 0
    end

    it "writes no spans when observation is disabled" do
      allow(RcrewAI::Rails.config).to receive(:observation_enabled).and_return(false)
      crew = build_observable_crew("unobserved")
      described_class.perform_now(crew, {})
      expect(crew.executions.order(:created_at).last.spans.count).to eq(0)
    end

    it "leaves no spans running after the job finishes" do
      crew = build_observable_crew("closed")
      described_class.perform_now(crew, {})
      expect(crew.executions.order(:created_at).last.spans.running.count).to eq(0)
    end
  end
end
