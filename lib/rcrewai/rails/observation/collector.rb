# frozen_string_literal: true

require "rcrewai/rails/observation/span_stack"
require "rcrewai/rails/observation/writer"
require "rcrewai/rails/observation/rollup"

module RcrewAI
  module Rails
    module Observation
      # Translates the flat RCrewAI event stream into a span tree.
      #
      # This is the only component that knows the rcrewai event vocabulary.
      # If that vocabulary changes, nothing outside this class moves.
      class Collector
        def initialize(execution:, writer: nil, trace_id: nil)
          @execution = execution
          @trace_id = trace_id || SecureRandom.uuid
          @stack = SpanStack.new
          @writer = writer || Writer.new(
            mode: config.observation_flush_mode,
            flush_every: config.observation_flush_every,
            on_span_change: method(:broadcast_span)
          )
          @agent_spans = {}
          @root_span_id = nil
          @text_buffers = Hash.new { |h, k| h[k] = +"" }
        end

        # The sink handed to crew.execute(stream:).
        def call(event)
          return unless config.observation_enabled

          case event
          when RCrewAI::Events::IterationStart then on_iteration_start(event)
          when RCrewAI::Events::IterationEnd   then on_iteration_end(event)
          when RCrewAI::Events::ToolCallStart  then on_tool_start(event)
          when RCrewAI::Events::ToolCallResult then on_tool_result(event)
          when RCrewAI::Events::ToolCallError  then on_tool_error(event)
          when RCrewAI::Events::Usage          then on_usage(event)
          when RCrewAI::Events::TextDelta      then on_text_delta(event)
          when RCrewAI::Events::TextDone       then on_text_done(event)
          when RCrewAI::Events::Thinking       then on_thinking(event)
          when RCrewAI::Events::Error          then on_error(event)
          end
        rescue StandardError => e
          warn_failure(e)
        end

        # Opens the run's root span. rcrewai emits no crew-level event, so
        # the engine opens this explicitly around its own dispatch.
        def start_crew_span(crew_name:)
          @root_span_id = open_span(kind: "crew", name: crew_name.to_s)
        end

        def finish_crew_span(status: "ok")
          id = @root_span_id
          @root_span_id = nil
          close_span(id, status: status) if id
        end

        # Agent and task spans have no corresponding events, so the engine
        # opens them explicitly around its own dispatch.
        def start_agent_span(agent_name:, parent_span_id: nil)
          key = SpanStack.key_for(agent_name)
          id = open_span(
            kind: "agent", name: agent_name.to_s,
            parent_span_id: parent_span_id || @root_span_id, agent: agent_name
          )
          @agent_spans[key] = id
          id
        end

        def finish_agent_span(agent_name:, status: "ok")
          id = @agent_spans.delete(SpanStack.key_for(agent_name))
          close_span(id, status: status) if id
        end

        # Closes every agent span opened lazily from the event stream. The
        # caller uses this on the success path; finish! closes whatever is
        # left as errored.
        def finish_open_agent_spans(status: "ok")
          @agent_spans.each_value { |id| close_span(id, status: status) }
          @agent_spans.clear
        end

        # Closes anything still open. Called when the run ends, so a crash
        # mid-span does not leave the tree permanently "running".
        def finish!
          @stack.open_span_ids.compact.each { |id| close_span(id, status: "error") }
          @agent_spans.each_value { |id| close_span(id, status: "error") }
          @agent_spans.clear
          # Close the root last: its children must be closed first so the
          # waterfall shows the run finishing after everything inside it.
          finish_crew_span(status: "error")
          # Deltas accumulate per agent and are normally freed by TextDone.
          # A stream that aborts mid-generation never sends one, so drop
          # anything left rather than retaining the whole generated text.
          @text_buffers.clear
          @writer.flush!
        end

        private

        def config
          RcrewAI::Rails.config
        end

        def on_iteration_start(event)
          id = open_span(
            kind: "llm_call", name: "iteration #{event.iteration_index}",
            parent_span_id: agent_span_for(event.agent), agent: event.agent
          )
          @stack.push(agent: event.agent, key: :iteration, id: id)
        end

        # Returns the agent span that events from +agent+ belong under,
        # opening one on first sight. rcrewai emits no AgentStart event, and
        # the agent named in the event stream is the *agent*, never the crew
        # — so the root span alone can never be the parent.
        def agent_span_for(agent)
          key = SpanStack.key_for(agent)
          @agent_spans[key] ||= open_span(
            kind: "agent", name: agent.to_s.empty? ? "(unattributed)" : agent.to_s,
            parent_span_id: @root_span_id, agent: agent
          )
        end

        def on_iteration_end(event)
          id = @stack.pop(agent: event.agent, key: :iteration)
          return unless id

          merge_attributes(id, "finish_reason" => event.finish_reason.to_s)
          close_span(id, status: "ok")
        end

        def on_tool_start(event)
          id = open_span(
            kind: "tool_call", name: event.tool.to_s,
            parent_span_id: @stack.current(agent: event.agent), agent: event.agent,
            attributes: { "args" => event.args }
          )
          @stack.register_call(call_id: event.call_id, span_id: id)
        end

        def on_tool_result(event)
          id = @stack.resolve_call(call_id: event.call_id)
          return unless id

          merge_attributes(id, "duration_ms" => event.duration_ms,
                               "result" => truncate(event.result.to_s))
          close_span(id, status: "ok")
        end

        def on_tool_error(event)
          id = @stack.resolve_call(call_id: event.call_id)
          return unless id

          merge_attributes(id, "error" => event.error.to_s)
          close_span(id, status: "error")
        end

        def on_usage(event)
          id = @stack.current(agent: event.agent)
          return unless id

          @writer.update_span(id,
                              prompt_tokens: event.prompt_tokens,
                              completion_tokens: event.completion_tokens,
                              total_tokens: event.total_tokens,
                              cost_usd: event.cost_usd)
          Rollup.record_usage(@execution, tokens: event.total_tokens, cost: event.cost_usd)
        end

        # Deltas are far too chatty to persist individually. They accumulate
        # in memory and are written once on TextDone.
        def on_text_delta(event)
          return if config.observation_capture_prompts == :none

          @text_buffers[SpanStack.key_for(event.agent)] << event.text.to_s
        end

        # Prefers the event's own text, falling back to the accumulated
        # deltas when the provider sends TextDone without a payload.
        def on_text_done(event)
          buffered = @text_buffers.delete(SpanStack.key_for(event.agent))
          return if config.observation_capture_prompts == :none

          id = @stack.current(agent: event.agent)
          return unless id

          text = event.text.to_s
          text = buffered.to_s if text.empty?
          merge_attributes(id, "text" => truncate(text))
        end

        def on_thinking(event)
          return if config.observation_capture_prompts == :none

          id = @stack.current(agent: event.agent)
          return unless id

          merge_attributes(id, "thinking" => truncate(event.text.to_s))
        end

        def on_error(event)
          id = @stack.current(agent: event.agent)
          return unless id

          merge_attributes(id, "error" => event.error.to_s)
          close_span(id, status: "error")
          Rollup.record_error(@execution)
        end

        def open_span(kind:, name:, parent_span_id: nil, agent: nil, attributes: {})
          attrs = attributes.dup
          attrs["agent"] = agent.to_s if agent
          @writer.create_span(
            execution_id: @execution.id,
            parent_span_id: parent_span_id,
            trace_id: @trace_id,
            kind: kind,
            name: name,
            status: "running",
            started_at: Time.current,
            sequence: @stack.next_sequence,
            attributes_json: JSON.generate(attrs),
            created_at: Time.current,
            updated_at: Time.current
          ).tap { |id| Rollup.record_span(@execution) if id }
        end

        def close_span(span_id, status:)
          span = Span.find_by(id: span_id)
          return unless span&.running?

          ended = Time.current
          @writer.update_span(span_id,
                              status: status,
                              ended_at: ended,
                              duration_ms: ((ended - span.started_at) * 1000).round)
        end

        def merge_attributes(span_id, hash)
          span = Span.find_by(id: span_id)
          return unless span

          @writer.update_span(span_id, attributes_json: JSON.generate(span.attributes_hash.merge(hash)))
        end

        # Truncates to a byte cap without splitting a multi-byte character.
        # A bare byteslice can leave an invalid UTF-8 tail, which makes
        # JSON.generate raise and costs us the whole attribute.
        def truncate(text)
          return text if config.observation_capture_prompts == :full

          max = config.observation_prompt_max_bytes
          return text if text.bytesize <= max

          text.byteslice(0, max).scrub("")
        end

        # Pushes a single span to anyone watching the live trace.
        #
        # This is driven from the writer rather than an ActiveRecord callback
        # on purpose: span completion is written with update_all, which fires
        # no callbacks, so an after_update_commit hook would show spans
        # starting and never finishing.
        def broadcast_span(span_id)
          return unless broadcastable?

          span = Span.find_by(id: span_id)
          return unless span

          ::Turbo::StreamsChannel.broadcast_replace_to(
            "rcrewai_execution_#{@execution.id}",
            target: "span-#{span_id}",
            partial: "rcrewai/rails/observations/span",
            locals: { span: span, children: {}, depth: 0 }
          )
        rescue StandardError => e
          warn_failure(e)
        end

        # `defined?(::Turbo::StreamsChannel)` is not enough on its own: in an
        # app without ActionCable the constant is registered but resolving it
        # raises, because Turbo::StreamsChannel subclasses ActionCable::Channel.
        # Checking ActionCable first keeps the no-cable case quiet instead of
        # logging a warning for every span.
        def broadcastable?
          defined?(::ActionCable) && defined?(::Turbo::StreamsChannel) ? true : false
        end

        def warn_failure(error)
          return unless defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger

          ::Rails.logger.warn("[rcrewai-rails] observation collector error: #{error.class}: #{error.message}")
        end
      end
    end
  end
end
