require "spec_helper"
require "support/rails_stubs"
require "rcrewai/rails/tools/action_mailer_tool"

RSpec.describe RcrewAI::Rails::Tools::ActionMailerTool do
  let(:mail_object) do
    Class.new do
      attr_reader :delivered_now, :delivered_later, :scheduled_for
      def deliver_now
        @delivered_now = true
        self
      end
      def deliver_later(wait_until: nil)
        @delivered_later = true
        @scheduled_for = wait_until
        Struct.new(:job_id).new("job-123")
      end
    end.new
  end

  let(:mailer) do
    obj = mail_object
    Class.new do
      define_singleton_method(:welcome_email) { |**_args| obj }
      define_singleton_method(:report) { |**_args| obj }
    end
  end

  describe "schema" do
    it "requires only mailer_method and enumerates delivery methods" do
      schema = described_class.json_schema
      expect(schema[:name]).to eq("action_mailer_send")
      expect(schema[:parameters][:required]).to eq(["mailer_method"])
      expect(schema[:parameters][:properties][:deliver_method][:enum]).to eq(
        %w[deliver_now deliver_later deliver_later_at]
      )
    end
  end

  describe "#execute" do
    subject(:tool) { described_class.new(mailer_class: mailer) }

    it "delivers now" do
      result = tool.execute(mailer_method: "welcome_email", deliver_method: "deliver_now", params: { user_id: 1 })
      expect(mail_object.delivered_now).to be true
      expect(result[:status]).to eq("sent")
      expect(result[:method]).to eq(:welcome_email)
    end

    it "queues with deliver_later" do
      result = tool.execute(mailer_method: "report", deliver_method: "deliver_later")
      expect(mail_object.delivered_later).to be true
      expect(result).to include(status: "queued", method: :report, job_id: "job-123")
    end

    it "schedules with deliver_later_at and parses an ISO8601 timestamp" do
      at = "2030-01-02T03:04:05Z"
      result = tool.execute(mailer_method: "report", deliver_method: "deliver_later_at", at: at)
      expect(mail_object.scheduled_for).to eq(Time.iso8601(at))
      expect(result[:status]).to eq("scheduled")
    end

    it "enforces allowed_methods when configured" do
      restricted = described_class.new(mailer_class: mailer, allowed_methods: %i[welcome_email])
      expect(restricted.execute(mailer_method: "report")[:error]).to eq("Failed to send email")
    end

    it "raises when no mailer is supplied or configured" do
      bare = described_class.new
      result = bare.execute(mailer_method: "welcome_email")
      expect(result[:error]).to eq("Failed to send email")
      expect(result[:message]).to match(/No mailer specified/)
    end
  end
end
