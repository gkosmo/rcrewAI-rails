# frozen_string_literal: true

module RcrewAI
  module Rails
    module Observation
      # Persists spans, isolating the crew run from any storage failure.
      #
      # Span creates always write through, because the collector needs the
      # id to nest children. Only span events are buffered in :batched mode.
      class Writer
        attr_reader :dropped_count

        def initialize(mode: :batched, flush_every: 25, logger: nil)
          @mode = mode
          @flush_every = flush_every
          @logger = logger
          @buffer = []
          @mutex = Mutex.new
          @dropped_count = 0
        end

        # Returns the span id, or nil if the write failed.
        def create_span(attrs)
          guard do
            span = Span.create!(attrs)
            span.id
          end
        end

        def update_span(span_id, attrs)
          guard do
            Span.where(id: span_id).update_all(attrs.merge(updated_at: Time.current))
            span_id
          end
        end

        # Span events carry no id that anything else references, so in
        # :batched mode they buffer and insert in bulk.
        def create_event(attrs)
          return guard { SpanEvent.create!(attrs).id } if @mode == :immediate

          should_flush = @mutex.synchronize do
            @buffer << attrs.merge(created_at: Time.current, updated_at: Time.current)
            @buffer.size >= @flush_every
          end
          flush! if should_flush
          nil
        end

        # Flushes buffered span events. Span creates are never buffered
        # (see create_span), so this only drains the event buffer.
        def flush!
          buffered = @mutex.synchronize { @buffer.slice!(0..-1) || [] }
          return if buffered.empty?

          guard { SpanEvent.insert_all(buffered) }
        end

        private

        # Any storage failure is counted and swallowed. Observation must
        # never break the execution it is observing.
        def guard
          yield
        rescue StandardError => e
          @mutex.synchronize { @dropped_count += 1 }
          @logger&.warn("[rcrewai-rails] observation write failed: #{e.class}: #{e.message}")
          nil
        end
      end
    end
  end
end
