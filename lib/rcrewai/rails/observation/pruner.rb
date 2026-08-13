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
        def prune!(older_than_days: nil, batch_size: 1_000)
          days = older_than_days || RcrewAI::Rails.config.observation_retention_days
          cutoff = days.to_i.days.ago
          removed = 0

          loop do
            ids = Span.where(Span.arel_table[:created_at].lt(cutoff)).limit(batch_size).pluck(:id)
            break if ids.empty?

            SpanEvent.where(span_id: ids).delete_all
            removed += Span.where(id: ids).delete_all
          end

          removed
        end
      end
    end
  end
end
