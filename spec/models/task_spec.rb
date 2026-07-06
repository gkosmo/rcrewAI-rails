require "rails_helper"

class GroupBTestGuardrail
  # Returns the core guardrail contract shape: [ok, value_or_error]
  def check(output)
    [true, output.to_s.upcase]
  end
end

RSpec.describe RcrewAI::Rails::Task, type: :model do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "C", process_type: "sequential") }
  let(:agent) { crew.agents.create!(name: "writer", role: "Writer") }

  describe "#to_rcrew_task" do
    it "synthesizes a name from the record id when no name column exists" do
      record = crew.tasks.create!(description: "Write the report", expected_output: "PDF", agent: agent)
      rcrew = record.to_rcrew_task
      expect(rcrew).to be_a(RCrewAI::Task)
      expect(rcrew.name).to eq("task_#{record.id}")
      expect(rcrew.description).to eq("Write the report")
      expect(rcrew.expected_output).to eq("PDF")
      expect(rcrew.agent).to be_a(RCrewAI::Agent)
    end

    it "maps async_execution to the gem's :async option" do
      sync   = crew.tasks.create!(description: "sync task",  expected_output: "out", agent: agent, async_execution: false)
      asyncr = crew.tasks.create!(description: "async task", expected_output: "out", agent: agent, async_execution: true)
      expect(sync.to_rcrew_task.async).to be false
      expect(asyncr.to_rcrew_task.async).to be true
    end

    it "passes through tools and context" do
      record = crew.tasks.create!(
        description: "log it",
        expected_output: "ok",
        agent: agent,
        context: ["task_1"],
        tools: [{ "class" => "RcrewAI::Rails::Tools::RailsLoggerTool", "params" => {} }]
      )
      rcrew = record.to_rcrew_task
      expect(rcrew.context).to eq(["task_1"])
      expect(rcrew.tools.first).to be_a(RcrewAI::Rails::Tools::RailsLoggerTool)
    end
  end

  describe "0.4/0.5 output-processing option forwarding" do
    let(:crew) { RcrewAI::Rails::Crew.create!(name: "C", process_type: "sequential") }

    def build_task(attrs = {})
      crew.tasks.create!({ description: "d", expected_output: "e" }.merge(attrs))
    end

    def capture_task_kwargs
      captured = nil
      allow(RCrewAI::Task).to receive(:new).and_wrap_original do |orig, **kwargs|
        captured = kwargs
        orig.call(**kwargs)
      end
      yield
      captured
    end

    it "forwards none of the new options for an all-default task" do
      captured = capture_task_kwargs { build_task.to_rcrew_task }

      expect(captured).not_to have_key(:output_schema)
      expect(captured).not_to have_key(:guardrail)
      expect(captured).not_to have_key(:guardrail_max_retries)
      expect(captured).not_to have_key(:output_file)
      expect(captured).not_to have_key(:markdown)
      expect(captured).not_to have_key(:attachments)
      expect(captured).not_to have_key(:create_directory)
    end

    it "forwards output_schema as a deep-symbolized hash" do
      schema = { "type" => "object", "properties" => { "name" => { "type" => "string" } } }
      captured = capture_task_kwargs { build_task(output_schema: schema).to_rcrew_task }

      expect(captured[:output_schema]).to eq(
        type: "object", properties: { name: { type: "string" } }
      )
    end

    it "resolves guardrail_class + guardrail_method_name to a working callable" do
      captured = capture_task_kwargs do
        build_task(guardrail_class: "GroupBTestGuardrail", guardrail_method_name: "check").to_rcrew_task
      end

      expect(captured[:guardrail]).to respond_to(:call)
      expect(captured[:guardrail].call("hi")).to eq([true, "HI"])
    end

    it "forwards guardrail_max_retries only when a guardrail class is set" do
      with_guardrail = capture_task_kwargs do
        build_task(
          guardrail_class: "GroupBTestGuardrail",
          guardrail_method_name: "check",
          guardrail_max_retries: 5
        ).to_rcrew_task
      end
      expect(with_guardrail[:guardrail_max_retries]).to eq(5)

      without_guardrail = capture_task_kwargs do
        build_task(guardrail_max_retries: 5).to_rcrew_task
      end
      expect(without_guardrail).not_to have_key(:guardrail_max_retries)
      expect(without_guardrail).not_to have_key(:guardrail)
    end

    it "forwards output_file, markdown, and create_directory" do
      captured = capture_task_kwargs do
        build_task(output_file: "/tmp/out.md", markdown: true, create_directory: false).to_rcrew_task
      end

      expect(captured[:output_file]).to eq("/tmp/out.md")
      expect(captured[:markdown]).to be true
      expect(captured[:create_directory]).to be false
    end

    it "forwards attachments with symbolized keys and a symbol :type" do
      captured = capture_task_kwargs do
        build_task(attachments: [{ "type" => "image", "url" => "http://x/y.png" }]).to_rcrew_task
      end

      expect(captured[:attachments]).to eq([{ type: :image, url: "http://x/y.png" }])
    end

    it "does not forward guardrail_max_retries when the guardrail method is missing" do
      captured = capture_task_kwargs do
        build_task(guardrail_class: "GroupBTestGuardrail", guardrail_max_retries: 5).to_rcrew_task
      end

      expect(captured).not_to have_key(:guardrail)
      expect(captured).not_to have_key(:guardrail_max_retries)
    end
  end
end
