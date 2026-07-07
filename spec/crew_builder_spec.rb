require "rails_helper"

RSpec.describe RcrewAI::Rails::CrewBuilder do
  it "builds a Crew via find_or_create_crew without referencing dropped columns" do
    builder_class = Class.new do
      include RcrewAI::Rails::CrewBuilder
      crew_name "Test Crew"
      process_type :sequential

      def setup_agents; end
      def setup_tasks; end
      def setup_callbacks; end
      def verbose?; false; end
    end

    builder = builder_class.new
    crew = builder.instance_variable_get(:@crew)

    expect(crew).to be_a(RcrewAI::Rails::Crew)
    expect(crew.name).to eq("Test Crew")
    expect(crew).to be_persisted
  end
end
