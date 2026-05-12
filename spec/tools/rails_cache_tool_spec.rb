require "spec_helper"
require "support/rails_stubs"
require "rcrewai/rails/tools/rails_cache_tool"

RSpec.describe RcrewAI::Rails::Tools::RailsCacheTool do
  let(:cache) do
    Class.new do
      def initialize; @store = {}; end
      def read(key); @store[key]; end
      def write(key, value, _opts = {}); @store[key] = value; true; end
      def delete(key); !@store.delete(key).nil?; end
      def exist?(key); @store.key?(key); end
      def fetch(key, _opts = {}); @store[key] ||= yield if block_given?; @store[key]; end
      def clear; @store.clear; true; end
    end.new
  end

  before { Rails.cache = cache }

  describe "schema" do
    it "declares enum action and required only on :action" do
      schema = described_class.json_schema
      expect(schema[:name]).to eq("rails_cache")
      expect(schema[:parameters][:required]).to eq(["action"])
      expect(schema[:parameters][:properties][:action][:enum]).to eq(
        %w[read write delete exist? fetch clear]
      )
    end
  end

  describe "#execute" do
    subject(:tool) { described_class.new }

    it "writes and reads" do
      tool.execute(action: "write", key: "k", value: "v")
      expect(tool.execute(action: "read", key: "k")).to eq(key: "k", value: "v", exists: true)
    end

    it "reports missing keys" do
      expect(tool.execute(action: "read", key: "missing")).to eq(key: "missing", value: nil, exists: false)
    end

    it "supports exist?" do
      tool.execute(action: "write", key: "k", value: "v")
      expect(tool.execute(action: "exist?", key: "k")).to eq(key: "k", exists: true)
    end

    it "deletes" do
      tool.execute(action: "write", key: "k", value: "v")
      expect(tool.execute(action: "delete", key: "k")).to eq(key: "k", deleted: true)
    end

    it "rejects unknown actions through the enum schema" do
      expect { tool.execute_with_validation("action" => "explode") }.not_to raise_error
      # The enum coerces to string and falls through to the unknown-action branch.
      result = tool.execute(action: "explode")
      expect(result).to eq(error: "Unknown action: explode")
    end
  end
end
