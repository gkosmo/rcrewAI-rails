# Stand-in for the Rails constant so unit specs can exercise tools that reach
# into Rails.logger / Rails.cache / Rails.env without loading the full Rails
# framework via rails_helper.
#
# Loaded only by lightweight specs (those that require "spec_helper"). The
# rails_helper boots a real Rails app via Combustion and does NOT load this
# file, so the two paths don't conflict.
unless defined?(Rails)
  module Rails
    class << self
      attr_accessor :logger, :cache, :env
    end
  end
end
