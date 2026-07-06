require "rails_helper"

class GroupCBeforeHook
  def call(inputs)
    inputs.merge(seen: true)
  end
end

class GroupCAfterHook
  def call(result)
    "wrapped: #{result}"
  end
end

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

  describe "0.5.0 lifecycle + planning forwarding" do
    def build_crew(attrs = {})
      RcrewAI::Rails::Crew.create!({ name: "C", process_type: "sequential" }.merge(attrs))
    end

    it "forwards no planning options and registers no hooks for an all-default crew" do
      captured = nil
      allow(RCrewAI::Crew).to receive(:new).and_wrap_original do |orig, name, **kwargs|
        captured = kwargs
        orig.call(name, **kwargs)
      end

      crew = build_crew.to_rcrew

      expect(captured).not_to have_key(:planning)
      expect(captured).not_to have_key(:planning_llm)
      expect(crew.instance_variable_get(:@before_kickoff_hooks)).to be_empty
      expect(crew.instance_variable_get(:@after_kickoff_hooks)).to be_empty
    end

    it "forwards planning and planning_llm (as a symbol) when set" do
      captured = nil
      allow(RCrewAI::Crew).to receive(:new).and_wrap_original do |orig, name, **kwargs|
        captured = kwargs
        orig.call(name, **kwargs)
      end

      build_crew(planning: true, planning_llm: "anthropic").to_rcrew

      expect(captured[:planning]).to be true
      expect(captured[:planning_llm]).to eq(:anthropic)
    end

    it "registers a before_kickoff hook that calls through to the host class" do
      captured_block = nil
      allow_any_instance_of(RCrewAI::Crew).to receive(:before_kickoff) do |_crew, &blk|
        captured_block = blk
      end

      build_crew(before_kickoff_class: "GroupCBeforeHook", before_kickoff_method: "call").to_rcrew

      expect(captured_block).not_to be_nil
      expect(captured_block.call({ a: 1 })).to eq({ a: 1, seen: true })
    end

    it "registers an after_kickoff hook that calls through to the host class" do
      captured_block = nil
      allow_any_instance_of(RCrewAI::Crew).to receive(:after_kickoff) do |_crew, &blk|
        captured_block = blk
      end

      build_crew(after_kickoff_class: "GroupCAfterHook", after_kickoff_method: "call").to_rcrew

      expect(captured_block).not_to be_nil
      expect(captured_block.call("done")).to eq("wrapped: done")
    end

    it "does not register a hook when only the class is set (method blank)" do
      crew = build_crew(before_kickoff_class: "GroupCBeforeHook").to_rcrew

      expect(crew.instance_variable_get(:@before_kickoff_hooks)).to be_empty
    end

    it "does not register an after hook when only the class is set (method blank)" do
      crew = build_crew(after_kickoff_class: "GroupCAfterHook").to_rcrew

      expect(crew.instance_variable_get(:@after_kickoff_hooks)).to be_empty
    end
  end

  describe "batch execution" do
    let(:batch_crew) do
      c = RcrewAI::Rails::Crew.create!(name: "Batch", process_type: "sequential")
      agent = c.agents.create!(name: "a", role: "Worker")
      c.tasks.create!(description: "do it", expected_output: "ok", agent: agent)
      c
    end

    describe "#execute_batch_sync" do
      it "creates one completed execution per input, sharing a batch_id" do
        result = batch_crew.execute_batch_sync([{ topic: "a" }, { topic: "b" }])

        execs = batch_crew.executions.where(batch_id: result[:batch_id])
        expect(execs.count).to eq(2)
        expect(execs.pluck(:status).uniq).to eq(["completed"])
        expect(result[:batch_id]).to be_a(String)
        expect(result[:executions].length).to eq(2)
      end

      it "preserves each input on its own execution" do
        batch_crew.execute_batch_sync([{ "topic" => "a" }, { "topic" => "b" }])

        topics = batch_crew.executions.order(:created_at, :id).map { |e| e.inputs["topic"] }
        expect(topics).to eq(["a", "b"])
      end
    end

    describe "#batch_executions" do
      it "returns the executions for a batch ordered by created_at" do
        result = batch_crew.execute_batch_sync([{ topic: "a" }, { topic: "b" }])

        rows = batch_crew.batch_executions(result[:batch_id])
        expect(rows.map(&:batch_id).uniq).to eq([result[:batch_id]])
        expect(rows.count).to eq(2)
      end
    end

    describe "#execute_batch_async" do
      it "enqueues one job per input and returns a String batch_id" do
        ActiveJob::Base.queue_adapter = :test

        batch_id = nil
        expect {
          batch_id = batch_crew.execute_batch_async([{ topic: "a" }, { topic: "b" }])
        }.to have_enqueued_job(RcrewAI::Rails::CrewExecutionJob).twice

        expect(batch_id).to be_a(String)
      end
    end

    it "leaves batch_id nil for a normal execute_sync run" do
      batch_crew.execute_sync({ topic: "solo" })

      expect(batch_crew.executions.order(:created_at, :id).last.batch_id).to be_nil
    end
  end
end
