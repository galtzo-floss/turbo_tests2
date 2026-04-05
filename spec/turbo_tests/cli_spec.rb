RSpec.describe TurboTests::CLI do
  subject(:output) { %x(bundle exec turbo_tests -f d #{fixture}).strip }

  before { output }

  # When SimpleCov is active, inject .simplecov_spawn into spawned subprocesses
  # via RUBYOPT so their coverage is collected and merged into the main report.
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

  context "when the 'seed' parameter was used", :check_output do
    subject(:output) { %x(bundle exec turbo_tests -f d #{fixture} --seed #{seed}).strip }

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

    it "defaults to progress formatter writing to stdout" do
      run_cli([])
      expect(captured_opts[:formatters]).to eq([{name: "progress", outputs: ["-"]}])
    end

    it "passes verbose: true with --verbose" do
      run_cli(["--verbose"])
      expect(captured_opts[:verbose]).to be true
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
