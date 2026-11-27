require "rails_helper"

RSpec.describe "setting tool approval from the dashboard", type: :request do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "C", process_type: "sequential") }
  let(:record) { crew.agents.create!(name: "a", role: "R", goal: "G") }

  it "offers a checkbox on the new and edit forms" do
    ["/rcrewai/agents/new", "/rcrewai/agents/#{record.id}/edit"].each do |path|
      get path

      expect(response.body).to include("agent[require_approval_for_tools]"), path
    end
  end

  it "saves it" do
    patch "/rcrewai/agents/#{record.id}", params: { agent: { require_approval_for_tools: "1" } }

    expect(record.reload.require_approval_for_tools).to be true
  end

  it "shows it on the agent page" do
    record.update!(require_approval_for_tools: true)

    get "/rcrewai/agents/#{record.id}"

    expect(response.body).to include("Tool Approval")
  end
end
