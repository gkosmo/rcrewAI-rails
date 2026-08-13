require "rails_helper"
require "rcrewai/rails/observation/pruner"

RSpec.describe RcrewAI::Rails::Observation::Pruner do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "c") }
  let(:execution) { crew.executions.create!(status: "completed", started_at: Time.current) }

  def span_at(time, on: execution, **attrs)
    RcrewAI::Rails::Span.create!(
      { execution: on, trace_id: "t", kind: "agent", name: "a",
        status: "ok", started_at: time, sequence: 1, created_at: time }.merge(attrs)
    )
  end

  def other_execution
    @other_execution ||= crew.executions.create!(status: "completed", started_at: Time.current)
  end

  it "removes spans older than the retention window" do
    old = span_at(40.days.ago)
    span_at(1.day.ago, on: other_execution)
    described_class.prune!(older_than_days: 30)
    expect(RcrewAI::Rails::Span.exists?(old.id)).to be(false)
    expect(RcrewAI::Rails::Span.count).to eq(1)
  end

  it "keeps a whole trace whose newest span is inside the window" do
    parent = span_at(40.days.ago, kind: "crew", name: "old-root")
    child  = span_at(1.day.ago, parent_span_id: parent.id, sequence: 2)

    described_class.prune!(older_than_days: 30)

    expect(RcrewAI::Rails::Span.exists?(parent.id)).to be(true),
                                                      "pruning must not delete a parent whose subtree is still current"
    expect(child.reload.parent).to eq(parent)
  end

  it "never leaves a span pointing at a deleted parent" do
    parent = span_at(40.days.ago, kind: "crew", name: "root")
    span_at(35.days.ago, parent_span_id: parent.id, sequence: 2)

    described_class.prune!(older_than_days: 30)

    surviving = RcrewAI::Rails::Span.all
    dangling = surviving.reject do |span|
      span.parent_span_id.nil? || RcrewAI::Rails::Span.exists?(span.parent_span_id)
    end
    expect(dangling).to be_empty
  end

  it "removes the events belonging to pruned spans" do
    old = span_at(40.days.ago)
    old.span_events.create!(level: "info", name: "x", timestamp: 40.days.ago)
    expect { described_class.prune!(older_than_days: 30) }
      .to change(RcrewAI::Rails::SpanEvent, :count).by(-1)
  end

  it "reports how many spans it removed" do
    span_at(40.days.ago)
    expect(described_class.prune!(older_than_days: 30)).to eq(1)
  end

  it "defaults to the configured retention window" do
    allow(RcrewAI::Rails.config).to receive(:observation_retention_days).and_return(10)
    span_at(20.days.ago)
    expect(described_class.prune!).to eq(1)
  end
end
