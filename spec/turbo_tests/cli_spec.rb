require "turbo_tests2/rspec/shared_contexts/simplecov_spawn"

RSpec.describe TurboTests::CLI do
  subject(:output) { %x(bundle exec turbo_tests2 -f d #{fixture}).strip }

  before { output }

  include_context "with simplecov spawn coverage"

  context "when the 'seed' parameter was used", :check_output do
    subject(:output) { %x(bundle exec turbo_tests2 -f d #{fixture} --seed #{seed}).strip }

    let(:seed) { 1234 }

    context "when errors occur outside of examples" do
      let(:expected_start_of_output) do
        %(
1 processes for 1 specs, ~ 1 specs per process

Randomized with seed #{seed}

An error occurred while loading #{fixture}.
).strip
      end

      let(:expected_end_of_output) do
        "0 examples, 0 failures, 1 error occurred outside of examples\n" \
          "\n" \
          "Randomized with seed #{seed}"
      end

      let(:fixture) { "./fixtures/rspec/errors_outside_of_examples_spec.rb" }

      it "reports" do
        expect($?.exitstatus).to be(1)

        expect(output).to start_with(expected_start_of_output)
        expect(output).to end_with(expected_end_of_output)
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

          "Pending: (Failures listed here are expected and do not affect your suite's status)",
        ].each do |part|
          expect(output).to include(part)
        end

        expect(output).to end_with("3 examples, 0 failures, 3 pending\n\nRandomized with seed #{seed}")
      end
    end
  end

  context "when 'seed' parameter was not used", :check_output do
    context "when errors occur outside of examples" do
      let(:expected_start_of_output) do
        %(
1 processes for 1 specs, ~ 1 specs per process

An error occurred while loading #{fixture}.
).strip
      end

      let(:expected_end_of_output) do
        "0 examples, 0 failures, 1 error occurred outside of examples"
      end

      let(:fixture) { "./fixtures/rspec/errors_outside_of_examples_spec.rb" }

      it "reports" do
        expect($?.exitstatus).to be(1)

        expect(output).to start_with(expected_start_of_output)
        expect(output).to end_with(expected_end_of_output)
      end

      it "exludes the seed message from the output" do
        expect(output).not_to include("seed")
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

          "Pending: (Failures listed here are expected and do not affect your suite's status)",
        ].each do |part|
          expect(output).to include(part)
        end

        expect(output).to end_with("3 examples, 0 failures, 3 pending")
      end
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
        /# #{Regexp.escape(fixture)}:2:in [`']block \(2 levels\) in <top \(required\)>'/,
        /1 example, 1 failure/,
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
          double("status", success?: true),
        ]

        allow(ParallelTests).to receive(:determine_number_of_processes).with(2).and_return(2)
        allow(Process).to receive(:spawn) do |env, *command|
          spawned << [env, command]
          spawned.size + 100
        end
        allow(Process).to receive(:wait2).with(101).and_return([101, statuses[0]])
        allow(Process).to receive(:wait2).with(102).and_return([102, statuses[1]])

        run_cli(["fan", "-w", "2", "rake", "db:test:prepare"])

        expect(spawned).to eq(
          [
            [{"TEST_ENV_NUMBER" => "1", "PARALLEL_TEST_GROUPS" => "2"}, ["rake", "db:test:prepare"]],
            [{"TEST_ENV_NUMBER" => "2", "PARALLEL_TEST_GROUPS" => "2"}, ["rake", "db:test:prepare"]],
          ],
        )
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

    it "passes count with -w" do
      run_cli(["-w", "2"])
      expect(captured_opts[:count]).to eq(2)
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

    it "collects tags with --tag" do
      run_cli(["--tag", "focus"])
      expect(captured_opts[:tags]).to eq(["focus"])
    end

    it "passes seed with --seed" do
      run_cli(["--seed", "42"])
      expect(captured_opts[:seed]).to eq("42")
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
  end
end
