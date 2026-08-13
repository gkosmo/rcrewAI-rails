# frozen_string_literal: true

module RcrewAI
  module Rails
    module Observation
      # In-memory bookkeeping for open spans. Holds no database state.
      #
      # Agents may run concurrently under AsyncExecutor, so every operation
      # is guarded by a mutex and spans are tracked per agent.
      class SpanStack
        # Bucket for events that arrive without an agent. rcrewai's LLM
        # clients emit Usage/TextDelta with a nil agent and rely on
        # ToolRunner#retag to fill it in; anything that slips through lands
        # here rather than silently merging with a real agent's stack.
        UNTAGGED = "__untagged__"

        def initialize
          @mutex = Mutex.new
          @sequence = 0
          @stacks = Hash.new { |h, k| h[k] = [] }
          @calls = {}
        end

        # Normalizes an agent key. Blank/nil agents share a single reserved
        # bucket that cannot collide with a real agent name.
        def self.key_for(agent)
          key = agent.to_s
          key.empty? ? UNTAGGED : key
        end

        def next_sequence
          @mutex.synchronize { @sequence += 1 }
        end

        def push(agent:, key:, id:)
          @mutex.synchronize { @stacks[self.class.key_for(agent)] << { key: key, id: id } }
          id
        end

        # Removes and returns the most recent span matching +key+ for +agent+.
        #
        # Reads use +fetch+ rather than +[]+: the default block auto-vivifies
        # on read, so querying unknown agents would retain a key forever.
        def pop(agent:, key:)
          @mutex.synchronize do
            stack = @stacks.fetch(self.class.key_for(agent), nil)
            next nil if stack.nil?

            index = stack.rindex { |frame| frame[:key] == key }
            next nil unless index

            stack.delete_at(index)[:id]
          end
        end

        def current(agent:)
          @mutex.synchronize { @stacks.fetch(self.class.key_for(agent), nil)&.last&.fetch(:id) }
        end

        def register_call(call_id:, span_id:)
          @mutex.synchronize { @calls[call_id] = span_id }
        end

        # Resolves and forgets a call id. Returns nil if never registered,
        # which happens when a result arrives without a matching start.
        def resolve_call(call_id:)
          @mutex.synchronize { @calls.delete(call_id) }
        end

        def open_span_ids
          @mutex.synchronize { @stacks.values.flatten.map { |f| f[:id] } }
        end
      end
    end
  end
end
