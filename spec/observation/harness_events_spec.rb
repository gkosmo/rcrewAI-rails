require "rails_helper"
require "rcrewai/rails/observation/collector"

RSpec.describe "traces of harness decisions" do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "c") }
  let(:execution) { crew.executions.create!(status: "running", started_at: Time.current) }
  let(:collector) { RcrewAI::Rails::Observation::Collector.new(execution: execution) }

  # An engine agent running a real tool through a scripted model, traced.
  context "with an rcrewai that has harnesses", if: defined?(RCrewAI::Harness) do
    let(:tool_class) do
      Class.new(RCrewAI::Tools::Base) do
        tool_name "note_writer"
        description "writes a note"
        param :text, type: :string, required: true

        def execute(text:)
          "wrote #{text}"
        end
      end
    end

    after do
      RcrewAI::Rails.config.agent_harness = nil
      RcrewAI::Rails.config.agent_mcp_tools = nil
    end

    def run_agent(harness, native:, text: "hello")
      writer = tool_class.new
      RcrewAI::Rails.config.agent_mcp_tools = ->(_) { [writer] }
      RcrewAI::Rails.config.agent_harness = ->(_) { harness }
      record = crew.agents.create!(name: "writer", role: "R", goal: "G")
      call = if native
               { content: nil, finish_reason: :tool_calls, usage: {},
                 tool_calls: [{ id: "c1", name: "note_writer", arguments: { "text" => text } }] }
             else
               { content: "USE_TOOL[note_writer](text=#{text})", finish_reason: :stop, usage: {}, tool_calls: [] }
             end
      replies = [call]
      llm = double("LLM", supports_native_tools?: native)
      allow(llm).to receive(:chat) do |**|
        replies.shift || { content: "FINAL_ANSWER[done]", finish_reason: :stop, usage: {}, tool_calls: [] }
      end
      agent = record.to_rcrew_agent
      agent.instance_variable_set(:@llm_client, llm)
      agent.execute_task(RCrewAI::Task.new(name: "t", description: "d", agent: agent), stream: collector)
      collector.finish!
      execution.spans.tool_calls.sole
    end

    [true, false].each do |native|
      context "on the #{native ? 'native' : 'legacy'} runner" do
        it "records which rule blocked a call and why" do
          harness = RCrewAI::Harness.new { block :note_writer, reason: "Read only." }

          span = run_agent(harness, native: native)

          expect(span.status).to eq("error")
          expect(span.attributes_hash).to include("blocked_by" => "rule", "blocked_reason" => "Read only.")
        end

        it "records a before hook that failed and blocked the call" do
          harness = RCrewAI::Harness.new(default: :allow) { before(:note_writer) { raise IOError, "boom" } }

          span = run_agent(harness, native: native)

          expect(span.attributes_hash["blocked_by"]).to eq("hook")
          expect(span.attributes_hash["hook_failures"]).to match(
            [a_hash_including("hook" => "before(note_writer) #1", "phase" => "before",
                              "error" => a_string_including("boom"))]
          )
        end

        it "keeps a call successful when an after hook failed, and records each failure" do
          harness = RCrewAI::Harness.new(default: :allow) do
            after(:note_writer) { raise IOError, "first" }
            after(:note_writer) { raise IOError, "second" }
          end

          span = run_agent(harness, native: native)

          expect(span.status).to eq("ok")
          expect(span.attributes_hash["hook_failures"].map { |f| f["hook"] })
            .to eq(["after(note_writer) #1", "after(note_writer) #2"])
        end
      end
    end

    it "caps a long failure message like other captured text" do
      harness = RCrewAI::Harness.new(default: :allow) { after(:note_writer) { raise "x" * 20_000 } }

      span = run_agent(harness, native: true)

      expect(span.attributes_hash["hook_failures"].first["error"].bytesize)
        .to be <= RcrewAI::Rails.config.observation_prompt_max_bytes
    end
  end

  # Naming an event class the installed core lacks would raise inside the
  # collector, which swallows it: every later kind of event would be lost.
  it "still records other events when the core has no harness events" do
    %w[ToolBlocked ToolHookFailed].each do |name|
      hide_const("RCrewAI::Events::#{name}") if RCrewAI::Events.const_defined?(name)
    end

    collector.call(RCrewAI::Events::Error.new(type: :error, timestamp: Time.now, agent: "writer", error: "x"))
    collector.call(RCrewAI::Events::IterationStart.new(type: :iteration_start, timestamp: Time.now,
                                                       agent: "writer", iteration: 1, iteration_index: 1))
    usage = RCrewAI::Events::Usage.new(type: :usage, timestamp: Time.now, agent: "writer", iteration: 1,
                                       prompt_tokens: 1, completion_tokens: 1, total_tokens: 2)
    collector.call(usage)

    expect(execution.spans.llm_calls.sole.total_tokens).to eq(2)
  end
end
