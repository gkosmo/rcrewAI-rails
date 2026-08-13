require "rails_helper"
require "rcrewai/rails/observation/rollup"

RSpec.describe RcrewAI::Rails::Observation::Rollup do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "c") }
  let(:execution) { crew.executions.create!(status: "running", started_at: Time.current) }

  it "accumulates tokens and cost" do
    described_class.record_usage(execution, tokens: 100, cost: 0.01)
    described_class.record_usage(execution, tokens: 50, cost: 0.005)
    execution.reload
    expect(execution.total_tokens).to eq(150)
    expect(execution.total_cost_usd.to_f).to be_within(0.000001).of(0.015)
  end

  it "tolerates nil usage figures" do
    expect { described_class.record_usage(execution, tokens: nil, cost: nil) }.not_to raise_error
    expect(execution.reload.total_tokens).to eq(0)
  end

  it "counts spans and errors" do
    2.times { described_class.record_span(execution) }
    described_class.record_error(execution)
    execution.reload
    expect(execution.span_count).to eq(2)
    expect(execution.error_count).to eq(1)
  end

  it "rebuilds totals from the span tree" do
    RcrewAI::Rails::Span.create!(
      execution: execution, trace_id: "t", kind: "llm_call", name: "i1",
      status: "ok", started_at: Time.current, sequence: 1,
      total_tokens: 70, cost_usd: 0.007
    )
    RcrewAI::Rails::Span.create!(
      execution: execution, trace_id: "t", kind: "tool_call", name: "search",
      status: "error", started_at: Time.current, sequence: 2
    )

    described_class.rebuild!(execution)
    execution.reload
    expect(execution.total_tokens).to eq(70)
    expect(execution.span_count).to eq(2)
    expect(execution.error_count).to eq(1)
  end

  it "never raises when the execution row is gone" do
    id = execution.id
    execution.destroy
    ghost = RcrewAI::Rails::Execution.new(id: id)
    expect { described_class.record_span(ghost) }.not_to raise_error
  end
end
