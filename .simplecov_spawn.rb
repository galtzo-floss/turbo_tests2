# frozen_string_literal: true

# Loaded via RUBYOPT ("-r./.simplecov_spawn") in spawned (non-fork) subprocesses
# to collect coverage from processes started with backticks, Open3, or Process.spawn.
#
# How this works:
#   `require "kettle-soup-cover"` sets up Kettle::Soup::Cover::Constants (and other
#   modules), mirroring what spec_helper.rb does. This must happen BEFORE simplecov
#   is loaded because our `.simplecov` file does `require "kettle/soup/cover/config"`,
#   and config.rb references Kettle::Soup::Cover::Constants directly.
#
#   `require "simplecov"` then loads the local `.simplecov` configuration.
#   That file configures coverage only; this spawn shim starts coverage for the
#   subprocess explicitly.
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
# .simplecov (and kettle/soup/cover/config inside it) references Kettle::Soup::Cover::Constants.
# That namespace is only available after the kettle-soup-cover main entry point is loaded.
# Mirror spec_helper.rb: require "kettle-soup-cover" first, then "simplecov".
#
# Disable resultset cleaning in spawned processes: each spawned process must NOT wipe
# .resultset.json or it would erase the accumulated coverage from other workers.
# Only the parent process (which initialises SimpleCov normally via spec_helper.rb) may clean.
ENV["K_SOUP_COV_CLEAN_RESULTSET"] = "false"
require "kettle-soup-cover"
require "simplecov"

SimpleCov.start

# Override to quiet mode: the parent process owns the formatted report.
SimpleCov.print_error_status = false
SimpleCov.formatter(SimpleCov::Formatter::SimpleFormatter)
SimpleCov.minimum_coverage(0)

# Each spawned process needs a unique command_name so results don't overwrite
# each other in .resultset.json. Set this AFTER start so .simplecov's own
# command_name setting doesn't clobber ours.
SimpleCov.command_name(
  "#{ENV.fetch("K_SOUP_COV_COMMAND_NAME", "RSpec (COVERAGE)")} (spawn:#{Process.pid})"
)
