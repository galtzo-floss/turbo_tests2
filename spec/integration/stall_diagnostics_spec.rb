# frozen_string_literal: true

require "turbo_tests2/rspec/shared_contexts/simplecov_spawn"

# End-to-end proof that a hung worker is diagnosable: a real nested run with
# a tiny watchdog must name the worker and example, and the worker must dump
# thread backtraces even though the example silenced $stderr.
RSpec.describe "TurboTests stall diagnostics integration", :check_output do
  # JVM engines take longer than the tiny watchdog used here just to start the
  # nested worker, so the report would legitimately say "no messages received".
  before { skip "timing-sensitive; needs a fast-starting engine" unless RUBY_ENGINE == "ruby" }

  include_context "with simplecov spawn coverage"

  it "reports the hung worker and dumps its threads" do
    env = {"TURBO_TESTS2_WATCHDOG_SECONDS" => "8", "TURBO_TESTS2_STACK_DUMP_SECONDS" => "2"}
    output = IO.popen(env, "bundle exec turbo_tests2 -n 1 ./fixtures/rspec/hanging_spec.rb 2>&1", &:read)

    expect(output).to match(/worker 1 \(pid \d+\): no exit message/)
    expect(output).to include("watchdog fired after 8.0s")
    expect(output).to match(/no example finished for .*current example: "\.\/fixtures\/rspec\/hanging_spec\.rb:\d+"/)
    expect(output).to include("--- #<Thread")
  end
end
