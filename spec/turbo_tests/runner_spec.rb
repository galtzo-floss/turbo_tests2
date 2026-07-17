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
      **overrides
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

    it "generates and reports a seed by default" do
      runner_double = double("runner", run: 0)
      allow(described_class).to receive(:generate_seed).and_return("12345")
      allow(described_class).to receive(:new) do |**opts|
        expect(opts[:seed]).to eq("12345")
        expect(opts[:seed_used]).to be true
        runner_double
      end

      allow(TurboTests::Reporter).to receive(:from_config).and_return(mock_reporter)

      described_class.run(files: ["spec"], formatters: [], tags: [], parallel_options: {})

      expect(TurboTests::Reporter).to have_received(:from_config).with([], anything, "12345", true, ["spec"], anything)
    end

    it "uses RSpec configuration for default file discovery" do
      runner_double = double("runner", run: 0)
      allow(described_class).to receive(:rspec_configured_files_to_run).and_return(["gems/example/spec/example_spec.rb"])
      allow(described_class).to receive(:new) do |**opts|
        expect(opts[:files]).to eq(["gems/example/spec/example_spec.rb"])
        expect(opts[:use_runtime_info]).to be true
        runner_double
      end

      described_class.run(formatters: [], tags: [], parallel_options: {})

      expect(TurboTests::Reporter).to have_received(:from_config).with(
        [],
        anything,
        anything,
        true,
        ["gems/example/spec/example_spec.rb"],
        anything
      )
    end

    it "does not use RSpec configuration when explicit files are provided" do
      runner_double = double("runner", run: 0)
      expect(described_class).not_to receive(:rspec_configured_files_to_run)
      allow(described_class).to receive(:new).and_return(runner_double)

      described_class.run(
        files: ["spec/turbo_tests/runner_spec.rb"],
        formatters: [],
        tags: [],
        parallel_options: {}
      )
    end

    it "groups file:line selectors by real file path while preserving RSpec locations" do
      runner_double = double("runner", run: 0)
      allow(described_class).to receive(:new) do |**opts|
        expect(opts[:files]).to eq(["spec/turbo_tests/runner_spec.rb"])
        expect(opts[:test_selectors]).to eq(
          "spec/turbo_tests/runner_spec.rb" => [
            "spec/turbo_tests/runner_spec.rb:279",
            "spec/turbo_tests/runner_spec.rb:884"
          ]
        )
        runner_double
      end

      described_class.run(
        files: ["spec/turbo_tests/runner_spec.rb:279", "spec/turbo_tests/runner_spec.rb:884"],
        formatters: [],
        tags: [],
        parallel_options: {}
      )
    end

    it "treats an explicit empty files array as a no-op run" do
      runner_double = double("runner", run: 0)
      expect(described_class).not_to receive(:rspec_configured_files_to_run)
      allow(described_class).to receive(:new) do |**opts|
        expect(opts[:files]).to be_empty
        expect(opts[:use_runtime_info]).to be false
        runner_double
      end

      described_class.run(files: [], formatters: [], tags: [], parallel_options: {})

      expect(TurboTests::Reporter).to have_received(:from_config).with(
        [],
        anything,
        anything,
        true,
        be_empty,
        anything
      )
    end

    it "uses the explicit seed when provided" do
      runner_double = double("runner", run: 0)
      expect(described_class).not_to receive(:generate_seed)
      allow(described_class).to receive(:new) do |**opts|
        expect(opts[:seed]).to eq("42")
        expect(opts[:seed_used]).to be true
        runner_double
      end

      described_class.run(files: ["spec"], formatters: [], tags: [], seed: "42", parallel_options: {})
    end

    it "does not generate a seed for defined order" do
      runner_double = double("runner", run: 0)
      expect(described_class).not_to receive(:generate_seed)
      allow(described_class).to receive(:new) do |**opts|
        expect(opts[:order]).to eq("defined")
        expect(opts[:seed]).to be_nil
        expect(opts[:seed_used]).to be false
        runner_double
      end

      allow(TurboTests::Reporter).to receive(:from_config).and_return(mock_reporter)

      described_class.run(files: ["spec"], formatters: [], tags: [], order: "defined", parallel_options: {})

      expect(TurboTests::Reporter).to have_received(:from_config).with([], anything, nil, false, ["spec"], anything)
    end

    context "when files are discovered by RSpec configuration (use_runtime_info = true)" do
      it "sets the default runtime_log in parallel_options and passes use_runtime_info: true" do
        runner_double = double("runner", run: 0)
        allow(described_class).to receive(:rspec_configured_files_to_run).and_return(["spec/turbo_tests/runner_spec.rb"])
        allow(described_class).to receive(:new) do |**opts|
          expect(opts[:use_runtime_info]).to be true
          expect(opts[:runtime_log]).to eq(TurboTests::Runner::DEFAULT_RUNTIME_LOG)
          expect(opts[:parallel_options]).to include(runtime_log: TurboTests::Runner::DEFAULT_RUNTIME_LOG)
          runner_double
        end

        described_class.run(formatters: [], tags: [], parallel_options: {})
      end

      it "uses filesize grouping by default when only_group is selected" do
        runner_double = double("runner", run: 0)
        allow(described_class).to receive(:rspec_configured_files_to_run).and_return(["spec/turbo_tests/runner_spec.rb"])
        allow(described_class).to receive(:new) do |**opts|
          expect(opts[:parallel_options]).to include(
            only_group: [2],
            group_by: :filesize
          )
          runner_double
        end

        described_class.run(formatters: [], tags: [], parallel_options: {only_group: [2]})
      end
    end

    context "when files is specific paths (use_runtime_info = false)" do
      it "sets group_by: :filesize while still configuring runtime logging" do
        runner_double = double("runner", run: 0)
        allow(described_class).to receive(:new) do |**opts|
          expect(opts[:use_runtime_info]).to be false
          expect(opts[:runtime_log]).to eq(TurboTests::Runner::DEFAULT_RUNTIME_LOG)
          expect(opts[:parallel_options][:runtime_log]).to eq(TurboTests::Runner::DEFAULT_RUNTIME_LOG)
          expect(opts[:parallel_options][:group_by]).to eq(:filesize)
          runner_double
        end

        described_class.run(
          files: ["spec/turbo_tests/cli_spec.rb"],
          formatters: [],
          tags: [],
          parallel_options: {}
        )
      end
    end

    context "when example_status_log is provided" do
      it "converts it to a runtime log and leaves grouping runtime-aware" do
        runner_double = double("runner", run: 0)
        allow(described_class).to receive(:runtime_log_from_example_status).with("spec/examples.txt").and_return("tmp/status_runtime.log")
        allow(described_class).to receive(:new) do |**opts|
          expect(opts[:runtime_log]).to eq("tmp/status_runtime.log")
          expect(opts[:parallel_options]).to include(runtime_log: "tmp/status_runtime.log")
          expect(opts[:parallel_options]).not_to have_key(:group_by)
          runner_double
        end

        described_class.run(
          files: ["spec/turbo_tests/cli_spec.rb"],
          formatters: [],
          tags: [],
          example_status_log: "spec/examples.txt",
          parallel_options: {}
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

  describe ".runtime_log_from_example_status" do
    it "writes passed example runtimes grouped by spec file" do
      Dir.mktmpdir do |dir|
        begin
          status_log = File.join(dir, "examples.txt")
          File.write(
            status_log,
            <<~STATUS
              example_id             | status | run_time        |
              ---------------------- | ------ | --------------- |
              spec/a_spec.rb[1:1]    | passed | 0.1 seconds     |
              spec/a_spec.rb[1:2]    | passed | 0.25 seconds    |
              spec/b_spec.rb[1:1]    | failed | 3.0 seconds     |
            STATUS
          )

          runtime_log = described_class.runtime_log_from_example_status(status_log)

          expect(File.read(runtime_log)).to eq("spec/a_spec.rb:0.35")
        ensure
          FileUtils.rm_f(File.join("tmp", "turbo_tests2_example_status_runtime.log"))
        end
      end
    end
  end

  describe ".rspec_configured_files_to_run" do
    it "loads RSpec options and returns relative paths" do
      files = described_class.rspec_configured_files_to_run

      expect(files).to include("spec/turbo_tests/runner_spec.rb")
      expect(files).to all(satisfy { |path| !path.start_with?(Dir.pwd) })
    end

    it "honors .rspec --pattern when no root spec directory exists" do
      Dir.mktmpdir("turbo-tests2-rspec-config") do |dir|
        File.write(File.join(dir, ".rspec"), <<~RSPEC)
          --require ./gems/example/spec/spec_helper
          --pattern gems/*/spec/**/*_spec.rb
        RSPEC
        FileUtils.mkdir_p(File.join(dir, "gems", "example", "spec"))
        File.write(File.join(dir, "gems", "example", "spec", "spec_helper.rb"), "")
        File.write(File.join(dir, "gems", "example", "spec", "example_spec.rb"), <<~RUBY)
          RSpec.describe "configured discovery" do
            it "runs" do
              expect(true).to be(true)
            end
          end
        RUBY

        stdout, stderr, status = Open3.capture3(
          RbConfig.ruby,
          "-I#{File.expand_path("../../lib", __dir__)}",
          "-rturbo_tests/runner",
          "-rjson",
          "-e",
          "puts JSON.dump(TurboTests::Runner.rspec_configured_files_to_run)",
          chdir: dir
        )

        expect(status).to be_success, stderr
        expect(JSON.parse(stdout)).to eq(["gems/example/spec/example_spec.rb"])
      end
    end
  end

  describe "#handle_messages (private)" do
    let(:reporter) { double("reporter", message: nil, error_outside_of_examples: nil, deprecation: nil, profile: nil) }

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

    it "collapses duplicate Run options messages from workers" do
      runner = build_runner_for_messages
      runner.instance_variable_set(:@num_processes, 2)
      queue = runner.instance_variable_get(:@messages)
      expect(reporter).to receive(:message).with("Run options: exclude {skip_ci: true}").once
      queue << {type: "message", process_id: 1, message: "Run options: exclude {skip_ci: true}"}
      queue << {type: "message", process_id: 2, message: "Run options: exclude {skip_ci: true}"}
      queue << {type: "exit", process_id: 1}
      queue << {type: "exit", process_id: 2}

      runner.send(:handle_messages)
    end

    it "summarizes distinct Run options messages by worker" do
      runner = build_runner_for_messages
      runner.instance_variable_set(:@num_processes, 2)
      queue = runner.instance_variable_get(:@messages)
      queue << {type: "message", process_id: 1, message: "Run options: include {locations: {\"./a_spec.rb\" => [1]}}"}
      queue << {type: "message", process_id: 2, message: "Run options: include {locations: {\"./b_spec.rb\" => [2]}}"}
      queue << {type: "exit", process_id: 1}
      queue << {type: "exit", process_id: 2}

      expect(reporter).to receive(:message).with(<<~MESSAGE.chomp)
        Run options by worker:
          workers 1: Run options: include {locations: {"./a_spec.rb" => [1]}}
          workers 2: Run options: include {locations: {"./b_spec.rb" => [2]}}
      MESSAGE

      runner.send(:handle_messages)
    end

    it "handles 'deprecation' via reporter.deprecation" do
      deprecation = {message: "deprecated"}
      runner = build_runner_for_messages
      expect(reporter).to receive(:deprecation).with(deprecation)
      enqueue_then_exit(runner, {type: "deprecation", deprecation: deprecation})
      runner.send(:handle_messages)
    end

    it "handles 'profile' via reporter.profile" do
      profile = {duration: 1.23}
      runner = build_runner_for_messages
      expect(reporter).to receive(:profile).with(profile)
      enqueue_then_exit(runner, {type: "profile", profile: profile})
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

    it "records exited process ids" do
      runner = build_runner_for_messages
      runner.instance_variable_get(:@messages) << {type: "exit", process_id: 1}
      runner.send(:handle_messages)

      expect(runner.instance_variable_get(:@exited_process_ids)).to eq([1])
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

        runner.instance_variable_set(:@tests_in_groups, [["spec/failing_spec.rb"], ["spec/skipped_spec.rb"]])
        runner.instance_variable_set(:@exited_process_ids, [1])
        runner.instance_variable_get(:@messages) << {type: "example_failed", example: {id: "1"}}

        expect { runner.send(:handle_messages) }
          .to output(/Groups stopped by fail-fast:\n  1\) spec\/skipped_spec\.rb/).to_stdout
      end
    end
  end

  describe ".worker_spec_opts" do
    before do
      allow(described_class).to receive(:project_rspec_options).and_return([])
    end

    it "removes RSpec file discovery options from worker commands" do
      expect(
        described_class.worker_spec_opts(
          [
            "--require", "spec_helper",
            "--pattern", "gems/*/spec/**/*_spec.rb",
            "-I", "spec",
            "--default-path", "gems",
            "--format", "documentation"
          ]
        )
      ).to eq(["--require", "spec_helper", "-I", "spec", "--format", "documentation"])
    end

    it "removes inline RSpec file discovery options from worker commands" do
      expect(
        described_class.worker_spec_opts(
          [
            "--pattern=gems/*/spec/**/*_spec.rb",
            "-Pspec/**/*_spec.rb",
            "--default-path=gems",
            "--color"
          ]
        )
      ).to eq(["--color"])
    end
  end

  describe ".project_rspec_options" do
    it "reads shell-style options from project RSpec option files" do
      Dir.mktmpdir("turbo-tests2-rspec-options") do |dir|
        File.write(File.join(dir, ".rspec"), "--require spec_helper\n--format documentation\n")
        File.write(File.join(dir, ".rspec-local"), "--tag ~slow\n")

        expect(described_class.project_rspec_options(dir)).to eq(
          ["--require", "spec_helper", "--format", "documentation", "--tag", "~slow"]
        )
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

    it "prints unfinished groups on first interrupt" do
      runner = build_runner
      runner.instance_variable_set(:@interrupt_handled, false)
      runner.instance_variable_set(:@wait_threads, [])
      runner.instance_variable_set(:@tests_in_groups, [["spec/finished_spec.rb"], ["spec/running_spec.rb"]])
      runner.instance_variable_set(:@exited_process_ids, [1])

      expect { runner.send(:handle_interrupt) }
        .to output(/Groups not finished:\n  1\) spec\/running_spec\.rb/).to_stdout
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
        double("thread", value: success_status)
      ]
      runner.instance_variable_set(:@wait_threads, threads)

      tests_in_groups = [["spec/foo_spec.rb", "spec/bar_spec.rb"], ["spec/baz_spec.rb"]]

      expect { runner.send(:report_failed_group, tests_in_groups) }
        .to output(/Group that failed: spec\/foo_spec.rb spec\/bar_spec.rb/).to_stdout
    end
  end

  describe "#report_unfinished_groups (private)" do
    it "does not print when every group has exited" do
      runner = build_runner
      runner.instance_variable_set(:@tests_in_groups, [["spec/one_spec.rb"]])
      runner.instance_variable_set(:@exited_process_ids, [1])

      expect { runner.send(:report_unfinished_groups, "Unfinished") }.not_to output.to_stdout
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

      stub_env("RSPEC_EXECUTABLE" => "my_rspec --flag")
      runner.send(:start_subprocess, {}, [], tests, 1, record_runtime: false)

      # env hash is first arg; command args follow
      expect(captured[1]).to eq("my_rspec")
      expect(captured[2]).to eq("--flag")
    end

    it "uses BUNDLE_BIN_PATH when RSPEC_EXECUTABLE is absent" do
      captured = []
      mock_open3(runner) { |*args| captured.replace(args) }

      hide_env("RSPEC_EXECUTABLE")
      stub_env("BUNDLE_BIN_PATH" => "/usr/local/bin/bundle")
      runner.send(:start_subprocess, {}, [], tests, 1, record_runtime: false)

      expect(captured[1]).to eq("/usr/local/bin/bundle")
      expect(captured[2]).to eq("exec")
    end

    it "prepends 'nice' when @nice is true" do
      runner.instance_variable_set(:@nice, true)
      captured = []
      mock_open3(runner) { |*args| captured.replace(args) }

      hide_env("RSPEC_EXECUTABLE")
      runner.send(:start_subprocess, {}, [], tests, 1, record_runtime: false)

      expect(captured[1]).to eq("nice")
    end

    it "logs the command when @verbose is true" do
      runner.instance_variable_set(:@verbose, true)
      mock_open3(runner)

      hide_env("RSPEC_EXECUTABLE")
      expect { runner.send(:start_subprocess, {}, [], tests, 1, record_runtime: false) }
        .to output(/Process 1/).to_stderr
    end

    it "includes record_runtime options when record_runtime is true" do
      captured = []
      mock_open3(runner) { |*args| captured.replace(args) }

      hide_env("RSPEC_EXECUTABLE")
      runner.send(:start_subprocess, {}, [], tests, 1, record_runtime: true)

      expect(captured).to include("ParallelTests::RSpec::RuntimeLogger")
    end

    it "passes defined order without a seed when randomization is disabled" do
      runner.instance_variable_set(:@order, "defined")
      runner.instance_variable_set(:@seed, nil)
      runner.instance_variable_set(:@seed_used, false)
      captured = []
      mock_open3(runner) { |*args| captured.replace(args) }

      hide_env("RSPEC_EXECUTABLE")
      runner.send(:start_subprocess, {}, [], tests, 1, record_runtime: false)

      expect(captured).to include("--order", "defined")
      expect(captured).not_to include("--seed")
    end

    it "uses plain 'rspec' string when neither RSPEC_EXECUTABLE nor BUNDLE_BIN_PATH is set" do
      captured = []
      mock_open3(runner) { |*args| captured.replace(args) }

      hide_env("RSPEC_EXECUTABLE", "BUNDLE_BIN_PATH")
      runner.send(:start_subprocess, {}, [], tests, 1, record_runtime: false)

      # command_name = "rspec" (string), [*"rspec"] = ["rspec"], first arg after env hash
      expect(captured[1]).to eq("rspec")
    end

    it "prevents worker RSpec processes from loading the project .rspec file" do
      captured = []
      mock_open3(runner) { |*args| captured.replace(args) }

      hide_env("RSPEC_EXECUTABLE")
      runner.send(:start_subprocess, {}, [], tests, 1, record_runtime: false)

      expect(captured).to include("--options", File::NULL)
      expect(captured.index("--options")).to be < captured.index("spec/turbo_tests/runner_spec.rb")
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

      it "buffers non-blank initial content before the output ID" do
        json_msg = {type: "seed", seed: 1234}.to_json
        mock_open3_with_stdout("prefix_content#{output_id}#{json_msg}\n")

        expect {
          runner.send(:start_subprocess, {}, [], tests, 1, record_runtime: false)
          runner.instance_variable_get(:@threads).each { |t| t.join(2) }
        }.not_to output.to_stdout

        worker_output = runner.instance_variable_get(:@worker_output)
        expect(worker_output[1][:stdout]).to eq("prefix_content")
      end

      it "streams non-formatter content immediately in verbose mode" do
        runner.instance_variable_set(:@verbose, true)
        json_msg = {type: "seed", seed: 1234}.to_json
        mock_open3_with_stdout("prefix_content#{output_id}#{json_msg}\n")

        expect {
          runner.send(:start_subprocess, {}, [], tests, 1, record_runtime: false)
          runner.instance_variable_get(:@threads).each { |t| t.join(2) }
        }.to output(/prefix_content/).to_stdout
      end

      it "buffers lines that contain no formatter output ID without parsing them" do
        # A plain line without the output_id: result.shift(×2) gives initial + nil message
        # → `next unless message` is taken, no JSON parse attempted
        mock_open3_with_stdout("plain rspec output without output id\n")

        expect {
          runner.send(:start_subprocess, {}, [], tests, 1, record_runtime: false)
          runner.instance_variable_get(:@threads).each do |thread|
            thread.join(2)
            expect(thread).not_to be_alive
            thread.value
          end
        }.not_to raise_error

        worker_output = runner.instance_variable_get(:@worker_output)
        expect(worker_output[1][:stdout]).to eq("plain rspec output without output id\n")
      end

      it "does not crash when worker stdout contains invalid UTF-8 bytes" do
        json_msg = {type: "seed", seed: 1234}.to_json
        invalid_output = +"raw output: "
        invalid_output << [0xC3, 0x28].pack("C*")
        invalid_output << "#{output_id}#{json_msg}\n"
        invalid_output.force_encoding(Encoding::UTF_8)
        mock_open3_with_stdout(invalid_output)

        expect {
          runner.send(:start_subprocess, {}, [], tests, 1, record_runtime: false)
          runner.instance_variable_get(:@threads).each { |t| t.join(2) }
        }.not_to raise_error
      end
    end

    it "passes --tag= flags from @tags via start_regular_subprocess" do
      runner.instance_variable_set(:@tags, ["focus", "wip"])
      captured = []
      mock_open3(runner) { |*args| captured.replace(args) }

      hide_env("RSPEC_EXECUTABLE")
      runner.send(:start_regular_subprocess, tests, 1, record_runtime: false)

      expect(captured).to include("--tag=focus", "--tag=wip")
    end

    it "passes the parallel test group count to workers for SimpleCov collation" do
      runner.instance_variable_set(:@num_processes, 3)
      captured = []
      mock_open3(runner) { |*args| captured.replace(args) }

      hide_env("RSPEC_EXECUTABLE")
      ParallelTests.with_pid_file do
        runner.send(:start_regular_subprocess, tests, 2, record_runtime: false)
        expect(captured.first).to include(
          "TEST_ENV_NUMBER" => "2",
          "PARALLEL_TEST_GROUPS" => "3",
          "PARALLEL_PID_FILE" => ParallelTests.pid_file_path
        )
      end
    end

    it "untracks worker pids after the pid-file environment has been restored" do
      mock_open3(runner)
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("RSPEC_EXECUTABLE").and_return(nil)
      allow(ENV).to receive(:[]).with("BUNDLE_BIN_PATH").and_return(nil)

      wait_threads = nil
      ParallelTests.with_pid_file do
        env = {
          "TEST_ENV_NUMBER" => "2",
          "PARALLEL_TEST_GROUPS" => "3",
          "PARALLEL_PID_FILE" => ParallelTests.pid_file_path
        }

        runner.send(:start_subprocess, env, [], tests, 2, record_runtime: false)
        wait_threads = runner.instance_variable_get(:@threads).dup
      end

      expect { wait_threads.each(&:value) }.not_to raise_error
    end

    it "exits from the waiter thread and closes worker pipes when output remains open" do
      stdout_reader, stdout_writer = IO.pipe
      stderr_reader, stderr_writer = IO.pipe
      begin
        allow(Open3).to receive(:popen3).and_return([fake_stdin, stdout_reader, stderr_reader, fake_wait_thr])
        runner.instance_variable_set(:@num_processes, 1)

        runner.send(:start_subprocess, {}, [], tests, 1, record_runtime: false)
        runner.send(:handle_messages)
        runner.instance_variable_get(:@threads).each { |thread| thread.join(2) }

        expect(runner.instance_variable_get(:@exited_process_ids)).to eq([1])
        expect(runner.instance_variable_get(:@threads)).not_to include(be_alive)
      ensure
        stdout_writer&.close unless stdout_writer&.closed?
        stderr_writer&.close unless stderr_writer&.closed?
      end
    end

    it "ignores duplicate exit messages from the same process" do
      runner.instance_variable_set(:@num_processes, 2)
      queue = runner.instance_variable_get(:@messages)
      queue << {type: "exit", process_id: 1}
      queue << {type: "exit", process_id: 1}
      queue << {type: "exit", process_id: 2}

      runner.send(:handle_messages)

      expect(runner.instance_variable_get(:@exited_process_ids)).to eq([1, 2])
    end
  end

  describe "#start_copy_thread (private)" do
    it "buffers data from src until EOF" do
      runner = build_runner
      r, w = IO.pipe

      w.write("hello from subprocess")
      w.close

      thread = runner.send(:start_copy_thread, r, 1, :stderr)
      thread.join(2)

      worker_output = runner.instance_variable_get(:@worker_output)
      expect(worker_output[1][:stderr]).to eq("hello from subprocess")
    end
  end

  describe "#flush_coverage_summary (private)" do
    it "prints one concise coverage summary from buffered worker output" do
      runner = build_runner
      worker_output = runner.instance_variable_get(:@worker_output)
      worker_output[1][:stdout] = <<~OUTPUT
        Coverage report generated for Test Coverage (turbo_tests2 worker 1) to coverage/index.html
        Line coverage: 311 / 312 (99.67%)
        Branch coverage: 28 / 29 (96.55%)
        Line Coverage: 99.68% (311 / 312)
        Branch Coverage: 96.55% (28 / 29)
        JSON Coverage report generated for Test Coverage (turbo_tests2 worker 1) to coverage/coverage.json
        Line coverage: 311 / 312 (99.67%)
        Branch coverage: 28 / 29 (96.55%)
      OUTPUT

      expect {
        runner.send(:flush_coverage_summary)
      }.to output(<<~OUTPUT).to_stdout

        Coverage:
        Line Coverage: 99.68% (311 / 312)
        Branch Coverage: 96.55% (28 / 29)
      OUTPUT
    end

    it "prints nothing when no coverage output was captured" do
      runner = build_runner

      expect {
        runner.send(:flush_coverage_summary)
      }.not_to output.to_stdout
    end
  end

  describe "#flush_worker_output (private)" do
    it "prints buffered worker stdout and stderr with labels" do
      runner = build_runner
      worker_output = runner.instance_variable_get(:@worker_output)
      worker_output[1][:stdout] = "worker stdout\n"
      worker_output[2][:stderr] = "worker stderr\n"

      expect {
        runner.send(:flush_worker_output)
      }.to output(/\nTurboTests worker 1 stdout:\nworker stdout\n/).to_stdout
        .and output(/\nTurboTests worker 2 stderr:\nworker stderr\n/).to_stderr
    end
  end

  describe "#run (instance method)" do
    context "when print_failed_group is true" do
      it "calls report_failed_group after messages are handled" do
        reporter = double("reporter", failed_examples: [])
        runner = build_runner(print_failed_group: true, reporter: reporter)

        test_groups = [["spec/one_spec.rb"]]

        allow(ParallelTests).to receive(:determine_number_of_processes).and_return(1)
        allow(ParallelTests::RSpec::Runner).to receive_messages(
          tests_with_size: [["spec/one_spec.rb", 1]],
          tests_in_groups: test_groups
        )
        allow(reporter).to receive(:report).and_yield(reporter)
        allow(Signal).to receive(:trap).and_return(nil)
        allow(runner).to receive(:start_regular_subprocess).and_return(nil)
        allow(runner).to receive(:handle_messages)

        expect(runner).to receive(:report_failed_group).with(test_groups)
        runner.run
      end
    end

    it "returns successfully without calling parallel_tests grouping when no files are discovered" do
      reporter = double("reporter", failed_examples: [], report: nil)
      runner = build_runner(reporter: reporter, files: [])

      allow(ParallelTests).to receive(:determine_number_of_processes).and_return(22)
      allow(ParallelTests::RSpec::Runner).to receive(:tests_with_size).and_return([])
      expect(ParallelTests::RSpec::Runner).not_to receive(:tests_in_groups)

      expect(runner.run).to eq(0)
      expect(reporter).to have_received(:report).with([])
    end

    it "stores test groups for interrupt reporting" do
      reporter = double("reporter", failed_examples: [])
      runner = build_runner(reporter: reporter)
      test_groups = [["spec/one_spec.rb"]]

      allow(ParallelTests).to receive(:determine_number_of_processes).and_return(1)
      allow(ParallelTests::RSpec::Runner).to receive_messages(tests_with_size: [["spec/one_spec.rb", 1]], tests_in_groups: test_groups)
      allow(reporter).to receive(:report).and_yield(reporter)
      allow(Signal).to receive(:trap).and_return(nil)
      allow(runner).to receive(:start_regular_subprocess).and_return(nil)
      allow(runner).to receive(:handle_messages)

      runner.run

      expect(runner.instance_variable_get(:@tests_in_groups)).to eq(test_groups)
    end

    it "passes parallel_tests options to discovery and grouping" do
      reporter = double("reporter", failed_examples: [])
      parallel_options = {pattern: /unit/, exclude_pattern: /system/}
      runner = build_runner(reporter: reporter, parallel_options: parallel_options)
      test_groups = [["spec/one_spec.rb"]]

      allow(ParallelTests).to receive(:determine_number_of_processes).and_return(2)
      allow(ParallelTests::RSpec::Runner).to receive_messages(
        tests_with_size: [["spec/one_spec.rb", 1]],
        tests_in_groups: test_groups
      )
      allow(reporter).to receive(:report).and_yield(reporter)
      allow(Signal).to receive(:trap).and_return(nil)
      allow(runner).to receive(:start_regular_subprocess).and_return(nil)
      allow(runner).to receive(:handle_messages)

      runner.run

      expect(ParallelTests::RSpec::Runner).to have_received(:tests_with_size).with(["spec"], parallel_options)
      expect(ParallelTests::RSpec::Runner).to have_received(:tests_in_groups).with(["spec"], 1, **parallel_options)
    end

    it "runs only selected 1-based groups while preserving the original process count" do
      reporter = double("reporter", failed_examples: [])
      parallel_options = {only_group: [2]}
      runner = build_runner(reporter: reporter, parallel_options: parallel_options)
      test_groups = [
        ["spec/one_spec.rb"],
        ["spec/two_spec.rb"],
        ["spec/three_spec.rb"]
      ]

      allow(ParallelTests).to receive(:determine_number_of_processes).and_return(3)
      allow(ParallelTests::RSpec::Runner).to receive_messages(
        tests_with_size: [
          ["spec/one_spec.rb", 1],
          ["spec/two_spec.rb", 1],
          ["spec/three_spec.rb", 1]
        ],
        tests_in_groups: test_groups
      )
      allow(reporter).to receive(:report).and_yield(reporter)
      allow(Signal).to receive(:trap).and_return(nil)
      allow(runner).to receive(:start_regular_subprocess).and_return(nil)
      allow(runner).to receive(:handle_messages)

      runner.run

      expect(reporter).to have_received(:report).with([["spec/two_spec.rb"]])
      expect(runner).to have_received(:start_regular_subprocess).with(
        ["spec/two_spec.rb"],
        1,
        record_runtime: true
      )
      expect(runner.instance_variable_get(:@num_processes)).to eq(3)
    end

    it "keeps grouped file paths when scheduling workers" do
      reporter = double("reporter", failed_examples: [])
      runner = build_runner(
        reporter: reporter,
        files: ["spec/turbo_tests/runner_spec.rb"],
        test_selectors: {
          "spec/turbo_tests/runner_spec.rb" => [
            "spec/turbo_tests/runner_spec.rb:279",
            "spec/turbo_tests/runner_spec.rb:884"
          ]
        }
      )
      test_groups = [["spec/turbo_tests/runner_spec.rb"]]

      allow(ParallelTests).to receive(:determine_number_of_processes).and_return(1)
      allow(ParallelTests::RSpec::Runner).to receive_messages(
        tests_with_size: [["spec/turbo_tests/runner_spec.rb", 1]],
        tests_in_groups: test_groups
      )
      allow(reporter).to receive(:report).and_yield(reporter)
      allow(Signal).to receive(:trap).and_return(nil)
      allow(runner).to receive(:handle_messages)

      allow(runner).to receive(:start_regular_subprocess).and_return(nil)

      runner.run

      expect(runner).to have_received(:start_regular_subprocess).with(
        ["spec/turbo_tests/runner_spec.rb"],
        1,
        record_runtime: true
      )
    end
  end

  describe "#start_regular_subprocess (private)" do
    it "passes RSpec location selectors to subprocesses after grouping by file" do
      runner = build_runner(
        test_selectors: {
          "spec/turbo_tests/runner_spec.rb" => [
            "spec/turbo_tests/runner_spec.rb:279",
            "spec/turbo_tests/runner_spec.rb:884"
          ]
        }
      )

      expect(runner).to receive(:start_subprocess).with(
        kind_of(Hash),
        [],
        ["spec/turbo_tests/runner_spec.rb:279", "spec/turbo_tests/runner_spec.rb:884"],
        1,
        record_runtime: false
      )

      runner.send(:start_regular_subprocess, ["spec/turbo_tests/runner_spec.rb"], 1, record_runtime: false)
    end
  end
end
