require "spec_helper"
require "support/rails_stubs"

# The tool references ActiveRecord::RecordNotFound in a rescue clause; stub it
# so the spec runs without loading the full ActiveRecord stack.
unless defined?(ActiveRecord::RecordNotFound)
  module ActiveRecord
    class RecordNotFound < StandardError; end
  end
end

require "rcrewai/rails/tools/active_record_tool"

RSpec.describe RcrewAI::Rails::Tools::ActiveRecordTool do
  let(:model) do
    Class.new do
      class << self
        def find(id); { id: id, name: "user_#{id}" }; end
        def find_by(attrs); attrs.merge(found: true); end
        def where(attrs); [{ attrs: attrs }]; end
        def count; 7; end
        def pluck(field); [field, field]; end
        def exists?(_attrs); true; end
        def first; { rank: :first }; end
        def last; { rank: :last }; end
        def to_a; [:a, :b]; end
      end
    end
  end

  describe "schema" do
    it "declares a strict JSON schema with query_type required and the right enum values" do
      schema = described_class.json_schema
      expect(schema[:name]).to eq("active_record_query")
      expect(schema[:parameters][:required]).to eq(["query_type"])
      expect(schema[:parameters][:properties][:query_type][:enum]).to eq(
        %w[find find_by where count pluck exists? first last all]
      )
      expect(schema[:parameters][:properties][:conditions][:type]).to eq("object")
    end
  end

  describe "#execute" do
    subject(:tool) { described_class.new(model_class: model, allowed_methods: %i[find where count pluck exists? first last all find_by]) }

    it "dispatches :find" do
      expect(tool.execute(query_type: "find", conditions: { id: 1 })).to eq({ id: 1, name: "user_1" })
    end

    it "dispatches :find_by" do
      expect(tool.execute(query_type: "find_by", conditions: { email: "x@y.z" })).to eq({ email: "x@y.z", found: true })
    end

    it "dispatches :count without conditions" do
      expect(tool.execute(query_type: "count")).to eq(7)
    end

    it "rejects query types not in allowed_methods" do
      restricted = described_class.new(model_class: model, allowed_methods: %i[count])
      result = restricted.execute(query_type: "find", conditions: { id: 1 })
      expect(result[:error]).to eq("Query failed")
      expect(result[:message]).to match(/not allowed/)
    end

    it "wraps ActiveRecord::RecordNotFound" do
      bad_model = Class.new { def self.find(_); raise ActiveRecord::RecordNotFound, "nope"; end }
      tool = described_class.new(model_class: bad_model, allowed_methods: %i[find])
      result = tool.execute(query_type: "find", conditions: { id: 99 })
      expect(result).to eq(error: "Record not found", message: "nope")
    end
  end

  describe "schema validation" do
    subject(:tool) { described_class.new(model_class: model, allowed_methods: %i[count]) }

    it "raises ToolError when query_type is missing" do
      expect { tool.execute_with_validation({}) }.to raise_error(RCrewAI::Tools::ToolError, /query_type/)
    end

    it "coerces args via the DSL schema and dispatches" do
      expect(tool.execute_with_validation("query_type" => "count")).to eq(7)
    end
  end
end
