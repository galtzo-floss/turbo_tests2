# frozen_string_literal: true

# Loaded via RUBYOPT ("-r./.simplecov_spawn") in spawned (non-fork) subprocesses
# to collect coverage from processes started with backticks / Open3 / Process.spawn.
#
# See: https://github.com/simplecov-ruby/simplecov#running-simplecov-against-spawned-subprocesses
#
# The main test process merges results from all spawned processes automatically
# because kettle-soup-cover enables use_merging by default.
#
# Usage (set in the test process *before* spawning):
#   ENV["RUBYOPT"] = "-r./.simplecov_spawn #{ENV["RUBYOPT"]}".strip
require "simplecov"

# Quiet mode: the parent test process owns the final formatted report.
SimpleCov.print_error_status = false
SimpleCov.formatter SimpleCov::Formatter::SimpleFormatter
SimpleCov.minimum_coverage 0

SimpleCov.start do
  coverage_dir ENV.fetch("K_SOUP_COV_DIR", "coverage")
  enable_coverage :branch
  primary_coverage :branch
  track_files "lib/**/*.rb"
  track_files "lib/**/*.rake"
  track_files "exe/*.rb"
end

# Override command_name AFTER .start (so any .simplecov config doesn't clobber it).
# Each spawned process gets a unique name so results don't overwrite each other.
SimpleCov.command_name(
  "#{ENV.fetch("K_SOUP_COV_COMMAND_NAME", "RSpec (COVERAGE)")} (spawn:#{Process.pid})",
)
