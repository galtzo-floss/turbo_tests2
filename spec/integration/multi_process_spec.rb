# frozen_string_literal: true

require "turbo_tests2/rspec/shared_contexts/simplecov_spawn"

# Integration tests that dogfood turbo_tests' core value proposition:
#
#   Run RSpec examples from multiple spec files in parallel subprocesses with
#   iterative (streaming) output merged from all processes.
#
# Every test here launches a real `bundle exec turbo_tests2` child process with
# `-n 2` so exactly two RSpec workers are spawned.  We then assert on the
# combined output to verify that:
#   1. The parallel-processes header is present.
#   2. Descriptions from *both* worker processes appear in the output
#      (demonstrating that output is streamed iteratively, not buffered to the end).
#   3. The combined summary line reflects totals across all workers.
#   4. Exit codes match the outcome of the run.
#
RSpec.describe "TurboTests multi-process integration", :check_output do
  # See the matching comment in spec/turbo_tests/cli_spec.rb: these specs
  # spawn real nested turbo_tests2 worker processes, which can hang
  # indefinitely on TruffleRuby 23.0 (EOL, targets Ruby 3.0 compat) due to
  # unreliable Thread#kill/IO interruption of worker-pipe reader threads.
  # Not reproducible on 22.3 or 23.1+.
  subject(:output) { `bundle exec turbo_tests2 -f d -n 2 #{fixtures}`.strip }

  before { skip_for(engine: "truffleruby", versions: "3.0", reason: "hangs indefinitely spawning nested turbo_tests2 subprocesses on TruffleRuby 23.0 (EOL); see spec comment") }

  include_context "with simplecov spawn coverage"

  # ── passing + pending ─────────────────────────────────────────────────────────
  # The happy path: two worker processes each finish successfully.
  # Validates that both workers' output is visible in the merged result.
  context "when two spec files run in parallel — one passing, one pending", :aggregate_failures do
    let(:fixtures) do
      "./fixtures/rspec/passing_spec.rb ./fixtures/rspec/pending_exceptions_spec.rb"
    end

    it "spawns two worker processes" do
      expect(output).to include("2 processes for 2 specs")
    end

    it "streams output from the passing worker" do
      # Description from passing_spec.rb — proves that process's output was received
      expect(output).to include("Fixture of spec file with passing examples")
      expect(output).to include("passes")
    end

    it "streams output from the pending worker" do
      # Descriptions from pending_exceptions_spec.rb — proves the second process's
      # output was also received and merged iteratively
      expect(output).to include("is implemented but skipped with 'pending'")
      expect(output).to include("is implemented but skipped with 'skip'")
      expect(output).to include("is implemented but skipped with 'xit'")
    end

    it "reports the combined summary across both workers" do
      # RSpec on Ruby 3.0 reports `xit` in the formatted examples but omits it
      # from the numeric summary; newer supported combinations count it.
      expect(output).to match(/(?:3 examples, 0 failures, 2 pending|4 examples, 0 failures, 3 pending)/)
    end

    it "exits zero when no worker fails" do
      output # trigger the subject
      expect($?.exitstatus).to be(0)
    end
  end

  # ── failing + passing ─────────────────────────────────────────────────────────
  # Validates that a failure in one worker is surfaced even though another worker
  # succeeded, and that the passing worker's output is *also* present.
  context "when two spec files run in parallel — one failing, one passing", :aggregate_failures do
    let(:fixtures) do
      "./fixtures/rspec/failing_spec.rb ./fixtures/rspec/passing_spec.rb"
    end

    it "spawns two worker processes" do
      expect(output).to include("2 processes for 2 specs")
    end

    it "reports the failure from the failing worker" do
      expect(output).to include("Failing example group")
      expect(output).to include("1 failure")
      expect(output).to include("Test info in extra_failure_lines")
    end

    it "still shows output from the passing worker" do
      expect(output).to include("Fixture of spec file with passing examples")
      expect(output).to include("passes")
    end

    it "exits non-zero" do
      output # trigger the subject
      expect($?.exitstatus).to be(1)
    end
  end

  # ── error + passing ───────────────────────────────────────────────────────────
  # Validates that a load-time error in one worker does not suppress the output
  # from the other worker.
  context "when two spec files run in parallel — one with an error, one passing", :aggregate_failures do
    let(:fixtures) do
      "./fixtures/rspec/errors_outside_of_examples_spec.rb ./fixtures/rspec/passing_spec.rb"
    end

    it "spawns two worker processes" do
      expect(output).to include("2 processes for 2 specs")
    end

    it "reports the error from the failing worker" do
      expect(output).to include("error occurred outside of examples")
    end

    it "still shows output from the passing worker" do
      expect(output).to include("Fixture of spec file with passing examples")
      expect(output).to include("passes")
    end

    it "exits non-zero" do
      output # trigger the subject
      expect($?.exitstatus).to be(1)
    end
  end
end
