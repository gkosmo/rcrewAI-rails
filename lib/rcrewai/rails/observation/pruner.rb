# frozen_string_literal: true

module RcrewAI
  module Rails
    module Observation
      # Removes spans past the retention window. Without this the span
      # table becomes the largest in the host application's database.
      module Pruner
        module_function

        # Returns the number of spans removed. Deletes in batches so a
        # large backlog does not hold one enormous transaction open.
        #
        # Retention is applied per EXECUTION, not per span. Deleting spans
        # by their own age fractures mixed-age traces: a surviving child of
        # a deleted parent keeps a dangling parent_span_id, and because it
        # is neither a root nor reachable from any parent it disappears
        # from the trace view entirely. A trace is kept or dropped whole.
        def prune!(older_than_days: nil, batch_size: 1_000)
          days = older_than_days || RcrewAI::Rails.config.observation_retention_days
          cutoff = days.to_i.days.ago
          removed = 0

          loop do
            execution_ids = stale_execution_ids(cutoff, batch_size)
            break if execution_ids.empty?

            span_ids = Span.where(execution_id: execution_ids).pluck(:id)
            SpanEvent.where(span_id: span_ids).delete_all
            removed += Span.where(id: span_ids).delete_all
          end

          removed
        end

        # Executions whose newest span predates the cutoff. Grouping by
        # execution means a long-running trace straddling the boundary is
        # retained until all of it has aged out.
        def stale_execution_ids(cutoff, batch_size)
          Span.group(:execution_id)
              .having(Span.arel_table[:created_at].maximum.lt(cutoff))
              .limit(batch_size)
              .pluck(:execution_id)
        end
      end
    end
  end
end
