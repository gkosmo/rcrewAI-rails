module RcrewAI
  module Rails
    class KnowledgeSource < ApplicationRecord
      self.table_name = "rcrewai_knowledge_sources"

      TYPE_MAP = {
        "string" => RCrewAI::Knowledge::StringSource,
        "file"   => RCrewAI::Knowledge::FileSource,
        "pdf"    => RCrewAI::Knowledge::PdfSource,
        "csv"    => RCrewAI::Knowledge::CsvSource,
        "url"    => RCrewAI::Knowledge::UrlSource,
      }.freeze

      belongs_to :owner, polymorphic: true

      validates :source_type, inclusion: { in: TYPE_MAP.keys }
      validates :value, presence: true

      scope :active, -> { where(active: true) }

      # Maps this row to the matching core Source object.
      def to_rcrew_source
        TYPE_MAP.fetch(source_type).new(value)
      end
    end
  end
end
