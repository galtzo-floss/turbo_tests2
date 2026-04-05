# frozen_string_literal: true

require "spec_helper"

RSpec.describe TurboTests::Runner do
  def build_runner(**overrides)
    described_class.new(
      reporter: double("reporter"),
      formatters: [],
      start_time: RSpec::Core::Time.now,
      files: ["spec"],
      tags: [],
      runtime_log: nil,
      verbose: false,
      fail_fast: nil,
      count: nil,
      seed: nil,
      seed_used: false,
      print_failed_group: false,
      use_runtime_info: true,
      parallel_options: {},
      nice: false,
**overrides,
    )
  end

  describe "#fail_fast_met (private)" do
    context "when fail_fast is nil" do
      it "returns false regardless of failure count" do
        runner = build_runner(fail_fast: nil)
        expect(runner.send(:fail_fast_met)).to be false
      end
    end

    context "when fail_fast is set but threshold not reached" do
      it "returns false" do
        runner = build_runner(fail_fast: 3)
        expect(runner.send(:fail_fast_met)).to be false
      end
    end

    context "when fail_fast threshold is exactly met" do
      it "returns true" do
        runner = build_runner(fail_fast: 1)
        runner.instance_variable_set(:@failure_count, 1)
        expect(runner.send(:fail_fast_met)).to be true
      end
    end

    context "when fail_fast threshold is exceeded" do
      it "returns true" do
        runner = build_runner(fail_fast: 2)
        runner.instance_variable_set(:@failure_count, 5)
        expect(runner.send(:fail_fast_met)).to be true
      end
    end
  end

  describe "#start_subprocess (private) with empty tests" do
    it "enqueues an exit message and returns nil" do
      runner = build_runner
      result = runner.send(:start_subprocess, {}, [], [], 1, record_runtime: false)

      expect(result).to be_nil
      message = runner.instance_variable_get(:@messages).pop
      expect(message).to eq({type: "exit", process_id: 1})
    end

    it "uses the given process_id in the exit message" do
      runner = build_runner
      runner.send(:start_subprocess, {}, [], [], 42, record_runtime: false)

      message = runner.instance_variable_get(:@messages).pop
      expect(message[:process_id]).to eq(42)
    end
  end

  describe ".run class method" do
    let(:mock_reporter) { double("reporter") }

    before do
      allow(TurboTests::Reporter).to receive(:from_config).and_return(mock_reporter)
    end

    context "when files is ['spec'] (use_runtime_info = true)" do
      it "sets runtime_log in parallel_options and passes use_runtime_info: true" do
        runner_double = double("runner", run: 0)
        allow(described_class).to receive(:new) do |**opts|
          expect(opts[:use_runtime_info]).to be true
          expect(opts[:parallel_options]).to have_key(:runtime_log)
          runner_double
        end

        described_class.run(files: ["spec"], formatters: [], tags: [], parallel_options: {})
      end
    end

    context "when files is specific paths (use_runtime_info = false)" do
      it "sets group_by: :filesize in parallel_options and passes use_runtime_info: false" do
        runner_double = double("runner", run: 0)
        allow(described_class).to receive(:new) do |**opts|
          expect(opts[:use_runtime_info]).to be false
          expect(opts[:parallel_options][:group_by]).to eq(:filesize)
          runner_double
        end

        described_class.run(
          files: ["spec/turbo_tests/cli_spec.rb"],
          formatters: [],
          tags: [],
          parallel_options: {},
        )
      end
    end

    context "when verbose: true" do
      it "outputs VERBOSE warning" do
        runner_double = double("runner", run: 0)
        allow(described_class).to receive(:new).and_return(runner_double)

        expect {
          described_class.run(files: ["spec"], formatters: [], tags: [], verbose: true, parallel_options: {})
        }.to output("VERBOSE\n").to_stderr
      end
    end
  end

  describe "#handle_messages (private)" do
    let(:reporter) { double("reporter", message: nil, error_outside_of_examples: nil) }

    def build_runner_for_messages(**overrides)
      runner = build_runner(reporter: reporter, **overrides)
      runner.instance_variable_set(:@num_processes, 1)
      runner
    end

    def enqueue_then_exit(runner, *messages)
      messages.each { |m| runner.instance_variable_get(:@messages) << m }
      runner.instance_variable_get(:@messages) << {type: "exit", process_id: 1}
    end

    it "handles 'seed' message (no-op)" do
      runner = build_runner_for_messages
      enqueue_then_exit(runner, {type: "seed", seed: 1234})
      expect { runner.send(:handle_messages) }.not_to raise_error
    end

    it "handles 'close' message (no-op)" do
      runner = build_runner_for_messages
      enqueue_then_exit(runner, {type: "close"})
      expect { runner.send(:handle_messages) }.not_to raise_error
    end

    it "handles 'error' message (no-op)" do
      runner = build_runner_for_messages
      enqueue_then_exit(runner, {type: "error"})
      expect { runner.send(:handle_messages) }.not_to raise_error
    end

    it "handles 'message' with a regular (non-error) message via reporter.message" do
      runner = build_runner_for_messages
      expect(reporter).to receive(:message).with("some regular message")
      enqueue_then_exit(runner, {type: "message", message: "some regular message"})
      runner.send(:handle_messages)
    end

    it "warns about unhandled message types" do
      runner = build_runner_for_messages
      enqueue_then_exit(runner, {type: "unknown_type", data: "something"})
      expect { runner.send(:handle_messages) }.to output(/Unhandled message/).to_stderr
    end

    it "continues looping when not all processes have exited yet" do
      runner = build_runner_for_messages
      runner.instance_variable_set(:@num_processes, 2)
      queue = runner.instance_variable_get(:@messages)
      # First exit: exited==1, @num_processes==2 → else branch (don't break)
      # Second exit: exited==2, @num_processes==2 → break
      queue << {type: "exit", process_id: 1}
      queue << {type: "exit", process_id: 2}
      expect { runner.send(:handle_messages) }.not_to raise_error
    end

    context "when fail_fast threshold is met on example_failed" do
      it "kills all threads and breaks out of the message loop" do
        runner = build_runner_for_messages(fail_fast: 1)
        runner.instance_variable_set(:@failure_count, 0)

        mock_thread = double("thread")
        expect(mock_thread).to receive(:kill)
        runner.instance_variable_set(:@threads, [mock_thread])

        reporter_with_fail = double("reporter", example_failed: nil)
        runner.instance_variable_set(:@reporter, reporter_with_fail)

        fake_example = double("example")
        allow(TurboTests::FakeExample).to receive(:from_obj).and_return(fake_example)
        allow(reporter_with_fail).to receive(:example_failed).with(fake_example)

        runner.instance_variable_get(:@messages) << {type: "example_failed", example: {id: "1"}}

        expect { runner.send(:handle_messages) }.not_to raise_error
      end
    end
  end

  describe "#handle_interrupt (private)" do
    it "calls Kernel.exit on second interrupt" do
      runner = build_runner
      runner.instance_variable_set(:@interrupt_handled, true)
      runner.instance_variable_set(:@wait_threads, [])
      expect(Kernel).to receive(:exit)
      runner.send(:handle_interrupt)
    end

    it "shuts down subprocesses on first interrupt" do
      runner = build_runner
      runner.instance_variable_set(:@interrupt_handled, false)
      runner.instance_variable_set(:@wait_threads, [])
      runner.send(:handle_interrupt)
      expect(runner.instance_variable_get(:@interrupt_handled)).to be true
    end

    it "sends INT signal to each subprocess and rescues Errno::ESRCH" do
      runner = build_runner
      runner.instance_variable_set(:@interrupt_handled, false)

      wait_thr = double("wait_thr", pid: 99999)
      runner.instance_variable_set(:@wait_threads, [wait_thr])

      allow(Process).to receive(:getpgid).with(99999).and_return(0)
      allow(Process).to receive(:kill).with(:INT, 99999).and_raise(Errno::ESRCH)

      expect { runner.send(:handle_interrupt) }.not_to raise_error
      expect(runner.instance_variable_get(:@interrupt_handled)).to be true
    end

    it "rescues Errno::ENOENT when subprocess is already gone" do
      runner = build_runner
      runner.instance_variable_set(:@interrupt_handled, false)

      wait_thr = double("wait_thr", pid: 99999)
      runner.instance_variable_set(:@wait_threads, [wait_thr])

      allow(Process).to receive(:getpgid).with(99999).and_return(0)
      allow(Process).to receive(:kill).with(:INT, 99999).and_raise(Errno::ENOENT)

      expect { runner.send(:handle_interrupt) }.not_to raise_error
      expect(runner.instance_variable_get(:@interrupt_handled)).to be true
    end

    it "falls back to pgid=0 when Process does not respond to :getpgid" do
      runner = build_runner
      runner.instance_variable_set(:@interrupt_handled, false)

      wait_thr = double("wait_thr", pid: 99999)
      runner.instance_variable_set(:@wait_threads, [wait_thr])

      allow(Process).to receive(:respond_to?).and_call_original
      allow(Process).to receive(:respond_to?).with(:getpgid).and_return(false)
      # pgid = 0 (fallback), Process.pid != 0, so kill is attempted
      allow(Process).to receive(:kill).with(:INT, 99999).and_raise(Errno::ESRCH)

      expect { runner.send(:handle_interrupt) }.not_to raise_error
      expect(runner.instance_variable_get(:@interrupt_handled)).to be true
    end

    it "skips INT signal when pgid equals Process.pid" do
      runner = build_runner
      runner.instance_variable_set(:@interrupt_handled, false)

      wait_thr = double("wait_thr", pid: 99999)
      runner.instance_variable_set(:@wait_threads, [wait_thr])

      # When getpgid returns Process.pid, the kill is skipped (else branch of line 154)
      allow(Process).to receive(:getpgid).with(99999).and_return(Process.pid)
      expect(Process).not_to receive(:kill)

      runner.send(:handle_interrupt)
      expect(runner.instance_variable_get(:@interrupt_handled)).to be true
    end
  end

  describe "#report_failed_group (private)" do
    it "prints the test files belonging to each failed process group" do
      runner = build_runner
      failed_status = double("process_status", success?: false)
      success_status = double("process_status", success?: true)

      threads = [
        double("thread", value: failed_status),
        double("thread", value: success_status),
      ]
      runner.instance_variable_set(:@wait_threads, threads)

      tests_in_groups = [["spec/foo_spec.rb", "spec/bar_spec.rb"], ["spec/baz_spec.rb"]]

      expect { runner.send(:report_failed_group, tests_in_groups) }
        .to output(/Group that failed: spec\/foo_spec.rb spec\/bar_spec.rb/).to_stdout
    end
  end

  describe "#start_subprocess with non-empty tests (private)" do
    let!(:runner) { build_runner }
    let(:tests) { ["spec/turbo_tests/runner_spec.rb"] }
    let(:fake_stdin) { double("stdin", close: nil) }
    let(:fake_wait_thr) { double("wait_thr", pid: 99999, value: double("status", success?: true)) }

    def mock_open3(runner_instance, &extra)
      allow(Open3).to receive(:popen3) do |*args|
        r1, w1 = IO.pipe
        r2, w2 = IO.pipe
        w1.close
        w2.close
        extra&.call(*args)
        [fake_stdin, r1, r2, fake_wait_thr]
      end
    end

    after do
      runner.instance_variable_get(:@threads).each { |t| t.join(2) }
    end

    it "uses RSPEC_EXECUTABLE as the command when set" do
      captured = []
      mock_open3(runner) { |*args| captured.replace(args) }

      begin
        old = ENV["RSPEC_EXECUTABLE"]
        ENV["RSPEC_EXECUTABLE"] = "my_rspec --flag"
        runner.send(:start_subprocess, {}, [], tests, 1, record_runtime: false)
      ensure
        old ? ENV["RSPEC_EXECUTABLE"] = old : ENV.delete("RSPEC_EXECUTABLE")
      end

      # env hash is first arg; command args follow
      expect(captured[1]).to eq("my_rspec")
      expect(captured[2]).to eq("--flag")
    end

    it "uses BUNDLE_BIN_PATH when RSPEC_EXECUTABLE is absent" do
      captured = []
      mock_open3(runner) { |*args| captured.replace(args) }

      begin
        old_rspec = ENV.delete("RSPEC_EXECUTABLE")
        old_bundle = ENV["BUNDLE_BIN_PATH"]
        ENV["BUNDLE_BIN_PATH"] = "/usr/local/bin/bundle"
        runner.send(:start_subprocess, {}, [], tests, 1, record_runtime: false)
      ensure
        ENV["RSPEC_EXECUTABLE"] = old_rspec if old_rspec
        old_bundle ? ENV["BUNDLE_BIN_PATH"] = old_bundle : ENV.delete("BUNDLE_BIN_PATH")
      end

      expect(captured[1]).to eq("/usr/local/bin/bundle")
      expect(captured[2]).to eq("exec")
    end

    it "prepends 'nice' when @nice is true" do
      runner.instance_variable_set(:@nice, true)
      captured = []
      mock_open3(runner) { |*args| captured.replace(args) }

      begin
        old = ENV.delete("RSPEC_EXECUTABLE")
        runner.send(:start_subprocess, {}, [], tests, 1, record_runtime: false)
      ensure
        ENV["RSPEC_EXECUTABLE"] = old if old
      end

      expect(captured[1]).to eq("nice")
    end

    it "logs the command when @verbose is true" do
      runner.instance_variable_set(:@verbose, true)
      mock_open3(runner)

      begin
        old = ENV.delete("RSPEC_EXECUTABLE")
        expect { runner.send(:start_subprocess, {}, [], tests, 1, record_runtime: false) }
          .to output(/Process 1/).to_stderr
      ensure
        ENV["RSPEC_EXECUTABLE"] = old if old
      end
    end

    it "includes record_runtime options when record_runtime is true" do
      captured = []
      mock_open3(runner) { |*args| captured.replace(args) }

      begin
        old = ENV.delete("RSPEC_EXECUTABLE")
        runner.send(:start_subprocess, {}, [], tests, 1, record_runtime: true)
      ensure
        ENV["RSPEC_EXECUTABLE"] = old if old
      end

      expect(captured).to include("ParallelTests::RSpec::RuntimeLogger")
    end

    it "uses plain 'rspec' string when neither RSPEC_EXECUTABLE nor BUNDLE_BIN_PATH is set" do
      captured = []
      mock_open3(runner) { |*args| captured.replace(args) }

      begin
        old_rspec = ENV.delete("RSPEC_EXECUTABLE")
        old_bundle = ENV.delete("BUNDLE_BIN_PATH")
        runner.send(:start_subprocess, {}, [], tests, 1, record_runtime: false)
      ensure
        ENV["RSPEC_EXECUTABLE"] = old_rspec if old_rspec
        ENV["BUNDLE_BIN_PATH"] = old_bundle if old_bundle
      end

      # command_name = "rspec" (string), [*"rspec"] = ["rspec"], first arg after env hash
      expect(captured[1]).to eq("rspec")
    end

    context "when stdout contains lines with and without the formatter output ID" do
      let(:output_id) { "fixed-test-output-id" }

      before { allow(SecureRandom).to receive(:uuid).and_return(output_id) }

      def mock_open3_with_stdout(content)
        r1, w1 = IO.pipe
        r2, w2 = IO.pipe
        w1.write(content)
        w1.close
        w2.close
        allow(Open3).to receive(:popen3).and_return([fake_stdin, r1, r2, fake_wait_thr])
      end

      it "prints non-blank initial content before the output ID to $stdout" do
        json_msg = {type: "seed", seed: 1234}.to_json
        mock_open3_with_stdout("prefix_content#{output_id}#{json_msg}\n")

        expect {
          runner.send(:start_subprocess, {}, [], tests, 1, record_runtime: false)
          runner.instance_variable_get(:@threads).each { |t| t.join(2) }
        }.to output("prefix_content").to_stdout
      end

      it "skips lines that contain no formatter output ID (message is nil)" do
        # A plain line without the output_id: result.shift(×2) gives initial + nil message
        # → `next unless message` is taken, no JSON parse attempted
        mock_open3_with_stdout("plain rspec output without output id\n")

        expect {
          runner.send(:start_subprocess, {}, [], tests, 1, record_runtime: false)
          runner.instance_variable_get(:@threads).each { |t| t.join(2) }
        }.not_to raise_error
      end
    end
  end

  describe "#run (instance method)" do
    context "when print_failed_group is true" do
      it "calls report_failed_group after messages are handled" do
        reporter = double("reporter", failed_examples: [])
        runner = build_runner(print_failed_group: true, reporter: reporter)

        allow(ParallelTests).to receive(:determine_number_of_processes).and_return(0)
        allow(ParallelTests::RSpec::Runner).to receive_messages(tests_with_size: [], tests_in_groups: [])
        allow(reporter).to receive(:report).and_yield(reporter)
        allow(Signal).to receive(:trap).and_return(nil)
        allow(runner).to receive(:handle_messages)

        expect(runner).to receive(:report_failed_group).with([])
        runner.run
      end
    end
  end
end
