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
end
