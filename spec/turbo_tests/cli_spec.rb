require "tmpdir"
require "turbo_tests2/rspec/shared_contexts/simplecov_spawn"

RSpec.describe TurboTests::CLI do
  subject(:output) { `bundle exec turbo_tests2 -f d #{fixture} 2>&1`.strip }

  before { output }

  include_context "with simplecov spawn coverage"

  def expect_load_error_details(output, fixture, expected_summary)
    unless RUBY_ENGINE == "truffleruby" && !output.include?("An error occurred while loading #{fixture}.")
      expect(output).to include("An error occurred while loading #{fixture}.")
      if expected_summary.is_a?(Regexp)
        expect(output).to match(expected_summary)
      else
        expect(output).to include(expected_summary)
      end
      return
    end

    expect(output).to include("0 examples, 0 failures")
  end

  context "when the 'seed' parameter was used", :check_output do
    subject(:output) { `bundle exec turbo_tests2 -f d #{fixture} --seed #{seed} 2>&1`.strip }

    let(:seed) { 1234 }

    context "when errors occur outside of examples" do
      let(:expected_summary) { "0 examples, 0 failures, 1 error occurred outside of examples" }

      let(:fixture) { "./fixtures/rspec/errors_outside_of_examples_spec.rb" }

      it "reports" do
        expect($?.exitstatus).to be(1)

        expect(output).to include("1 processes for 1 specs, ~ 1 specs per process")
        expect(output).to include("Randomized with seed #{seed}")
        expect_load_error_details(output, fixture, expected_summary)
      end
    end

    context "with pending exceptions", :aggregate_failures do
      let(:fixture) { "./fixtures/rspec/pending_exceptions_spec.rb" }

      it "reports" do
        expect($?.exitstatus).to be(0)

        [
          "is implemented but skipped with 'pending' (PENDING: TODO: skipped with 'pending')",
          "is implemented but skipped with 'skip' (PENDING: TODO: skipped with 'skip')",
          "is implemented but skipped with 'xit' (PENDING: Temporarily skipped with xit)",

          "Pending: (Failures listed here are expected and do not affect your suite's status)"
        ].each do |part|
          expect(output).to include(part)
        end

        expect(output).to include("3 examples, 0 failures, 3 pending\n\nRandomized with seed #{seed}")
      end
    end
  end

  context "when 'seed' parameter was not used", :check_output do
    context "when errors occur outside of examples" do
      let(:expected_summary) { /0 examples, 0 failures, 1 error occurred outside of examples/ }

      let(:fixture) { "./fixtures/rspec/errors_outside_of_examples_spec.rb" }

      it "reports" do
        expect($?.exitstatus).to be(1)

        expect(output).to include("1 processes for 1 specs, ~ 1 specs per process")
        expect(output).to match(/Randomized with seed \d+/)
        expect_load_error_details(output, fixture, expected_summary)
      end

      it "includes the generated seed message in the output" do
        expect(output).to match(/Randomized with seed \d+/)
      end
    end

    context "with pending exceptions", :aggregate_failures do
      let(:fixture) { "./fixtures/rspec/pending_exceptions_spec.rb" }

      it "reports" do
        expect($?.exitstatus).to be(0)

        [
          "is implemented but skipped with 'pending' (PENDING: TODO: skipped with 'pending')",
          "is implemented but skipped with 'skip' (PENDING: TODO: skipped with 'skip')",
          "is implemented but skipped with 'xit' (PENDING: Temporarily skipped with xit)",

          "Pending: (Failures listed here are expected and do not affect your suite's status)"
        ].each do |part|
          expect(output).to include(part)
        end

        expect(output).to match(/3 examples, 0 failures, 3 pending\n\nRandomized with seed \d+/)
      end
    end
  end

  context "when randomization is disabled", :check_output do
    subject(:output) { `bundle exec turbo_tests2 -f d #{fixture} --no-random 2>&1`.strip }

    let(:fixture) { "./fixtures/rspec/passing_spec.rb" }

    it "does not print a seed" do
      expect($?.exitstatus).to be(0)
      expect(output).to include("1 example, 0 failures")
      expect(output).not_to include("Randomized with seed")
    end
  end

  describe "extra_failure_lines", :check_output do
    let(:fixture) { "./fixtures/rspec/failing_spec.rb" }

    it "outputs extra_failure_lines" do
      expect($?.exitstatus).to be(1)

      expect(output).to include("Test info in extra_failure_lines")
    end
  end

  describe "full error failure message and line", :check_output do
    let(:fixture) { "./fixtures/rspec/no_method_error_spec.rb" }

    it "outputs file name and line number" do
      expect($?.exitstatus).to be(1)

      [
        /undefined method [`']\[\]' for nil/,
        /it\("fails"\) \{ expect\(nil\[:key\]\).to\(eql\("value"\)\) \}/,
        /# #{Regexp.escape(fixture)}:2:in [`']block (?:\(2 levels\) in <top \(required\)>|in <main>)'/,
        /1 example, 1 failure/
      ].each do |part|
        expect(output).to match(part)
      end
    end
  end

  describe "passing examples", :check_output do
    let(:fixture) { "./fixtures/rspec/passing_spec.rb" }

    it "reports a passing example and exits 0" do
      expect($?.exitstatus).to be(0)
      expect(output).to include("1 example, 0 failures")
    end
  end

  # Unit tests for option parsing — stub Runner.run so no subprocess is spawned.
  describe "option parsing" do
    # Override the outer subject(:output) so the inherited `before { output }` is a no-op.
    subject(:output) { nil }

    let(:captured_opts) { {} }

    before do
      allow(TurboTests::Runner).to receive(:run) do |opts|
        captured_opts.merge!(opts)
        0
      end
    end

    def run_cli(args)
      TurboTests::CLI.new(args).run
    rescue SystemExit
      nil
    end

    it "renders help for all documented options" do
      matcher = RSpec::Matchers::BuiltIn::Output.new(
        /-n, --count \[PROCESSES\].*-w, --workers \[PROCESSES\].*--example-status-log FILE.*--pattern PATTERN.*--exclude-pattern PATTERN.*--only-group GROUP_INDEX\[,GROUP_INDEX\].*--group-by MODE.*--allowed-missing PERCENT.*--unknown-runtime SECONDS.*--worker-output MODE.*--seed SEED.*--order ORDER.*--no-random.*--no-rake-hooks.*--nice/m
      ).to_stdout

      expect { run_cli(["--help"]) }.to matcher
    end

    it "passes nil files for no-argument runs so Runner can use RSpec discovery" do
      run_cli([])

      expect(captured_opts[:files]).to be_nil
    end

    it "passes explicit file arguments unchanged" do
      run_cli(["spec/example_spec.rb"])

      expect(captured_opts[:files]).to eq(["spec/example_spec.rb"])
    end

    it "passes an explicit pattern to parallel_tests" do
      run_cli(["--pattern", "spec/system"])

      expect(captured_opts[:files]).to be_nil
      expect(captured_opts[:parallel_options]).to include(pattern: /spec\/system/)
    end

    it "passes a separator pattern to parallel_tests without treating it as a file" do
      run_cli(["spec/example_spec.rb", "--", "--pattern", "spec/system"])

      expect(captured_opts[:files]).to eq(["spec/example_spec.rb"])
      expect(captured_opts[:parallel_options]).to include(pattern: /spec\/system/)
    end

    it "passes an explicit exclude pattern to parallel_tests" do
      run_cli(["--exclude-pattern", "spec/system"])

      expect(captured_opts[:files]).to be_nil
      expect(captured_opts[:parallel_options]).to include(exclude_pattern: /spec\/system/)
    end

    it "passes a separator exclude pattern to parallel_tests without treating it as a file" do
      run_cli(["spec/example_spec.rb", "--", "--exclude-pattern", "spec/system"])

      expect(captured_opts[:files]).to eq(["spec/example_spec.rb"])
      expect(captured_opts[:parallel_options]).to include(exclude_pattern: /spec\/system/)
    end

    it "passes explicit selected groups to parallel_tests" do
      run_cli(["--only-group", "1,3"])

      expect(captured_opts[:files]).to be_nil
      expect(captured_opts[:parallel_options]).to include(only_group: [1, 3])
    end

    it "passes separator selected groups to parallel_tests without treating them as files" do
      run_cli(["spec/example_spec.rb", "--", "--only-group", "2"])

      expect(captured_opts[:files]).to eq(["spec/example_spec.rb"])
      expect(captured_opts[:parallel_options]).to include(only_group: [2])
    end

    it "passes explicit runtime grouping to parallel_tests" do
      run_cli(["--group-by", "runtime"])

      expect(captured_opts[:files]).to be_nil
      expect(captured_opts[:parallel_options]).to include(group_by: :runtime)
    end

    it "passes explicit filesize grouping to parallel_tests" do
      run_cli(["--group-by", "filesize"])

      expect(captured_opts[:files]).to be_nil
      expect(captured_opts[:parallel_options]).to include(group_by: :filesize)
    end

    it "passes explicit found-order grouping to parallel_tests" do
      run_cli(["--group-by", "found"])

      expect(captured_opts[:files]).to be_nil
      expect(captured_opts[:parallel_options]).to include(group_by: :found)
    end

    it "passes separator grouping to parallel_tests without treating it as a file" do
      run_cli(["spec/example_spec.rb", "--", "--group-by", "runtime"])

      expect(captured_opts[:files]).to eq(["spec/example_spec.rb"])
      expect(captured_opts[:parallel_options]).to include(group_by: :runtime)
    end

    it "passes allowed missing runtime percent to parallel_tests" do
      run_cli(["--allowed-missing", "25"])

      expect(captured_opts[:files]).to be_nil
      expect(captured_opts[:parallel_options]).to include(allowed_missing_percent: 25)
    end

    it "passes separator allowed missing runtime percent to parallel_tests without treating it as a file" do
      run_cli(["spec/example_spec.rb", "--", "--allowed-missing", "25"])

      expect(captured_opts[:files]).to eq(["spec/example_spec.rb"])
      expect(captured_opts[:parallel_options]).to include(allowed_missing_percent: 25)
    end

    it "passes unknown runtime seconds to parallel_tests" do
      run_cli(["--unknown-runtime", "1.5"])

      expect(captured_opts[:files]).to be_nil
      expect(captured_opts[:parallel_options]).to include(unknown_runtime: 1.5)
    end

    it "passes separator unknown runtime seconds to parallel_tests without treating it as a file" do
      run_cli(["spec/example_spec.rb", "--", "--unknown-runtime", "1.5"])

      expect(captured_opts[:files]).to eq(["spec/example_spec.rb"])
      expect(captured_opts[:parallel_options]).to include(unknown_runtime: 1.5)
    end

    it "rejects unsupported group-by modes" do
      expect {
        run_cli(["--group-by", "alphabetical"])
      }.to raise_error(OptionParser::InvalidArgument, /invalid group-by mode/)
    end

    it "rejects allowed missing runtime percent below zero" do
      expect {
        run_cli(["--allowed-missing", "-1"])
      }.to raise_error(OptionParser::InvalidArgument, /invalid allowed missing percent/)
    end

    it "rejects allowed missing runtime percent above one hundred" do
      expect {
        run_cli(["--allowed-missing", "101"])
      }.to raise_error(OptionParser::InvalidArgument, /invalid allowed missing percent/)
    end

    it "rejects unknown runtime seconds below zero" do
      expect {
        run_cli(["--unknown-runtime", "-0.1"])
      }.to raise_error(OptionParser::InvalidArgument, /invalid unknown runtime/)
    end

    it "rejects unknown runtime seconds that are not finite" do
      expect {
        run_cli(["--unknown-runtime", "1e309"])
      }.to raise_error(OptionParser::InvalidArgument, /invalid unknown runtime/)

      expect {
        run_cli(["--unknown-runtime", "NaN"])
      }.to raise_error(OptionParser::InvalidArgument)
    end

    it "rejects invalid exclude pattern regexes" do
      expect {
        run_cli(["--exclude-pattern", "["])
      }.to raise_error(OptionParser::InvalidArgument, /invalid regex pattern/)
    end

    it "rejects invalid pattern regexes" do
      expect {
        run_cli(["--pattern", "["])
      }.to raise_error(OptionParser::InvalidArgument, /invalid regex pattern/)
    end

    it "rejects invalid selected groups" do
      expect {
        run_cli(["--only-group", "1,zero"])
      }.to raise_error(OptionParser::InvalidArgument, /invalid group index/)
    end

    describe "shim commands" do
      around do |example|
        Dir.mktmpdir do |dir|
          @shim_root = dir
          example.run
        end
      end

      attr_reader :shim_root

      it "installs a project-local turbo_tests shim" do
        run_cli(["shim", "install", "--path", File.join(shim_root, "bin/turbo_tests")])

        expect(File).to exist(File.join(shim_root, "bin/turbo_tests"))
        expect(File.read(File.join(shim_root, "bin/turbo_tests"))).to include("exec bundle exec turbo_tests2")
      end

      it "removes an installed shim" do
        shim_path = File.join(shim_root, "bin/turbo_tests")

        run_cli(["shim", "install", "--path", shim_path])
        run_cli(["shim", "remove", "--path", shim_path])

        expect(File).not_to exist(shim_path)
      end
    end

    describe "fan command" do
      it "spawns the command once per worker with process env" do
        spawned = []
        statuses = [
          double("status", success?: true),
          double("status", success?: true)
        ]

        allow(ParallelTests).to receive(:determine_number_of_processes).with(2).and_return(2)
        allow(Process).to receive(:spawn) do |env, *command|
          spawned << [env, command]
          spawned.size + 100
        end
        allow(Process).to receive(:wait2).with(101).and_return([101, statuses[0]])
        allow(Process).to receive(:wait2).with(102).and_return([102, statuses[1]])

        run_cli(["fan", "-w", "2", "rake", "db:test:prepare"])

        pid_file_path = spawned.dig(0, 0, "PARALLEL_PID_FILE")
        expect(pid_file_path).to be_a(String)
        expect(pid_file_path).not_to be_empty
        expect(spawned).to eq(
          [
            [
              {
                "TEST_ENV_NUMBER" => "1",
                "PARALLEL_TEST_GROUPS" => "2",
                "PARALLEL_PID_FILE" => pid_file_path
              },
              ["rake", "db:test:prepare"]
            ],
            [
              {
                "TEST_ENV_NUMBER" => "2",
                "PARALLEL_TEST_GROUPS" => "2",
                "PARALLEL_PID_FILE" => pid_file_path
              },
              ["rake", "db:test:prepare"]
            ]
          ]
        )
      end

      it "accepts --count for process count" do
        spawned = []
        statuses = [double("status", success?: true)]

        allow(ParallelTests).to receive(:determine_number_of_processes).with(1).and_return(1)
        allow(Process).to receive(:spawn) do |env, *command|
          spawned << [env, command]
          101
        end
        allow(Process).to receive(:wait2).with(101).and_return([101, statuses[0]])

        run_cli(["fan", "--count", "1", "rake", "db:test:prepare"])

        expect(spawned.size).to eq(1)
      end

      it "exits nonzero when a worker command fails" do
        success = double("success", success?: true)
        failure = double("failure", success?: false)

        allow(ParallelTests).to receive(:determine_number_of_processes).with(nil).and_return(2)
        allow(Process).to receive(:spawn).and_return(101, 102)
        allow(Process).to receive(:wait2).with(101).and_return([101, success])
        allow(Process).to receive(:wait2).with(102).and_return([102, failure])

        expect { described_class.new(["fan", "false"]).run }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end

      it "exits nonzero and prints usage without a command" do
        cli = described_class.new(["fan"])

        expect(cli).to receive(:warn).with(instance_of(OptionParser))
        expect { cli.run }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end

      it "exits nonzero and prints usage on invalid fan options" do
        cli = described_class.new(["fan", "--bad-option", "rake"])

        expect(cli).to receive(:warn).with("invalid option: --bad-option")
        expect(cli).to receive(:warn).with(instance_of(OptionParser))
        expect { cli.run }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end
    end

    it "defaults to progress formatter writing to stdout" do
      run_cli([])
      expect(captured_opts[:formatters]).to eq([{name: "progress", outputs: ["-"]}])
    end

    it "passes verbose: true with --verbose" do
      run_cli(["--verbose"])
      expect(captured_opts[:verbose]).to be true
    end

    it "passes worker_output with --worker-output" do
      run_cli(["--worker-output", "stream"])
      expect(captured_opts[:worker_output]).to eq("stream")
    end

    it "leaves worker_output nil when --worker-output is not provided so Runner can use ENV" do
      run_cli([])
      expect(captured_opts[:worker_output]).to be_nil
    end

    it "passes count with -w" do
      run_cli(["-w", "2"])
      expect(captured_opts[:count]).to eq(2)
    end

    it "passes count with --count" do
      run_cli(["--count", "3"])
      expect(captured_opts[:count]).to eq(3)
    end

    it "passes count with --workers" do
      run_cli(["--workers", "3"])
      expect(captured_opts[:count]).to eq(3)
    end

    it "passes nice: true with --nice" do
      run_cli(["--nice"])
      expect(captured_opts[:nice]).to be true
    end

    it "passes runtime_log with --runtime-log" do
      run_cli(["--runtime-log", "my.log"])
      expect(captured_opts[:runtime_log]).to eq("my.log")
    end

    it "passes example_status_log with --example-status-log" do
      run_cli(["--example-status-log", "spec/examples.txt"])
      expect(captured_opts[:example_status_log]).to eq("spec/examples.txt")
    end

    it "collects tags with --tag" do
      run_cli(["--tag", "focus"])
      expect(captured_opts[:tags]).to eq(["focus"])
    end

    it "passes seed with --seed" do
      run_cli(["--seed", "42"])
      expect(captured_opts[:seed]).to eq("42")
    end

    it "passes order with --order" do
      run_cli(["--order", "defined"])
      expect(captured_opts[:order]).to eq("defined")
    end

    it "passes defined order with --no-random" do
      run_cli(["--no-random"])
      expect(captured_opts[:order]).to eq("defined")
    end

    it "passes print_failed_group: true with --print_failed_group" do
      run_cli(["--print_failed_group"])
      expect(captured_opts[:print_failed_group]).to be true
    end

    it "adds a named formatter with -f" do
      run_cli(["-f", "progress"])
      expect(captured_opts[:formatters].first[:name]).to eq("progress")
    end

    it "requires the file with -r" do
      run_cli(["-r", "json"]) # json is already loaded; require is a no-op
      expect(captured_opts[:verbose]).to be false
    end

    describe "--fail-fast" do
      it "defaults to 1 with no value" do
        run_cli(["--fail-fast"])
        expect(captured_opts[:fail_fast]).to eq(1)
      end

      it "defaults to 1 when value is 0" do
        run_cli(["--fail-fast=0"])
        expect(captured_opts[:fail_fast]).to eq(1)
      end

      it "uses the given value when >= 1" do
        run_cli(["--fail-fast=3"])
        expect(captured_opts[:fail_fast]).to eq(3)
      end

      it "defaults to 1 on non-integer value" do
        run_cli(["--fail-fast=abc"])
        expect(captured_opts[:fail_fast]).to eq(1)
      end
    end

    describe "-o / --out FILE" do
      context "with no prior formatter" do
        it "adds a default progress formatter and sets the file as output" do
          run_cli(["-o", "output.txt"])
          expect(captured_opts[:formatters].first[:name]).to eq("progress")
          expect(captured_opts[:formatters].first[:outputs]).to eq(["output.txt"])
        end
      end

      context "with a prior -f formatter" do
        it "appends the file to that formatter's outputs" do
          run_cli(["-f", "progress", "-o", "output.txt"])
          expect(captured_opts[:formatters].first[:outputs]).to include("output.txt")
        end
      end
    end

    describe "--create" do
      before { allow(TurboTests::Runner).to receive(:create).and_return(nil) }

      it "calls Runner.create and skips Runner.run" do
        run_cli(["--create"])
        expect(TurboTests::Runner).to have_received(:create).with(nil)
        expect(TurboTests::Runner).not_to have_received(:run)
      end

      it "passes -n count to Runner.create" do
        run_cli(["--create", "-n", "4"])
        expect(TurboTests::Runner).to have_received(:create).with(4)
      end
    end

    describe "--no-rake-hooks" do
      it "loads and invokes Rake hooks by default" do
        cli = described_class.new([])
        allow(cli).to receive(:load_rake)
        allow(cli).to receive(:invoke_rake_hook)

        expect { cli.run }.to raise_error(SystemExit)
        expect(cli).to have_received(:load_rake)
        expect(cli).to have_received(:invoke_rake_hook).with("setup")
        expect(cli).to have_received(:invoke_rake_hook).with("cleanup")
      end

      it "skips loading and invoking Rake hooks" do
        cli = described_class.new(["--no-rake-hooks"])
        allow(cli).to receive(:load_rake)
        allow(cli).to receive(:invoke_rake_hook)

        expect { cli.run }.to raise_error(SystemExit)
        expect(cli).not_to have_received(:load_rake)
        expect(cli).not_to have_received(:invoke_rake_hook)
      end
    end

    describe "#load_rake" do
      subject(:cli) { described_class.new([]) }

      before do
        allow(Rake.application).to receive(:init)
        allow(Rake.application).to receive(:load_rakefile)
      end

      context "when no Rakefile is discoverable" do
        before { allow(Rake.application).to receive(:find_rakefile_location).and_return(nil) }

        it "does not load a Rakefile" do
          cli.send(:load_rake)

          expect(Rake.application).not_to have_received(:load_rakefile)
        end
      end

      context "when a Rakefile is discoverable" do
        before do
          allow(Rake.application).to receive(:find_rakefile_location).and_return(["Rakefile", Dir.pwd])
        end

        it "loads the Rakefile" do
          cli.send(:load_rake)

          expect(Rake.application).to have_received(:load_rakefile)
        end
      end
    end

    describe "#invoke_rake_task" do
      subject(:cli) { described_class.new([]) }

      context "when the task is defined" do
        let(:task) { instance_double(Rake::Task, invoke: nil) }

        before do
          allow(Rake::Task).to receive(:task_defined?).with("turbo_tests:example").and_return(true)
          allow(Rake::Task).to receive(:[]).with("turbo_tests:example").and_return(task)
        end

        it "invokes the task" do
          cli.send(:invoke_rake_task, "turbo_tests:example")
          expect(task).to have_received(:invoke)
        end
      end

      context "when the task is not defined" do
        it "returns without invoking anything" do
          block_is_expected.not_to raise_error
        end
      end
    end

    describe "#invoke_rake_hook" do
      subject(:cli) { described_class.new([]) }

      let(:current_task) { instance_double(Rake::Task, invoke: nil) }
      let(:legacy_task) { instance_double(Rake::Task, invoke: nil) }

      before do
        allow(Rake::Task).to receive(:task_defined?).with("turbo_tests2:setup").and_return(current_defined)
        allow(Rake::Task).to receive(:task_defined?).with("turbo_tests:setup").and_return(legacy_defined)
        allow(Rake::Task).to receive(:[]).with("turbo_tests2:setup").and_return(current_task)
        allow(Rake::Task).to receive(:[]).with("turbo_tests:setup").and_return(legacy_task)
      end

      context "when the current namespace task is defined" do
        let(:current_defined) { true }
        let(:legacy_defined) { true }

        it "invokes the current namespace task" do
          cli.send(:invoke_rake_hook, "setup")

          expect(current_task).to have_received(:invoke)
          expect(legacy_task).not_to have_received(:invoke)
        end
      end

      context "when only the legacy namespace task is defined" do
        let(:current_defined) { false }
        let(:legacy_defined) { true }

        it "invokes the legacy namespace task" do
          cli.send(:invoke_rake_hook, "setup")

          expect(current_task).not_to have_received(:invoke)
          expect(legacy_task).to have_received(:invoke)
        end
      end

      context "when neither namespace task is defined" do
        let(:current_defined) { false }
        let(:legacy_defined) { false }

        it "returns without invoking anything" do
          cli.send(:invoke_rake_hook, "setup")

          expect(current_task).not_to have_received(:invoke)
          expect(legacy_task).not_to have_received(:invoke)
        end
      end
    end
  end
end
