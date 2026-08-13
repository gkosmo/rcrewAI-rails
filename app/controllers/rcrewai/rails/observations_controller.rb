module RcrewAI
  module Rails
    class ObservationsController < ApplicationController
      # Hard ceiling on how deep the span partial will recurse. Real traces
      # are a handful of levels deep; this only exists so a malformed tree
      # cannot recurse until the request dies.
      MAX_SPAN_DEPTH = 50

      def show
        @execution = Execution.find(params[:execution_id])
        # Load the whole tree in one query and nest in memory — a recursive
        # per-node query would be N+1 on deep traces.
        @spans = @execution.spans.ordered.to_a
        @children = @spans.group_by(&:parent_span_id)
        @roots = @children[nil] || []
      end

      def costs
        @executions = Execution.where.not(total_cost_usd: nil)
                               .order(created_at: :desc)
                               .limit(100)
        @total_cost = @executions.sum(&:total_cost_usd)
        @total_tokens = @executions.sum { |e| e.total_tokens.to_i }
      end
    end
  end
end
