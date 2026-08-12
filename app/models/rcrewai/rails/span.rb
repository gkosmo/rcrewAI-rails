module RcrewAI
  module Rails
    class Span < ApplicationRecord
      self.table_name = "rcrewai_spans"

      KINDS    = %w[crew agent task llm_call tool_call].freeze
      STATUSES = %w[running ok error].freeze

      belongs_to :execution
      belongs_to :parent, class_name: "RcrewAI::Rails::Span",
                          foreign_key: :parent_span_id, optional: true
      has_many :children, class_name: "RcrewAI::Rails::Span",
                          foreign_key: :parent_span_id, dependent: :destroy
      has_many :span_events, dependent: :destroy

      validates :kind, inclusion: { in: KINDS }
      validates :status, inclusion: { in: STATUSES }
      validates :name, :trace_id, :started_at, :sequence, presence: true

      scope :roots, -> { where(parent_span_id: nil).order(:sequence) }
      scope :ordered, -> { order(:sequence) }
      scope :errored, -> { where(status: "error") }
      scope :running, -> { where(status: "running") }
      scope :llm_calls, -> { where(kind: "llm_call") }
      scope :tool_calls, -> { where(kind: "tool_call") }

      def attributes_hash
        raw = self[:attributes_json]
        return {} if raw.blank?

        JSON.parse(raw)
      rescue JSON::ParserError
        {}
      end

      def attributes_hash=(hash)
        self[:attributes_json] = hash.nil? ? nil : JSON.generate(hash)
      end

      def finish!(status: "ok", ended_at: Time.current)
        update!(
          status: status,
          ended_at: ended_at,
          duration_ms: ((ended_at - started_at) * 1000).round
        )
      end

      def running?
        status == "running"
      end

      def errored?
        status == "error"
      end
    end
  end
end
