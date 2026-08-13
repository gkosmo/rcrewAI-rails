module RcrewAI
  module Rails
    class SpanEvent < ApplicationRecord
      self.table_name = "rcrewai_span_events"

      LEVELS = %w[debug info warn error].freeze

      belongs_to :span

      validates :level, inclusion: { in: LEVELS }
      validates :name, presence: true

      serialize :details, coder: JSON

      scope :errors, -> { where(level: "error") }
      scope :recent, -> { order(timestamp: :desc) }
    end
  end
end
