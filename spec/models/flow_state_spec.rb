require "rails_helper"

# A tiny real Flow subclass for integration tests. Flow methods are plain Ruby.
class FlowStateSpecFlow < RCrewAI::Flow
  start :go
  def go
    state.ran = true
    state.count = 41
  end
end

RSpec.describe RcrewAI::Rails::ActiveRecordStateStore, type: :model do
  let(:store) { described_class.new }

  it "round-trips a hash by id" do
    store.save("abc", { "a" => 1, "b" => "two" })
    expect(store.load("abc")).to eq({ "a" => 1, "b" => "two" })
  end

  it "updates rather than duplicating on repeat save" do
    store.save("abc", { "n" => 1 })
    store.save("abc", { "n" => 2 })

    expect(store.load("abc")).to eq({ "n" => 2 })
    expect(RcrewAI::Rails::FlowState.where(state_id: "abc").count).to eq(1)
  end

  it "returns nil for an unknown id" do
    expect(store.load("missing")).to be_nil
  end

  it "persists and restores a real Flow's state through the DB" do
    flow = FlowStateSpecFlow.new(state_store: store)
    result = flow.kickoff

    expect(RcrewAI::Rails::FlowState.find_by(state_id: result.id)).to be_present

    restored = FlowStateSpecFlow.new(state_store: store)
    state = restored.restore(result.id)
    expect(state.ran).to eq(true)
    expect(state.count).to eq(41)
  end
end

RSpec.describe RcrewAI::Rails::FlowState, type: :model do
  it "validates state_id presence and uniqueness" do
    RcrewAI::Rails::FlowState.create!(state_id: "dup", data: { "x" => 1 })

    missing = RcrewAI::Rails::FlowState.new(data: { "x" => 1 })
    expect(missing).not_to be_valid

    dup = RcrewAI::Rails::FlowState.new(state_id: "dup", data: { "x" => 1 })
    expect(dup).not_to be_valid
  end
end
