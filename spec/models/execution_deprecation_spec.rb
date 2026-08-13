require "rails_helper"

RSpec.describe "ExecutionLog deprecation" do
  let(:crew) { RcrewAI::Rails::Crew.create!(name: "c") }
  let(:execution) { crew.executions.create!(status: "running", started_at: Time.current) }

  it "still writes log rows" do
    expect { execution.log("info", "hello") }.to change(RcrewAI::Rails::ExecutionLog, :count).by(1)
  end

  it "warns that the method is deprecated" do
    expect(RcrewAI::Rails).to receive(:deprecator_warn).with(/ExecutionLog/)
    execution.log("info", "hello")
  end
end
