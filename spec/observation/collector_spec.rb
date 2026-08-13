require "rails_helper"
require "rcrewai/rails/observation/collector"

RSpec.describe RcrewAI::Rails::Observation::Collector do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "c") }
  let(:execution) { crew.executions.create!(status: "running", started_at: Time.current) }
  subject(:collector) { described_class.new(execution: execution) }

  def event(klass, **attrs)
    klass.new(type: klass.name.split("::").last.to_sym, timestamp: Time.now, **attrs)
  end

  describe "iterations" do
    it "opens an llm_call span on IterationStart" do
      collector.call(event(RCrewAI::Events::IterationStart, agent: "writer", iteration: 1, iteration_index: 1))
      span = execution.spans.llm_calls.first
      expect(span).to be_present
      expect(span.status).to eq("running")
    end

    it "closes the span on IterationEnd" do
      collector.call(event(RCrewAI::Events::IterationStart, agent: "writer", iteration: 1, iteration_index: 1))
      collector.call(event(RCrewAI::Events::IterationEnd, agent: "writer", iteration: 1, finish_reason: :stop))
      span = execution.spans.llm_calls.first
      expect(span.reload.status).to eq("ok")
      expect(span.attributes_hash["finish_reason"]).to eq("stop")
      expect(span.duration_ms).not_to be_nil
    end
  end

  describe "tool calls" do
    before do
      collector.call(event(RCrewAI::Events::IterationStart, agent: "writer", iteration: 1, iteration_index: 1))
    end

    it "opens a tool_call span nested under the current llm_call" do
      collector.call(event(RCrewAI::Events::ToolCallStart, agent: "writer", iteration: 1,
                           tool: "search", args: { q: "ruby" }, call_id: "c1"))
      tool_span = execution.spans.tool_calls.first
      llm_span  = execution.spans.llm_calls.first
      expect(tool_span.parent_span_id).to eq(llm_span.id)
      expect(tool_span.attributes_hash["args"]).to eq("q" => "ruby")
    end

    it "closes the matching span by call_id" do
      collector.call(event(RCrewAI::Events::ToolCallStart, agent: "writer", iteration: 1,
                           tool: "search", args: {}, call_id: "c1"))
      collector.call(event(RCrewAI::Events::ToolCallResult, agent: "writer", iteration: 1,
                           tool: "search", call_id: "c1", result: "found", duration_ms: 12))
      expect(execution.spans.tool_calls.first.reload.status).to eq("ok")
    end

    it "correlates correctly when tool calls interleave" do
      collector.call(event(RCrewAI::Events::ToolCallStart, agent: "writer", iteration: 1,
                           tool: "search", args: {}, call_id: "c1"))
      collector.call(event(RCrewAI::Events::ToolCallStart, agent: "writer", iteration: 1,
                           tool: "fetch", args: {}, call_id: "c2"))
      collector.call(event(RCrewAI::Events::ToolCallResult, agent: "writer", iteration: 1,
                           tool: "fetch", call_id: "c2", result: "ok", duration_ms: 5))

      by_name = execution.spans.tool_calls.index_by(&:name)
      expect(by_name["fetch"].reload.status).to eq("ok")
      expect(by_name["search"].reload.status).to eq("running")
    end

    it "marks a tool span errored on ToolCallError" do
      collector.call(event(RCrewAI::Events::ToolCallStart, agent: "writer", iteration: 1,
                           tool: "search", args: {}, call_id: "c1"))
      collector.call(event(RCrewAI::Events::ToolCallError, agent: "writer", iteration: 1,
                           tool: "search", call_id: "c1", error: "timeout"))
      span = execution.spans.tool_calls.first.reload
      expect(span.status).to eq("error")
      expect(span.attributes_hash["error"]).to eq("timeout")
    end

    it "ignores a result with no matching start" do
      expect do
        collector.call(event(RCrewAI::Events::ToolCallResult, agent: "writer", iteration: 1,
                             tool: "ghost", call_id: "nope", result: "x", duration_ms: 1))
      end.not_to raise_error
    end
  end

  describe "usage" do
    it "attaches tokens and cost to the enclosing llm_call span" do
      collector.call(event(RCrewAI::Events::IterationStart, agent: "writer", iteration: 1, iteration_index: 1))
      collector.call(event(RCrewAI::Events::Usage, agent: "writer", iteration: 1,
                           prompt_tokens: 100, completion_tokens: 50, total_tokens: 150, cost_usd: 0.0042))
      span = execution.spans.llm_calls.first.reload
      expect(span.total_tokens).to eq(150)
      expect(span.cost_usd.to_f).to be_within(0.000001).of(0.0042)
    end

    it "ignores usage with no open span" do
      expect do
        collector.call(event(RCrewAI::Events::Usage, agent: "ghost", iteration: 1,
                             prompt_tokens: 1, completion_tokens: 1, total_tokens: 2, cost_usd: 0.1))
      end.not_to raise_error
    end
  end

  describe "text capture" do
    before do
      collector.call(event(RCrewAI::Events::IterationStart, agent: "writer", iteration: 1, iteration_index: 1))
    end

    it "does not create a row per delta" do
      expect do
        3.times { collector.call(event(RCrewAI::Events::TextDelta, agent: "writer", iteration: 1, text: "x")) }
      end.not_to change(RcrewAI::Rails::Span, :count)
    end

    it "persists the final text on TextDone" do
      collector.call(event(RCrewAI::Events::TextDone, agent: "writer", iteration: 1, text: "hello world"))
      expect(execution.spans.llm_calls.first.reload.attributes_hash["text"]).to eq("hello world")
    end

    it "truncates text beyond the configured cap" do
      allow(RcrewAI::Rails.config).to receive(:observation_prompt_max_bytes).and_return(5)
      collector.call(event(RCrewAI::Events::TextDone, agent: "writer", iteration: 1, text: "abcdefghij"))
      expect(execution.spans.llm_calls.first.reload.attributes_hash["text"].bytesize).to be <= 5
    end

    it "stores no text when capture is disabled" do
      allow(RcrewAI::Rails.config).to receive(:observation_capture_prompts).and_return(:none)
      collector.call(event(RCrewAI::Events::TextDone, agent: "writer", iteration: 1, text: "secret"))
      expect(execution.spans.llm_calls.first.reload.attributes_hash).not_to have_key("text")
    end
  end

  describe "errors and lifecycle" do
    it "marks the current span errored on Error" do
      collector.call(event(RCrewAI::Events::IterationStart, agent: "writer", iteration: 1, iteration_index: 1))
      collector.call(event(RCrewAI::Events::Error, agent: "writer", iteration: 1, error: "boom"))
      expect(execution.spans.llm_calls.first.reload.status).to eq("error")
    end

    it "closes spans left open when the run finishes" do
      collector.call(event(RCrewAI::Events::IterationStart, agent: "writer", iteration: 1, iteration_index: 1))
      collector.finish!
      expect(execution.spans.running.count).to eq(0)
    end

    it "never raises on an unrecognised event" do
      expect { collector.call(Struct.new(:type).new(:mystery)) }.not_to raise_error
    end
  end

  describe "agent spans" do
    it "nests llm_calls under an explicitly opened agent span" do
      agent_span_id = collector.start_agent_span(agent_name: "writer")
      collector.call(event(RCrewAI::Events::IterationStart, agent: "writer", iteration: 1, iteration_index: 1))
      expect(execution.spans.llm_calls.first.parent_span_id).to eq(agent_span_id)
    end
  end
end
