require "bundler/setup"

require "active_support"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/string/inflections"
require "active_support/core_ext/numeric/time"
require "active_support/core_ext/integer/time"
require "active_support/notifications"
require "active_support/concern"
require "active_support/time"

require "rcrewai"

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
