require "spec_helper"
require "rcrewai/rails/observation/span_stack"

RSpec.describe RcrewAI::Rails::Observation::SpanStack do
  subject(:stack) { described_class.new }

  it "hands out monotonically increasing sequence numbers" do
    expect([stack.next_sequence, stack.next_sequence, stack.next_sequence]).to eq([1, 2, 3])
  end

  it "tracks the current span for an agent" do
    stack.push(agent: "writer", key: :iteration, id: 10)
    expect(stack.current(agent: "writer")).to eq(10)
  end

  it "isolates spans between agents" do
    stack.push(agent: "writer", key: :iteration, id: 10)
    stack.push(agent: "editor", key: :iteration, id: 20)
    expect(stack.current(agent: "writer")).to eq(10)
    expect(stack.current(agent: "editor")).to eq(20)
  end

  it "returns nil for an agent with no open span" do
    expect(stack.current(agent: "ghost")).to be_nil
  end

  it "pops the most recent span for an agent" do
    stack.push(agent: "writer", key: :agent, id: 1)
    stack.push(agent: "writer", key: :iteration, id: 2)
    expect(stack.pop(agent: "writer", key: :iteration)).to eq(2)
    expect(stack.current(agent: "writer")).to eq(1)
  end

  it "correlates tool calls by call_id" do
    stack.register_call(call_id: "abc", span_id: 42)
    expect(stack.resolve_call(call_id: "abc")).to eq(42)
  end

  it "forgets a call id once resolved" do
    stack.register_call(call_id: "abc", span_id: 42)
    stack.resolve_call(call_id: "abc")
    expect(stack.resolve_call(call_id: "abc")).to be_nil
  end

  it "returns nil for an unknown call id" do
    expect(stack.resolve_call(call_id: "never-seen")).to be_nil
  end

  it "reports all open span ids for orphan cleanup" do
    stack.push(agent: "writer", key: :agent, id: 1)
    stack.push(agent: "editor", key: :iteration, id: 2)
    expect(stack.open_span_ids).to match_array([1, 2])
  end

  it "is safe under concurrent access" do
    threads = 10.times.map do |i|
      Thread.new do
        50.times { stack.push(agent: "a#{i}", key: :iteration, id: stack.next_sequence) }
      end
    end
    threads.each(&:join)
    expect(stack.next_sequence).to eq(501)
  end
end
