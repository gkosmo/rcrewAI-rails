require "rails_helper"

RSpec.describe "observation autoloading" do
  it "exposes the observation components without explicit requires" do
    expect(defined?(RcrewAI::Rails::Observation::Collector)).to eq("constant")
    expect(defined?(RcrewAI::Rails::Observation::SpanStack)).to eq("constant")
    expect(defined?(RcrewAI::Rails::Observation::Writer)).to eq("constant")
    expect(defined?(RcrewAI::Rails::Observation::Rollup)).to eq("constant")
  end

  it "resolves the models the observation components depend on" do
    expect(RcrewAI::Rails::Observation::Writer.new(mode: :immediate)).to be_a(
      RcrewAI::Rails::Observation::Writer
    )
    expect(defined?(RcrewAI::Rails::Span)).to eq("constant")
    expect(defined?(RcrewAI::Rails::SpanEvent)).to eq("constant")
  end
end
