require "rcrewai"
require "rails"
require "active_record"
require "active_job"
require "turbo-rails"
require "stimulus-rails"

require_relative "rails/version"
require_relative "rails/engine"
require_relative "rails/configuration"
require_relative "rails/crew_builder"
require_relative "rails/agent_builder"

module RcrewAI
  module Rails
    class Error < StandardError; end

    class << self
      attr_accessor :configuration

      def configure
        self.configuration ||= Configuration.new
        yield(configuration) if block_given?
      end

      def config
        @configuration ||= Configuration.new
      end
    end
  end

  # Delegate configure to Rails module for convenience
  def self.configure(&block)
    Rails.configure(&block)
  end

  def self.config
    Rails.config
  end
end