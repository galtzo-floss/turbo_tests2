# frozen_string_literal: true

# Loaded via RUBYOPT ("-r./.simplecov_spawn") in spawned (non-fork) subprocesses
# to collect coverage from processes started with backticks, Open3, or Process.spawn.
#
# How this works:
#   `require "simplecov"` below causes Ruby to load simplecov's defaults module
#   (simplecov/defaults.rb), which searches upward from SimpleCov.root for a
#   `.simplecov` file and loads it immediately at require time. Our `.simplecov`
#   calls `SimpleCov.start`, so coverage measurement begins in that ONE call —
#   no second SimpleCov.start is needed or wanted here (calling Coverage.start
#   twice raises RuntimeError in Ruby 2.5+).
#
#   After that single start, we switch the process into quiet mode and assign a
#   unique command_name so each spawned process writes its own entry in
#   coverage/.resultset.json without clobbering others.
#
#   The parent test process has use_merging enabled (kettle-soup-cover default),
#   so all spawn results are automatically combined into the final report at exit.
#
# Usage — set in the test process before spawning, restore after:
#   ENV["RUBYOPT"] = "-r./.simplecov_spawn #{ENV["RUBYOPT"]}".strip
#
# See: https://github.com/simplecov-ruby/simplecov#running-simplecov-against-spawned-subprocesses
require "simplecov"

# .simplecov was auto-loaded above and already called SimpleCov.start.
# Override to quiet mode: the parent process owns the formatted report.
SimpleCov.print_error_status = false
SimpleCov.formatter SimpleCov::Formatter::SimpleFormatter
SimpleCov.minimum_coverage 0

# Each spawned process needs a unique command_name so results don't overwrite
# each other in .resultset.json. Set this AFTER start so .simplecov's own
# command_name setting doesn't clobber ours.
SimpleCov.command_name(
  "#{ENV.fetch("K_SOUP_COV_COMMAND_NAME", "RSpec (COVERAGE)")} (spawn:#{Process.pid})",
)
