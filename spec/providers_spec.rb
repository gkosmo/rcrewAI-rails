require "rails_helper"

# rcrewai 0.8 added four providers. The engine passes an agent's llm_config
# through to the gem verbatim, so these assert the wiring resolves rather than
# re-testing the gem's client internals.
RSpec.describe "rcrewai 0.8 providers", type: :model do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "c") }

  before do
    # Undo the global for_provider stub: resolution is what's under test.
    allow(RCrewAI::LLMClient).to receive(:for_provider).and_call_original
  end

  def config_for(**attrs)
    RCrewAI.configuration.dup.tap do |c|
      attrs.each { |k, v| c.public_send("#{k}=", v) }
    end
  end

  it "exposes every new provider in the gem's provider table" do
    expect(RCrewAI::LLMClient::PROVIDERS.keys)
      .to include(:openai_compatible, :bedrock, :snowflake, :openai_responses)
  end

  {
    openai_compatible: { base_url: "https://api.groq.com/openai/v1" },
    bedrock: { aws_region: "us-east-1" },
    snowflake: { snowflake_account: "acme-test" },
    openai_responses: {}
  }.each do |provider, extra|
    it "resolves #{provider} through an agent's llm_config" do
      config = config_for(llm_provider: provider, api_key: "k", model: "m", **extra)
      allow(RCrewAI).to receive(:configuration).and_return(config)

      agent = crew.agents.create!(
        name: "a", role: "Worker",
        llm_config: { "provider" => provider.to_s, "model" => "m" }
      )

      expect { agent.to_rcrew_agent }.not_to raise_error
      expect(agent.to_rcrew_agent.llm_client)
        .to be_a(RCrewAI::LLMClient::PROVIDERS.fetch(provider))
    end
  end

  it "surfaces the gem's error for a provider that is genuinely unknown" do
    agent = crew.agents.create!(
      name: "a", role: "Worker",
      llm_config: { "provider" => "nope", "model" => "m" }
    )

    expect { agent.to_rcrew_agent }.to raise_error(RCrewAI::ConfigurationError, /nope/)
  end
end
