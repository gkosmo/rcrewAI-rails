require "rails_helper"
require "rails/generators"

RSpec.describe "generator lookup" do
  it "finds the install generator under its documented name" do
    expect(Rails::Generators.find_by_namespace("rcrewai:rails:install").to_s)
      .to eq("RcrewAI::Rails::Generators::InstallGenerator")
  end

  it "finds the crew generator under its documented name" do
    expect(Rails::Generators.find_by_namespace("rcrewai:rails:crew").to_s)
      .to eq("RcrewAI::Rails::Generators::CrewGenerator")
  end
end
