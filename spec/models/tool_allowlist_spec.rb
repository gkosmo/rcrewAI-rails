require "rails_helper"

class AllowlistSpecTool < RCrewAI::Tools::Base
  tool_name "allowlist_spec"
  description "d"
  attr_reader :opts

  def initialize(**opts)
    super()
    @opts = opts
  end

  def execute(**) = "ok"
end

# Would be dangerous to instantiate from a form field.
class AllowlistSpecDanger
  cattr_accessor :built, default: false
  def initialize(**) = self.class.built = true
end

RSpec.describe "tool class allowlist" do
  let(:config) { RcrewAI::Rails.config }
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "c") }
  let(:agent) { crew.agents.create!(name: "a", role: "r", goal: "g") }

  around do |example|
    previous = config.allowed_tool_classes
    example.run
  ensure
    config.allowed_tool_classes = previous
    AllowlistSpecDanger.built = false
  end

  describe RcrewAI::Rails::Tool do
    it "allows nothing by default" do
      config.allowed_tool_classes = RcrewAI::Rails::Configuration.new.allowed_tool_classes
      expect(agent.tools.build(name: "t", tool_class: "RCrewAI::Tools::WebSearch")).not_to be_valid
    end

    it "accepts an allowed class, as a class or a name" do
      config.allowed_tool_classes = [AllowlistSpecTool, "RCrewAI::Tools::WebSearch"]
      expect(agent.tools.build(name: "t", tool_class: "AllowlistSpecTool")).to be_valid
      expect(agent.tools.build(name: "t", tool_class: "RCrewAI::Tools::WebSearch")).to be_valid
    end

    it "rejects any other class without loading it" do
      config.allowed_tool_classes = [AllowlistSpecTool]
      tool = agent.tools.build(name: "t", tool_class: "AllowlistSpecDanger")

      expect(tool).not_to be_valid
      expect(tool.errors[:tool_class]).to be_present
      expect { tool.instantiated_tool }.to raise_error(RcrewAI::Rails::ToolAllowlist::NotAllowed)
      expect(AllowlistSpecDanger.built).to be(false)
    end

    it "refuses a row saved before the allowlist, or since removed from it" do
      config.allowed_tool_classes = [AllowlistSpecDanger]
      tool = agent.tools.create!(name: "t", tool_class: "AllowlistSpecDanger")
      config.allowed_tool_classes = []

      expect { tool.instantiated_tool }.to raise_error(RcrewAI::Rails::ToolAllowlist::NotAllowed)
      expect(AllowlistSpecDanger.built).to be(false)
    end

    it "builds an allowed tool with its config" do
      config.allowed_tool_classes = [AllowlistSpecTool]
      tool = agent.tools.create!(name: "t", tool_class: "AllowlistSpecTool", config: { "limit" => 3 })
      expect(tool.instantiated_tool.opts).to eq(limit: 3)
    end
  end

  describe RcrewAI::Rails::Agent do
    it "gives the core agent its configured tools" do
      config.allowed_tool_classes = [AllowlistSpecTool]
      agent.tools.create!(name: "t", tool_class: "AllowlistSpecTool")
      agent.tools.create!(name: "off", tool_class: "AllowlistSpecTool", active: false)

      expect(agent.to_rcrew_agent.tools.map(&:class)).to eq([AllowlistSpecTool])
    end

    it "refuses to build with a disallowed tool, rather than run without it" do
      config.allowed_tool_classes = [AllowlistSpecDanger]
      agent.tools.create!(name: "t", tool_class: "AllowlistSpecDanger")
      config.allowed_tool_classes = []

      expect { agent.to_rcrew_agent }.to raise_error(RcrewAI::Rails::ToolAllowlist::NotAllowed)
    end
  end

  describe RcrewAI::Rails::Task do
    it "refuses a disallowed class in its tools column" do
      task = crew.tasks.create!(description: "d", expected_output: "e", agent: agent,
                                tools: [{ "class" => "AllowlistSpecDanger", "params" => {} }])

      expect { task.instantiated_tools }.to raise_error(RcrewAI::Rails::ToolAllowlist::NotAllowed)
      expect(AllowlistSpecDanger.built).to be(false)
    end

    it "builds an allowed class in its tools column" do
      config.allowed_tool_classes = [AllowlistSpecTool]
      task = crew.tasks.create!(description: "d", expected_output: "e", agent: agent,
                                tools: [{ "class" => "AllowlistSpecTool", "params" => { "a" => 1 } }])

      expect(task.instantiated_tools.first.opts).to eq(a: 1)
    end
  end

  describe "the tools form", type: :request do
    it "does not save a disallowed class" do
      expect do
        post "/rcrewai/agents/#{agent.id}/tools", params: { tool: { name: "t", tool_class: "AllowlistSpecDanger" } }
      end.not_to(change(RcrewAI::Rails::Tool, :count))
    end
  end
end

RSpec.describe "MCP tools on an engine agent" do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "c") }
  let(:agent) { crew.agents.create!(name: "a", role: "r", goal: "g") }
  let(:config) { RcrewAI::Rails.config }

  after { config.agent_mcp_tools = nil }

  it "adds nothing by default" do
    expect(agent.to_rcrew_agent.tools).to eq([])
  end

  it "adds the tools the host returns for that agent" do
    mcp_tool = AllowlistSpecTool.new
    config.agent_mcp_tools = ->(record) { record.name == "a" ? [mcp_tool] : [] }

    expect(agent.to_rcrew_agent.tools).to eq([mcp_tool])
  end

  it "takes a connected MCP client and uses its tools" do
    mcp_tool = AllowlistSpecTool.new
    client = instance_double(RCrewAI::MCP::Client, tools: [mcp_tool])
    config.agent_mcp_tools = ->(_record) { [client] }

    expect(agent.to_rcrew_agent.tools).to eq([mcp_tool])
  end
end
