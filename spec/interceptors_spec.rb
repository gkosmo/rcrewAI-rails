require "rails_helper"

RSpec.describe RcrewAI::Rails::Interceptors do
  # A real gem client, so hook registration is exercised against the actual
  # LLMClients::Base API rather than a double that would accept anything.
  def real_client
    RCrewAI::LLMClients::OpenAI.new(
      RCrewAI.configuration.dup.tap do |c|
        c.llm_provider = :openai
        c.api_key = "test-key"
        c.model = "gpt-4"
      end
    )
  end

  after do
    RcrewAI::Rails.config.llm_before_request = nil
    RcrewAI::Rails.config.llm_after_response = nil
  end

  describe ".configured?" do
    it "is false by default and true once a hook is set" do
      expect(described_class.configured?).to be(false)

      RcrewAI::Rails.config.llm_before_request = ->(payload, _ctx) { payload }
      expect(described_class.configured?).to be(true)
    end
  end

  describe ".apply" do
    it "registers a before_request hook that the client actually calls" do
      seen = nil
      RcrewAI::Rails.config.llm_before_request = lambda do |payload, ctx|
        seen = ctx
        payload.merge(user: "rails")
      end

      client = described_class.apply(real_client)
      result = client.send(:apply_before_request, { model: "gpt-4" })

      expect(result).to eq({ model: "gpt-4", user: "rails" })
      expect(seen[:provider]).to eq(:openai)
      expect(seen[:model]).to eq("gpt-4")
    end

    it "registers an after_response hook and exposes duration_ms" do
      seen = nil
      RcrewAI::Rails.config.llm_after_response = lambda do |result, ctx|
        seen = ctx
        result.merge(tagged: true)
      end

      client = described_class.apply(real_client)
      result = client.send(:apply_after_response, { content: "hi" }, Time.now)

      expect(result[:tagged]).to be(true)
      expect(seen).to have_key(:duration_ms)
    end

    it "applies multiple hooks in order" do
      RcrewAI::Rails.config.llm_before_request = [
        ->(payload, _ctx) { payload.merge(order: ["first"]) },
        ->(payload, _ctx) { payload.merge(order: payload[:order] + ["second"]) }
      ]

      client = described_class.apply(real_client)
      expect(client.send(:apply_before_request, {})[:order]).to eq(%w[first second])
    end

    it "leaves a client that does not speak the hook API untouched" do
      bare = double("CustomClient")
      allow(bare).to receive(:respond_to?).and_return(false)

      RcrewAI::Rails.config.llm_before_request = ->(payload, _ctx) { payload }
      expect { described_class.apply(bare) }.not_to raise_error
    end

    it "is a no-op for a nil client" do
      expect(described_class.apply(nil)).to be_nil
    end
  end

  describe "agent wiring" do
    let(:crew) { RcrewAI::Rails::Crew.create!(name: "c") }

    it "attaches the configured hooks to an agent record's client" do
      RcrewAI::Rails.config.llm_before_request = ->(payload, _ctx) { payload }

      # The global stub replaces for_provider with a double; use a real client
      # here so registration is verifiable.
      client = real_client
      allow(RCrewAI::LLMClient).to receive(:resolve).and_return(client)
      allow(RCrewAI::LLMClient).to receive(:for_provider).and_return(client)

      agent = crew.agents.create!(name: "a", role: "Worker")
      agent.to_rcrew_agent

      expect(client.instance_variable_get(:@before_request_hooks).size).to eq(1)
    end

    it "does not touch the client when no hooks are configured" do
      client = real_client
      allow(RCrewAI::LLMClient).to receive(:resolve).and_return(client)
      allow(RCrewAI::LLMClient).to receive(:for_provider).and_return(client)

      agent = crew.agents.create!(name: "a", role: "Worker")
      agent.to_rcrew_agent

      expect(client.instance_variable_get(:@before_request_hooks)).to be_empty
    end
  end
end
