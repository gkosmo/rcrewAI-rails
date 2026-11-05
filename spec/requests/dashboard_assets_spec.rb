require "rails_helper"

RSpec.describe "the dashboard's own assets", type: :request do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "c") }

  it "does not reference the host's application assets" do
    get "/rcrewai/crews"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to match(%r{(src|href)="[^"]*application[^"]*"})
  end

  it "links its own stylesheet and serves it" do
    get "/rcrewai/crews"
    href = response.body[%r{<link[^>]*rel="stylesheet"[^>]*href="([^"]+)"}, 1]
    expect(href).to start_with("/rcrewai/assets/")

    get href
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/css")
    expect(response.body).to include(".navbar")
  end

  it "links Turbo as a module and serves it, with cross-site forgery protection off for the script" do
    get "/rcrewai/crews"
    script = response.body[%r{<script[^>]*src="([^"]+)"[^>]*>}]
    expect(script).to include('type="module"')
    src = script[/src="([^"]+)"/, 1]
    expect(src).to start_with("/rcrewai/assets/")

    get src
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/javascript")
    expect(response.body).to include("turbo-cable-stream-source")
  end

  it "keeps the assets behind the auth hook" do
    RcrewAI::Rails.config.authenticate_with = ->(_controller) { false }
    get "/rcrewai/assets/dashboard.css"
    expect(response).to have_http_status(:forbidden)
  end

  it "renders a running execution on a host without Action Cable" do
    execution = crew.executions.create!(status: "running", started_at: Time.current)
    get "/rcrewai/executions/#{execution.id}"
    expect(response).to have_http_status(:ok)
  end

  describe "buttons that rely on JavaScript" do
    before { RcrewAI::Rails.config.allowed_tool_classes = ["RCrewAI::Tools::WebSearch"] }
    after { RcrewAI::Rails.config.allowed_tool_classes = [] }

    it "deletes a crew with a real form" do
      get "/rcrewai/crews/#{crew.id}"
      expect(response.body).to match(/name="_method"[^>]*value="delete"/)
    end

    it "asks Turbo to send a delete from links, since rails-ujs isn't loaded" do
      agent = crew.agents.create!(name: "a", role: "r", goal: "g")
      tool = agent.tools.create!(name: "t", tool_class: "RCrewAI::Tools::WebSearch")
      get "/rcrewai/agents/#{agent.id}/tools/#{tool.id}"
      expect(response.body).to include('data-turbo-method="delete"')
      expect(response.body).not_to include('data-method="delete"')
    end
  end

  # Every page, since nothing covered the views before.
  describe "every dashboard page renders" do
    let(:agent) { crew.agents.create!(name: "a", role: "r", goal: "g") }
    let(:task) { crew.tasks.create!(description: "d", expected_output: "e", agent: agent) }
    let(:tool) { agent.tools.create!(name: "t", tool_class: "RCrewAI::Tools::WebSearch") }
    let(:execution) { crew.executions.create!(status: "completed", started_at: Time.current) }

    before do
      RcrewAI::Rails.config.allowed_tool_classes = ["RCrewAI::Tools::WebSearch"]
      # Show the template error rather than a bare 500.
      @show_exceptions = Rails.application.env_config["action_dispatch.show_exceptions"]
      Rails.application.env_config["action_dispatch.show_exceptions"] = :none
    end

    after do
      RcrewAI::Rails.config.allowed_tool_classes = []
      Rails.application.env_config["action_dispatch.show_exceptions"] = @show_exceptions
    end

    {
      "root" => ->(_) { "/rcrewai" },
      "crews" => ->(_) { "/rcrewai/crews" },
      "new crew" => ->(_) { "/rcrewai/crews/new" },
      "crew" => ->(s) { "/rcrewai/crews/#{s.crew.id}" },
      "edit crew" => ->(s) { "/rcrewai/crews/#{s.crew.id}/edit" },
      "agents" => ->(s) { s.agent && "/rcrewai/agents" },
      "agent" => ->(s) { "/rcrewai/agents/#{s.agent.id}" },
      "new agent" => ->(s) { "/rcrewai/crews/#{s.crew.id}/agents/new" },
      "edit agent" => ->(s) { "/rcrewai/agents/#{s.agent.id}/edit" },
      "tasks" => ->(s) { s.task && "/rcrewai/tasks" },
      "task" => ->(s) { "/rcrewai/tasks/#{s.task.id}" },
      "new task" => ->(s) { "/rcrewai/crews/#{s.crew.id}/tasks/new" },
      "edit task" => ->(s) { "/rcrewai/tasks/#{s.task.id}/edit" },
      "tools" => ->(s) { s.tool && "/rcrewai/agents/#{s.agent.id}/tools" },
      "tool" => ->(s) { "/rcrewai/agents/#{s.agent.id}/tools/#{s.tool.id}" },
      "new tool" => ->(s) { "/rcrewai/agents/#{s.agent.id}/tools/new" },
      "edit tool" => ->(s) { "/rcrewai/agents/#{s.agent.id}/tools/#{s.tool.id}/edit" },
      "executions" => ->(s) { s.execution && "/rcrewai/executions" },
      "execution" => ->(s) { "/rcrewai/executions/#{s.execution.id}" },
      "observation" => ->(s) { "/rcrewai/executions/#{s.execution.id}/observation" },
      "costs" => ->(_) { "/rcrewai/observations/costs" }
    }.each do |name, path|
      it "renders #{name}" do
        get path.call(self)
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
