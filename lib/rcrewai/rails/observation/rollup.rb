# frozen_string_literal: true

module RcrewAI
  module Rails
    module Observation
      # Denormalized totals on Execution. The span tree is the source of
      # truth; these are a cache so cost/performance views never walk it.
      #
      # Counters use atomic SQL updates because agents run concurrently.
      module Rollup
        module_function

        def record_usage(execution, tokens:, cost:)
          guard do
            scope(execution).update_all([
              "total_tokens = COALESCE(total_tokens, 0) + ?, " \
              "total_cost_usd = COALESCE(total_cost_usd, 0) + ?",
              tokens.to_i, cost.to_f
            ])
          end
        end

        def record_span(execution)
          guard { scope(execution).update_all("span_count = COALESCE(span_count, 0) + 1") }
        end

        def record_error(execution)
          guard { scope(execution).update_all("error_count = COALESCE(error_count, 0) + 1") }
        end

        # Recomputes from the spans themselves. The repair path when
        # buffered writes are lost to a crash.
        def rebuild!(execution)
          guard do
            spans = Span.where(execution_id: execution.id)
            scope(execution).update_all(
              total_tokens: spans.sum(:total_tokens),
              total_cost_usd: spans.sum(:cost_usd),
              span_count: spans.count,
              error_count: spans.errored.count
            )
          end
        end

        def scope(execution)
          Execution.where(id: execution.id)
        end

        def guard
          yield
        rescue StandardError => e
          if defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger
            ::Rails.logger.warn("[rcrewai-rails] rollup failed: #{e.class}: #{e.message}")
          end
          nil
        end
      end
    end
  end
end
