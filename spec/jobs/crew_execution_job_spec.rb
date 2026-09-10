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

  describe "inputs" do
    it "forwards the execution inputs to the crew so before_kickoff hooks see them" do
      agent = crew.agents.create!(name: "a", role: "Worker")
      crew.tasks.create!(description: "do it", expected_output: "ok", agent: agent)

      seen = nil
      allow_any_instance_of(RCrewAI::Crew).to receive(:execute).and_wrap_original do |original, **kwargs|
        seen = kwargs[:inputs]
        original.call(**kwargs)
      end

      described_class.new.perform(crew, { "topic" => "ruby" })

      expect(seen).to eq({ "topic" => "ruby" })
    end
  end

  describe "checkpointing" do
    let(:crew) do
      RcrewAI::Rails::Crew.create!(name: "C", process_type: "sequential", checkpoint_enabled: true)
    end

    before do
      agent = crew.agents.create!(name: "a", role: "Worker")
      crew.tasks.create!(description: "first", expected_output: "ok", agent: agent)
      crew.tasks.create!(description: "second", expected_output: "ok", agent: agent)
    end

    it "persists a checkpoint and records the run id on the execution" do
      described_class.new.perform(crew)

      execution = crew.executions.order(:id).last
      expect(execution.run_id).to be_present

      checkpoint = RcrewAI::Rails::Checkpoint.find_by(run_id: execution.run_id)
      expect(checkpoint).to be_present
      expect(checkpoint.crew_name).to eq("C")
      expect(checkpoint.completed_task_names.size).to eq(2)
    end

    it "writes no checkpoint when the crew has not opted in" do
      crew.update!(checkpoint_enabled: false)

      described_class.new.perform(crew)

      expect(RcrewAI::Rails::Checkpoint.count).to eq(0)
      expect(crew.executions.order(:id).last.run_id).to be_nil
    end

    it "replays completed tasks on resume instead of re-executing them" do
      described_class.new.perform(crew)
      original = crew.executions.order(:id).last

      restored = nil
      allow_any_instance_of(RCrewAI::Crew).to receive(:resume).and_wrap_original do |original_method, *args, **kwargs|
        result = original_method.call(*args, **kwargs)
        restored = original_method.receiver.restored_task_names
        result
      end

      crew.resume_sync(original)

      expect(restored).to contain_exactly("task_1", "task_2")

      resumed = crew.executions.order(:id).last
      expect(resumed.parent_run_id).to eq(original.run_id)
      expect(resumed.run_id).to be_present
      expect(resumed.run_id).not_to eq(original.run_id)
      expect(resumed.status).to eq("completed")
    end

    it "links the resumed run to its parent so lineage walks the chain" do
      described_class.new.perform(crew)
      original = crew.executions.order(:id).last

      crew.resume_sync(original)
      resumed = crew.executions.order(:id).last

      store = RcrewAI::Rails::ActiveRecordCheckpointStore.new
      expect(RCrewAI::Checkpoint.lineage(store, resumed.run_id))
        .to eq([original.run_id, resumed.run_id])
    end

    it "exposes resumable executions and rejects a run with no id" do
      described_class.new.perform(crew)

      expect(crew.resumable_executions.pluck(:run_id).compact).to be_present
      expect { crew.resume_sync(nil) }.to raise_error(ArgumentError, /no checkpoint run id/)
    end
  end

  describe "checkpointing without the 0.8 migration" do
    let(:crew) do
      RcrewAI::Rails::Crew.create!(name: "C", process_type: "sequential", checkpoint_enabled: true)
    end

    before do
      agent = crew.agents.create!(name: "a", role: "Worker")
      crew.tasks.create!(description: "do it", expected_output: "ok", agent: agent)
      # Simulate an install that enabled checkpointing but never migrated.
      allow(RcrewAI::Rails::Checkpoint).to receive(:table_exists?).and_return(false)
    end

    it "raises a message naming the fix, before any task runs" do
      # The point of failing early: no LLM work is paid for first.
      expect_any_instance_of(RCrewAI::Crew).not_to receive(:execute)

      expect { described_class.new.perform(crew) }
        .to raise_error(described_class::CheckpointTableMissing, /rcrew_ai_rails:install:migrations/)
    end

    it "marks the execution failed rather than leaving it running" do
      expect { described_class.new.perform(crew) }.to raise_error(described_class::CheckpointTableMissing)

      expect(crew.executions.order(:id).last.status).to eq("failed")
    end

    it "does not raise when a custom store is configured instead" do
      RcrewAI::Rails.config.checkpoint_store = RCrewAI::Checkpoint::MemoryStore.new

      expect { described_class.new.perform(crew) }.not_to raise_error
      expect(crew.executions.order(:id).last.status).to eq("completed")
    ensure
      RcrewAI::Rails.config.checkpoint_store = nil
    end

    it "is unaffected when checkpointing is off" do
      crew.update!(checkpoint_enabled: false)

      expect { described_class.new.perform(crew) }.not_to raise_error
      expect(crew.executions.order(:id).last.status).to eq("completed")
    end
  end
end
