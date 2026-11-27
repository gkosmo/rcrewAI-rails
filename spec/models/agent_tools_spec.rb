require "rails_helper"

RSpec.describe RcrewAI::Rails::Agent, "#add_tool and #remove_tool" do
  let(:record) do
    RcrewAI::Rails::Crew.create!(name: "C", process_type: "sequential").agents.create!(name: "a", role: "R", goal: "G")
  end

  before do
    stub_const("EchoTool", Class.new)
    RcrewAI::Rails.config.allowed_tool_classes = ["EchoTool"]
  end

  after { RcrewAI::Rails.config.allowed_tool_classes = [] }

  it "adds a tool record with its params" do
    expect(record.add_tool(EchoTool, "limit" => 3)).to be true

    tool = record.tools.reload.sole
    expect([tool.name, tool.tool_class, tool.config]).to eq(["EchoTool", "EchoTool", { "limit" => 3 }])
  end

  it "returns false for a class the host hasn't allowed" do
    expect(record.add_tool("Kernel")).to be false
    expect(record.tools.reload).to be_empty
  end

  it "removes the tools of one class" do
    record.add_tool(EchoTool)

    record.remove_tool(EchoTool)

    expect(record.tools.reload).to be_empty
  end
end
