require "rails_helper"

RSpec.describe RcrewAI::Rails::SpanEvent do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "c") }
  let(:execution) { crew.executions.create!(status: "running", started_at: Time.current) }
  let(:span) do
    RcrewAI::Rails::Span.create!(
      execution: execution, trace_id: "t1", kind: "agent",
      name: "writer", started_at: Time.current, sequence: 1
    )
  end

  it "records an event against a span" do
    event = span.span_events.create!(
      level: "warn", name: "guardrail_retry",
      details: { attempt: 2 }, timestamp: Time.current
    )
    expect(event.reload.details).to eq("attempt" => 2)
  end

  it "rejects an unknown level" do
    expect do
      span.span_events.create!(level: "nonsense", name: "x", timestamp: Time.current)
    end.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "exposes spans through the execution" do
    span
    expect(execution.spans).to eq([span])
  end

  it "destroys spans and their events with the execution" do
    span.span_events.create!(level: "info", name: "x", timestamp: Time.current)
    expect { execution.destroy }
      .to change(RcrewAI::Rails::Span, :count).by(-1)
      .and change(described_class, :count).by(-1)
  end
end
