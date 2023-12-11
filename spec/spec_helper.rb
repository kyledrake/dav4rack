require "bundler/setup"
Bundler.setup

require "dav4rack"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end
  config.order = :random
end
