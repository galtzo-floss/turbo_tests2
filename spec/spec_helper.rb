# frozen_string_literal: true

# Config for development dependencies of this library
# i.e., not configured by this library
#
# Simplecov & related config (must run BEFORE any requires that might load this library)
# NOTE: Gemfiles for older rubies won't have kettle-soup-cover.
#       The rescue LoadError handles that scenario.
begin
  require "kettle-soup-cover"
  require "simplecov" if Kettle::Soup::Cover::DO_COV # `.simplecov` is run here!
rescue LoadError => error
  # check the error message and re-raise when unexpected
  raise error unless error.message.include?("kettle")
end

# External RSpec & related config
require "parallel_tests/tasks"
require "kettle/test/rspec"

# RSpec Configs
require_relative "config/debug"
require_relative "config/rspec/rspec_core"
require_relative "config/rspec/rspec_block_is_expected"

require "turbo_tests2"
RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
