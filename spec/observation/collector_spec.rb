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

    it "releases accumulated text buffers when the run finishes" do
      collector.call(event(RCrewAI::Events::IterationStart, agent: "writer", iteration: 1, iteration_index: 1))
      50.times { collector.call(event(RCrewAI::Events::TextDelta, agent: "writer", iteration: 1, text: "tok")) }
      collector.finish!
      buffers = collector.instance_variable_get(:@text_buffers)
      expect(buffers).to be_empty
    end
  end

  describe "multi-byte text" do
    before do
      collector.call(event(RCrewAI::Events::IterationStart, agent: "writer", iteration: 1, iteration_index: 1))
      allow(RcrewAI::Rails.config).to receive(:observation_prompt_max_bytes).and_return(5)
    end

    it "still stores text when the cap splits a multi-byte character" do
      collector.call(event(RCrewAI::Events::TextDone, agent: "writer", iteration: 1, text: "日本語テキスト"))
      attrs = execution.spans.llm_calls.first.reload.attributes_hash
      expect(attrs).to have_key("text")
      expect(attrs["text"]).to eq("日")
    end

    it "stores valid UTF-8 when the cap splits an emoji" do
      collector.call(event(RCrewAI::Events::TextDone, agent: "writer", iteration: 1, text: "abc🎉def"))
      text = execution.spans.llm_calls.first.reload.attributes_hash["text"]
      expect(text).to eq("abc")
      expect(text.valid_encoding?).to be(true)
    end
  end

  describe "text buffer fallback" do
    before do
      collector.call(event(RCrewAI::Events::IterationStart, agent: "writer", iteration: 1, iteration_index: 1))
    end

    it "falls back to accumulated deltas when TextDone carries no text" do
      %w[hel lo\  wor ld].each do |chunk|
        collector.call(event(RCrewAI::Events::TextDelta, agent: "writer", iteration: 1, text: chunk))
      end
      collector.call(event(RCrewAI::Events::TextDone, agent: "writer", iteration: 1, text: ""))
      expect(execution.spans.llm_calls.first.reload.attributes_hash["text"]).to eq("hello world")
    end

    it "prefers the event text when both are present" do
      collector.call(event(RCrewAI::Events::TextDelta, agent: "writer", iteration: 1, text: "partial"))
      collector.call(event(RCrewAI::Events::TextDone, agent: "writer", iteration: 1, text: "final"))
      expect(execution.spans.llm_calls.first.reload.attributes_hash["text"]).to eq("final")
    end
  end

  describe "agent spans" do
    it "nests llm_calls under an explicitly opened agent span" do
      agent_span_id = collector.start_agent_span(agent_name: "writer")
      collector.call(event(RCrewAI::Events::IterationStart, agent: "writer", iteration: 1, iteration_index: 1))
      expect(execution.spans.llm_calls.first.parent_span_id).to eq(agent_span_id)
    end
  end

  # rcrewai 0.8+ stamps every event with the id of the enclosing run span.
  describe "concurrent runs of the same agent (rcrewai 0.8 event hierarchy)" do
    let(:run_a) { SecureRandom.uuid }
    let(:run_b) { SecureRandom.uuid }

    it "nests each run's tool call under that run's own iteration" do
      collector.call(event(RCrewAI::Events::IterationStart, agent: "writer", iteration: 1,
                           iteration_index: 1, parent_id: run_a))
      collector.call(event(RCrewAI::Events::IterationStart, agent: "writer", iteration: 1,
                           iteration_index: 1, parent_id: run_b))

      # Run A's tool call arrives while run B's iteration is the most recent.
      collector.call(event(RCrewAI::Events::ToolCallStart, agent: "writer", iteration: 1,
                           tool: "search", args: {}, call_id: "c1", parent_id: run_a))

      llm_a, llm_b = execution.spans.llm_calls.order(:sequence).to_a
      tool = execution.spans.tool_calls.first

      expect(tool.parent_span_id).to eq(llm_a.id)
      expect(tool.parent_span_id).not_to eq(llm_b.id)
    end

    it "closes each run's iteration independently" do
      collector.call(event(RCrewAI::Events::IterationStart, agent: "writer", iteration: 1,
                           iteration_index: 1, parent_id: run_a))
      collector.call(event(RCrewAI::Events::IterationStart, agent: "writer", iteration: 1,
                           iteration_index: 1, parent_id: run_b))
      collector.call(event(RCrewAI::Events::IterationEnd, agent: "writer", iteration: 1,
                           finish_reason: :stop, parent_id: run_a))

      llm_a, llm_b = execution.spans.llm_calls.order(:sequence).to_a
      expect(llm_a.reload.status).to eq("ok")
      expect(llm_b.reload.status).to eq("running")
    end

    it "attributes usage to the emitting run" do
      collector.call(event(RCrewAI::Events::IterationStart, agent: "writer", iteration: 1,
                           iteration_index: 1, parent_id: run_a))
      collector.call(event(RCrewAI::Events::IterationStart, agent: "writer", iteration: 1,
                           iteration_index: 1, parent_id: run_b))
      collector.call(event(RCrewAI::Events::Usage, agent: "writer", iteration: 1,
                           prompt_tokens: 5, completion_tokens: 7, total_tokens: 12,
                           cost_usd: 0.01, parent_id: run_a))

      llm_a, llm_b = execution.spans.llm_calls.order(:sequence).to_a
      expect(llm_a.reload.total_tokens).to eq(12)
      expect(llm_b.reload.total_tokens).to be_nil
    end

    it "keeps buffered text separate per run" do
      collector.call(event(RCrewAI::Events::IterationStart, agent: "writer", iteration: 1,
                           iteration_index: 1, parent_id: run_a))
      collector.call(event(RCrewAI::Events::IterationStart, agent: "writer", iteration: 1,
                           iteration_index: 1, parent_id: run_b))
      collector.call(event(RCrewAI::Events::TextDelta, agent: "writer", iteration: 1,
                           text: "from-a", parent_id: run_a))
      collector.call(event(RCrewAI::Events::TextDone, agent: "writer", iteration: 1,
                           text: "", parent_id: run_a))

      llm_a, llm_b = execution.spans.llm_calls.order(:sequence).to_a
      expect(llm_a.reload.attributes_hash["text"]).to eq("from-a")
      expect(llm_b.reload.attributes_hash).not_to have_key("text")
    end

    # Streams from before the hierarchy existed carry no parent_id at all.
    it "still tracks a run whose events carry no parent_id" do
      collector.call(event(RCrewAI::Events::IterationStart, agent: "writer", iteration: 1,
                           iteration_index: 1))
      collector.call(event(RCrewAI::Events::ToolCallStart, agent: "writer", iteration: 1,
                           tool: "search", args: {}, call_id: "c9"))

      tool = execution.spans.tool_calls.first
      expect(tool.parent_span_id).to eq(execution.spans.llm_calls.first.id)
    end
  end

  # rcrewai 0.9 runs a turn's tool calls concurrently, emitting their events
  # from worker threads. The gem carries the run span across that boundary,
  # so the collector must still attribute them correctly.
  describe "concurrent tool calls in one turn (rcrewai 0.9)" do
    let(:run) { SecureRandom.uuid }

    it "nests every concurrent tool call under the same iteration" do
      collector.call(event(RCrewAI::Events::IterationStart, agent: "w", iteration: 1,
                           iteration_index: 1, parent_id: run))

      # Interleaved the way two worker threads would emit: both start, then
      # both finish out of order.
      collector.call(event(RCrewAI::Events::ToolCallStart, agent: "w", iteration: 1,
                           tool: "alpha", args: {}, call_id: "c1", parent_id: run))
      collector.call(event(RCrewAI::Events::ToolCallStart, agent: "w", iteration: 1,
                           tool: "beta", args: {}, call_id: "c2", parent_id: run))
      collector.call(event(RCrewAI::Events::ToolCallResult, agent: "w", iteration: 1,
                           tool: "beta", call_id: "c2", result: "b", duration_ms: 5, parent_id: run))
      collector.call(event(RCrewAI::Events::ToolCallResult, agent: "w", iteration: 1,
                           tool: "alpha", call_id: "c1", result: "a", duration_ms: 9, parent_id: run))

      llm = execution.spans.llm_calls.first
      tools = execution.spans.tool_calls.order(:sequence).to_a

      expect(tools.map(&:name)).to contain_exactly("alpha", "beta")
      expect(tools.map(&:parent_span_id).uniq).to eq([llm.id])
      # Each result lands on its own span, matched by call_id rather than order.
      expect(tools.map { |t| t.reload.attributes_hash["result"] }).to contain_exactly("a", "b")
      expect(tools.map { |t| t.reload.status }).to eq(%w[ok ok])
    end

    it "keeps a failing concurrent tool from affecting its sibling" do
      collector.call(event(RCrewAI::Events::IterationStart, agent: "w", iteration: 1,
                           iteration_index: 1, parent_id: run))
      collector.call(event(RCrewAI::Events::ToolCallStart, agent: "w", iteration: 1,
                           tool: "alpha", args: {}, call_id: "c1", parent_id: run))
      collector.call(event(RCrewAI::Events::ToolCallStart, agent: "w", iteration: 1,
                           tool: "beta", args: {}, call_id: "c2", parent_id: run))
      collector.call(event(RCrewAI::Events::ToolCallError, agent: "w", iteration: 1,
                           tool: "beta", call_id: "c2", error: "boom", parent_id: run))
      collector.call(event(RCrewAI::Events::ToolCallResult, agent: "w", iteration: 1,
                           tool: "alpha", call_id: "c1", result: "a", duration_ms: 3, parent_id: run))

      by_name = execution.spans.tool_calls.index_by(&:name)
      expect(by_name["beta"].reload.status).to eq("error")
      expect(by_name["alpha"].reload.status).to eq("ok")
    end

    # The collector is handed to the gem as a sink and, under 0.9, is reached
    # from worker threads. Events.fan_out serializes delivery, but the
    # collector must not corrupt its own state if called concurrently.
    it "survives concurrent delivery from multiple threads" do
      collector.call(event(RCrewAI::Events::IterationStart, agent: "w", iteration: 1,
                           iteration_index: 1, parent_id: run))

      threads = 8.times.map do |i|
        Thread.new do
          collector.call(event(RCrewAI::Events::ToolCallStart, agent: "w", iteration: 1,
                               tool: "t#{i}", args: {}, call_id: "call-#{i}", parent_id: run))
          collector.call(event(RCrewAI::Events::ToolCallResult, agent: "w", iteration: 1,
                               tool: "t#{i}", call_id: "call-#{i}", result: "r#{i}",
                               duration_ms: 1, parent_id: run))
        end
      end
      threads.each(&:join)

      tools = execution.spans.tool_calls
      expect(tools.count).to eq(8)
      expect(tools.map(&:status).uniq).to eq(["ok"])
      expect(tools.map(&:parent_span_id).uniq).to eq([execution.spans.llm_calls.first.id])
    end
  end
end
