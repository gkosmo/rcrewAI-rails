require "spec_helper"

ENV["RAILS_ENV"] = "test"

require "combustion"
Combustion.path = "spec/internal"
Combustion.initialize! :active_record, :action_controller, :active_job,
                       database_migrate: false do
  config.load_defaults 7.0
  config.eager_load = true
  config.logger = Logger.new(File::NULL)
end

# Combustion queues schema-loading inside a `to_prepare` callback that doesn't
# always fire under `eager_load: false` in test mode. Run the setup explicitly
# so the schema is in place before the first example.
Combustion::Database.setup(
  database_reset: false,
  load_schema: true,
  database_migrate: false
)

require "rspec/rails" if defined?(Rails)

RSpec.configure do |config|
  config.use_transactional_fixtures = true

  # Every RCrewAI::Agent.new builds an LLM client via LLMClient.for_provider,
  # which validates provider credentials. Replace it with a tiny double for
  # all model/job specs so they don't need real API keys.
  config.before(:each) do
    fake_llm = double("LLMClient")
    allow(fake_llm).to receive(:chat).and_return(
      content: "FINAL_ANSWER[done]",
      finish_reason: :stop,
      usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 }
    )
    allow(fake_llm).to receive(:supports_native_tools?).and_return(false)
    allow(RCrewAI::LLMClient).to receive(:for_provider).and_return(fake_llm)
  end
end
