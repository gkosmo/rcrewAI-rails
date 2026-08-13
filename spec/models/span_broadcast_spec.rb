require "rails_helper"
require "rcrewai/rails/observation/writer"

RSpec.describe "span broadcasting" do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "c") }
  let(:execution) { crew.executions.create!(status: "running", started_at: Time.current) }

  def span_attrs(**overrides)
    { execution_id: execution.id, trace_id: "t", kind: "agent", name: "writer",
      status: "running", started_at: Time.current, sequence: 1 }.merge(overrides)
  end

  it "broadcasts when a span is created" do
    broadcasts = []
    writer = RcrewAI::Rails::Observation::Writer.new(
      mode: :immediate, on_span_change: ->(id) { broadcasts << id }
    )
    id = writer.create_span(span_attrs)
    expect(broadcasts).to eq([id])
  end

  it "broadcasts when a span completes via update_span" do
    broadcasts = []
    writer = RcrewAI::Rails::Observation::Writer.new(
      mode: :immediate, on_span_change: ->(id) { broadcasts << id }
    )
    id = writer.create_span(span_attrs)
    broadcasts.clear
    writer.update_span(id, status: "ok", ended_at: Time.current, duration_ms: 5)
    expect(broadcasts).to eq([id]),
      "update_span uses update_all and fires no AR callbacks; completion must broadcast explicitly"
  end

  it "does not raise when the broadcast callback itself fails" do
    writer = RcrewAI::Rails::Observation::Writer.new(
      mode: :immediate, on_span_change: ->(_id) { raise "broadcast boom" }
    )
    expect { writer.create_span(span_attrs) }.not_to raise_error
  end

  it "works with no callback configured" do
    writer = RcrewAI::Rails::Observation::Writer.new(mode: :immediate)
    expect { writer.create_span(span_attrs) }.not_to raise_error
  end
end
