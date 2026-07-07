require "rails_helper"

RSpec.describe RcrewAI::Rails::Configuration do
  it "defaults memory embedder and store to nil" do
    config = described_class.new
    expect(config.default_memory_embedder).to be_nil
    expect(config.default_memory_store).to be_nil
  end

  it "allows setting memory embedder and store" do
    config = described_class.new
    config.default_memory_embedder = :an_embedder
    config.default_memory_store = :a_store
    expect(config.default_memory_embedder).to eq(:an_embedder)
    expect(config.default_memory_store).to eq(:a_store)
  end
end
