require "rails_helper"

RSpec.describe RcrewAI::Rails::Span do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "c") }
  let(:execution) { crew.executions.create!(status: "running", started_at: Time.current) }

  def build_span(**attrs)
    described_class.create!(
      { execution: execution, trace_id: "t1", kind: "agent",
        name: "writer", started_at: Time.current, sequence: 1 }.merge(attrs)
    )
  end

  it "defaults to running status" do
    expect(build_span.status).to eq("running")
  end

  it "rejects an unknown kind" do
    expect { build_span(kind: "nonsense") }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "stores and reads attributes as a hash" do
    span = build_span(attributes_hash: { model: "gpt-4", temperature: 0.7 })
    expect(span.reload.attributes_hash).to eq("model" => "gpt-4", "temperature" => 0.7)
  end

  it "returns an empty hash when attributes are absent" do
    expect(build_span.attributes_hash).to eq({})
  end

  it "computes duration_ms on finish" do
    started = Time.current
    span = build_span(started_at: started)
    span.finish!(status: "ok", ended_at: started + 1.5)
    expect(span.duration_ms).to eq(1500)
    expect(span.status).to eq("ok")
  end

  it "nests children under parents" do
    parent = build_span(kind: "agent", sequence: 1)
    child  = build_span(kind: "llm_call", sequence: 2, parent_span_id: parent.id)
    expect(parent.children).to eq([child])
    expect(child.parent).to eq(parent)
  end

  it "orders roots by sequence" do
    b = build_span(sequence: 2, name: "b")
    a = build_span(sequence: 1, name: "a")
    expect(execution.spans.roots.to_a).to eq([a, b])
  end
end
