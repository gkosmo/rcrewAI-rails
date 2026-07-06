require "rails_helper"

class FlowRunSpecFlow < RCrewAI::Flow
  start :go
  def go
    state.topic = "ruby"
    state.done = true
  end
end

class FlowRunBoomFlow < RCrewAI::Flow
  start :go
  def go
    raise "kaboom"
  end
end

RSpec.describe RcrewAI::Rails::FlowRun, type: :model do
  describe ".execute" do
    it "creates a completed run with the final state" do
      run = described_class.execute(FlowRunSpecFlow, inputs: { seed: "x" })

      expect(run.status).to eq("completed")
      expect(run.flow_class).to eq("FlowRunSpecFlow")
      expect(run.state_id).to be_present
      expect(run.result["topic"]).to eq("ruby")
      expect(run.result["done"]).to eq(true)
      expect(run.inputs).to eq({ "seed" => "x" })
    end

    it "accepts a String flow class name" do
      run = described_class.execute("FlowRunSpecFlow")
      expect(run.status).to eq("completed")
      expect(run.flow_class).to eq("FlowRunSpecFlow")
    end

    it "persists the flow state so it is queryable by state_id" do
      run = described_class.execute(FlowRunSpecFlow)
      expect(RcrewAI::Rails::FlowState.find_by(state_id: run.state_id)).to be_present
    end

    it "records a failure and re-raises when the flow raises" do
      expect {
        described_class.execute(FlowRunBoomFlow)
      }.to raise_error("kaboom")

      run = described_class.where(flow_class: "FlowRunBoomFlow").order(:id).last
      expect(run.status).to eq("failed")
      expect(run.error_message).to eq("kaboom")
    end
  end

  describe "validations and scopes" do
    it "validates flow_class presence and status inclusion" do
      bad = described_class.new(flow_class: nil, status: "weird")
      expect(bad).not_to be_valid
      expect(bad.errors[:flow_class]).to be_present
      expect(bad.errors[:status]).to be_present
    end

    it "scopes successful and failed" do
      ok = described_class.create!(flow_class: "X", status: "completed")
      bad = described_class.create!(flow_class: "X", status: "failed")

      expect(described_class.successful).to include(ok)
      expect(described_class.successful).not_to include(bad)
      expect(described_class.failed).to include(bad)
    end
  end
end
