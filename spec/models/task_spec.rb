require "rails_helper"

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
end
