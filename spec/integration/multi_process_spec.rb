# frozen_string_literal: true

# Integration tests that dogfood turbo_tests' core value proposition:
#
#   Run RSpec examples from multiple spec files in parallel subprocesses with
#   iterative (streaming) output merged from all processes.
#
# Every test here launches a real `bundle exec turbo_tests` child process with
# `-n 2` so exactly two RSpec workers are spawned.  We then assert on the
# combined output to verify that:
#   1. The parallel-processes header is present.
#   2. Descriptions from *both* worker processes appear in the output
#      (demonstrating that output is streamed iteratively, not buffered to the end).
#   3. The combined summary line reflects totals across all workers.
#   4. Exit codes match the outcome of the run.
#
RSpec.describe "TurboTests multi-process integration", :check_output do
  subject(:output) { %x(bundle exec turbo_tests -f d -n 2 #{fixtures}).strip }

  # Inject the SimpleCov spawn shim into subprocesses when coverage is active,
  # mirroring the setup in cli_spec.rb.
  around do |example|
    if defined?(SimpleCov) && SimpleCov.running
      original_rubyopt = ENV.fetch("RUBYOPT", nil)
      ENV["RUBYOPT"] = "-r./.simplecov_spawn #{original_rubyopt}".strip
      example.run
      ENV["RUBYOPT"] = original_rubyopt
    else
      example.run
    end
  end

  # ── passing + pending ─────────────────────────────────────────────────────────
  # The happy path: two worker processes each finish successfully.
  # Validates that both workers' output is visible in the merged result.
  context "when two spec files run in parallel — one passing, one pending", :aggregate_failures do
    let(:fixtures) do
      "./fixtures/rspec/passing_spec.rb ./fixtures/rspec/pending_exceptions_spec.rb"
    end

    it "spawns two worker processes" do
      expect(output).to match(/2 processes for 2 specs/)
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
      expect(output).to include("4 examples, 0 failures, 3 pending")
    end

    it "exits zero when no worker fails" do
      output # trigger the subject
      expect($CHILD_STATUS.exitstatus).to be(0)
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
      expect(output).to match(/2 processes for 2 specs/)
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
      expect($CHILD_STATUS.exitstatus).to be(1)
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
      expect(output).to match(/2 processes for 2 specs/)
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
      expect($CHILD_STATUS.exitstatus).to be(1)
    end
  end
end
