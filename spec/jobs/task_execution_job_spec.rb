require "spec_helper"
require "support/rails_stubs"

require "active_job"
require "fileutils"
require "tmpdir"

# RcrewAI::Rails.config is consulted by queue_as { ... }; provide a minimal one.
module RcrewAI
  module Rails
    class << self
      def config
        @config ||= Struct.new(:job_queue_name).new(:default)
      end
    end
  end
end

require "rcrewai/rails/agent_builder" # not strictly required, but exercises load order

# Load just the job class without dragging in the engine.
require File.expand_path("../../app/jobs/rcrewai/rails/task_execution_job", __dir__)

RSpec.describe RcrewAI::Rails::TaskExecutionJob do
  before do
    ActiveJob::Base.queue_adapter = :test
    Rails.logger = Logger.new(File::NULL)
    Rails.cache = nil
    @tmpdir = Dir.mktmpdir
    Rails.singleton_class.class_eval do
      define_method(:root) { Pathname.new(@__test_root) }
    end
    Rails.instance_variable_set(:@__test_root, @tmpdir)
  end

  after { FileUtils.remove_entry(@tmpdir) if @tmpdir && File.directory?(@tmpdir) }

  let(:rcrew_agent) do
    Class.new do
      def execute_task(_task)
        {
          content: "the final content",
          tool_calls_history: [{ tool: "x", args: {} }],
          usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
          iterations: 2,
          finish_reason: :stop
        }
      end
    end.new
  end

  let(:task_record) do
    rcrew_task_stub = Object.new
    Struct.new(:id, :output_file, :rcrew_task).new(42, output_file, rcrew_task_stub).tap do |s|
      s.define_singleton_method(:to_rcrew_task) { rcrew_task_stub }
    end
  end
  let(:agent_record) do
    a = rcrew_agent
    Struct.new(:id).new(7).tap do |s|
      s.define_singleton_method(:to_rcrew_agent) { a }
    end
  end

  context "with no output_file" do
    let(:output_file) { nil }

    it "returns the hash and emits an ActiveSupport notification with the content and usage" do
      events = []
      sub = ActiveSupport::Notifications.subscribe("task_execution.rcrewai") { |*args| events << args.last }
      result = described_class.new.perform(task_record, agent_record, { extra: "input" })
      expect(result).to include(content: "the final content", finish_reason: :stop)
      payload = events.last
      expect(payload[:status]).to eq("completed")
      expect(payload[:result]).to eq("the final content")  # the string, not the hash
      expect(payload[:usage]).to eq(prompt_tokens: 10, completion_tokens: 5, total_tokens: 15)
      expect(payload[:iterations]).to eq(2)
      expect(payload[:finish_reason]).to eq(:stop)
    ensure
      ActiveSupport::Notifications.unsubscribe(sub) if sub
    end
  end

  context "with an output_file configured" do
    let(:output_file) { "out.txt" }

    it "writes the content string (not the hash) to the file" do
      described_class.new.perform(task_record, agent_record)
      written = File.read(File.join(@tmpdir, "tmp", "rcrewai_outputs", "out.txt"))
      expect(written).to eq("the final content")
    end
  end

  context "when the agent raises" do
    let(:output_file) { nil }

    let(:rcrew_agent) do
      Class.new do
        def execute_task(_task); raise "boom"; end
      end.new
    end

    it "emits a failed notification and re-raises" do
      events = []
      sub = ActiveSupport::Notifications.subscribe("task_execution.rcrewai") { |*args| events << args.last }
      expect { described_class.new.perform(task_record, agent_record) }.to raise_error(RuntimeError, "boom")
      expect(events.last[:status]).to eq("failed")
      expect(events.last[:error]).to eq("boom")
    ensure
      ActiveSupport::Notifications.unsubscribe(sub) if sub
    end
  end
end
