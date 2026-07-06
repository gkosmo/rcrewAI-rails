require "rails_helper"

RSpec.describe RcrewAI::Rails::KnowledgeSource, type: :model do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "C", process_type: "sequential") }
  let(:agent) { crew.agents.create!(name: "a", role: "Worker") }

  describe "#to_rcrew_source" do
    {
      "string" => RCrewAI::Knowledge::StringSource,
      "file"   => RCrewAI::Knowledge::FileSource,
      "pdf"    => RCrewAI::Knowledge::PdfSource,
      "csv"    => RCrewAI::Knowledge::CsvSource,
      "url"    => RCrewAI::Knowledge::UrlSource,
    }.each do |type, klass|
      it "maps #{type} to #{klass}" do
        source = crew.knowledge_sources.create!(source_type: type, value: "v")
        expect(source.to_rcrew_source).to be_a(klass)
      end
    end
  end

  describe "validations" do
    it "rejects an unknown source_type" do
      source = crew.knowledge_sources.build(source_type: "bogus", value: "v")
      expect(source).not_to be_valid
      expect(source.errors[:source_type]).to be_present
    end

    it "requires a value" do
      source = crew.knowledge_sources.build(source_type: "string", value: nil)
      expect(source).not_to be_valid
      expect(source.errors[:value]).to be_present
    end
  end

  describe "polymorphic ownership" do
    it "can belong to a crew" do
      source = crew.knowledge_sources.create!(source_type: "string", value: "hello")
      expect(source.owner).to eq(crew)
      expect(crew.knowledge_sources).to include(source)
    end

    it "can belong to an agent" do
      source = agent.knowledge_sources.create!(source_type: "string", value: "hello")
      expect(source.owner).to eq(agent)
      expect(agent.knowledge_sources).to include(source)
    end
  end

  describe "active scope" do
    it "returns only active sources" do
      keep = crew.knowledge_sources.create!(source_type: "string", value: "keep", active: true)
      crew.knowledge_sources.create!(source_type: "string", value: "drop", active: false)
      expect(crew.knowledge_sources.active).to eq([keep])
    end
  end
end
