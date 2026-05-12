require "spec_helper"
require "support/rails_stubs"
require "rcrewai/rails/tools/active_storage_tool"

RSpec.describe RcrewAI::Rails::Tools::ActiveStorageTool do
  describe "schema" do
    it "requires operation and enumerates the supported operations" do
      schema = described_class.json_schema
      expect(schema[:name]).to eq("active_storage")
      expect(schema[:parameters][:required]).to eq(["operation"])
      expect(schema[:parameters][:properties][:operation][:enum]).to eq(
        %w[attach download analyze delete url]
      )
    end
  end

  describe "#execute" do
    subject(:tool) { described_class.new(allowed_operations: %i[attach download]) }

    it "rejects operations not in the allowed list" do
      result = tool.execute(operation: "delete")
      expect(result[:error]).to eq("Active Storage operation failed")
      expect(result[:message]).to match(/'delete' is not allowed/)
    end

    it "returns an error hash for unknown operations" do
      permissive = described_class.new(allowed_operations: %i[attach download analyze delete url unknown])
      expect(permissive.execute(operation: "unknown")).to eq(error: "Unknown operation: unknown")
    end
  end
end
