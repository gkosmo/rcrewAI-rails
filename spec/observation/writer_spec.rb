require "rails_helper"
require "rcrewai/rails/observation/writer"

RSpec.describe RcrewAI::Rails::Observation::Writer do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "c") }
  let(:execution) { crew.executions.create!(status: "running", started_at: Time.current) }

  def span_attrs(sequence:, **overrides)
    { execution_id: execution.id, trace_id: "t1", kind: "agent", name: "writer",
      status: "running", started_at: Time.current, sequence: sequence }.merge(overrides)
  end

  describe "immediate mode" do
    subject(:writer) { described_class.new(mode: :immediate) }

    it "writes a span straight away and returns its id" do
      id = writer.create_span(span_attrs(sequence: 1))
      expect(RcrewAI::Rails::Span.find(id)).to be_present
    end

    it "applies updates immediately" do
      id = writer.create_span(span_attrs(sequence: 1))
      writer.update_span(id, status: "ok")
      expect(RcrewAI::Rails::Span.find(id).status).to eq("ok")
    end
  end

  describe "batched mode" do
    subject(:writer) { described_class.new(mode: :batched, flush_every: 3) }

    it "flushes automatically once the buffer fills" do
      3.times { |i| writer.create_span(span_attrs(sequence: i + 1)) }
      expect(RcrewAI::Rails::Span.count).to eq(3)
    end

    it "writes everything buffered on an explicit flush" do
      2.times { |i| writer.create_span(span_attrs(sequence: i + 1)) }
      writer.flush!
      expect(RcrewAI::Rails::Span.count).to eq(2)
    end
  end

  describe "error isolation" do
    subject(:writer) { described_class.new(mode: :immediate) }

    it "never raises when a write fails" do
      allow(RcrewAI::Rails::Span).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "boom")
      expect { writer.create_span(span_attrs(sequence: 1)) }.not_to raise_error
    end

    it "never raises when an update targets a missing span" do
      expect { writer.update_span(999_999, status: "ok") }.not_to raise_error
    end

    it "records that a failure happened" do
      allow(RcrewAI::Rails::Span).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "boom")
      writer.create_span(span_attrs(sequence: 1))
      expect(writer.dropped_count).to eq(1)
    end
  end
end
