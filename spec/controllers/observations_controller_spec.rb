require "rails_helper"

RSpec.describe RcrewAI::Rails::ObservationsController, type: :request do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "c") }
  let(:execution) { crew.executions.create!(status: "completed", started_at: Time.current) }

  def create_span(**attrs)
    RcrewAI::Rails::Span.create!(
      { execution: execution, trace_id: "t", kind: "agent", name: "writer",
        status: "ok", started_at: Time.current, sequence: 1 }.merge(attrs)
    )
  end

  describe "GET /rcrewai/executions/:execution_id/observation" do
    it "renders the trace" do
      create_span
      get "/rcrewai/executions/#{execution.id}/observation"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("writer")
    end

    it "renders nested spans" do
      parent = create_span(name: "parent", kind: "crew", sequence: 1)
      create_span(name: "child", kind: "llm_call", sequence: 2, parent_span_id: parent.id)
      get "/rcrewai/executions/#{execution.id}/observation"
      expect(response.body).to include("parent").and include("child")
    end

    it "renders an execution with no spans" do
      get "/rcrewai/executions/#{execution.id}/observation"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /rcrewai/observations/costs" do
    it "renders cost totals from the rollups" do
      execution.update!(total_cost_usd: 1.25, total_tokens: 5000, span_count: 3)
      get "/rcrewai/observations/costs"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("1.25")
    end
  end
end
