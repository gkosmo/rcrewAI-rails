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

  describe "observation settings" do
    subject(:config) { described_class.new }

    it "enables observation by default" do
      expect(config.observation_enabled).to be(true)
    end

    it "truncates prompts by default" do
      expect(config.observation_capture_prompts).to eq(:truncated)
      expect(config.observation_prompt_max_bytes).to eq(4_096)
    end

    it "batches writes by default" do
      expect(config.observation_flush_mode).to eq(:batched)
      expect(config.observation_flush_every).to eq(25)
    end

    it "retains spans for 30 days by default" do
      expect(config.observation_retention_days).to eq(30)
    end

    it "allows overriding each setting" do
      config.observation_enabled = false
      config.observation_capture_prompts = :none
      expect(config.observation_enabled).to be(false)
      expect(config.observation_capture_prompts).to eq(:none)
    end
  end
end
