require "spec_helper"
require "support/rails_stubs"
require "rcrewai/rails/tools/rails_logger_tool"

RSpec.describe RcrewAI::Rails::Tools::RailsLoggerTool do
  let(:logger) do
    Class.new do
      attr_reader :calls
      def initialize; @calls = []; end
      %i[debug info warn error fatal].each do |lvl|
        define_method(lvl) { |msg| @calls << [lvl, msg] }
      end
    end.new
  end

  # Rails.logger is global. Restore it afterwards so this fake -- which
  # accepts exactly one argument and no block -- cannot break unrelated
  # examples that log through the real logger.
  around do |example|
    previous = Rails.logger
    Rails.logger = logger
    begin
      example.run
    ensure
      Rails.logger = previous
    end
  end

  describe "schema" do
    it "requires level and message and enumerates levels" do
      schema = described_class.json_schema
      expect(schema[:name]).to eq("rails_logger")
      expect(schema[:parameters][:required]).to match_array(%w[level message])
      expect(schema[:parameters][:properties][:level][:enum]).to eq(%w[debug info warn error fatal])
    end
  end

  describe "#execute" do
    subject(:tool) { described_class.new(tag: "Test") }

    it "logs the message with the tag prefix" do
      result = tool.execute(level: "info", message: "hello")
      expect(result).to eq(logged: true, level: "info", message: "hello")
      expect(logger.calls).to eq([[:info, "[Test] hello"]])
    end

    it "appends metadata as JSON" do
      tool.execute(level: "warn", message: "danger", metadata: { code: 42 })
      expect(logger.calls.last).to eq([:warn, "[Test] danger | {\"code\":42}"])
    end

    it "emits an ActiveSupport notification" do
      events = []
      sub = ActiveSupport::Notifications.subscribe("log.rcrewai") { |*args| events << args }
      tool.execute(level: "info", message: "hi")
      expect(events.length).to eq(1)
    ensure
      ActiveSupport::Notifications.unsubscribe(sub) if sub
    end

    it "returns an error hash for unknown levels" do
      expect(tool.execute(level: "trace", message: "x")).to eq(error: "Unknown log level: trace")
    end
  end
end
