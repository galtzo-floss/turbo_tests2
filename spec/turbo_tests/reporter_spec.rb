# frozen_string_literal: true

require "spec_helper"

RSpec.describe TurboTests::Reporter do
  let(:start_time) { RSpec::Core::Time.now }
  let(:formatter_output) { StringIO.new }

  def build_reporter(**overrides)
    defaults = {start_time: start_time, seed: nil, seed_used: false, files: [], parallel_options: {}}
    described_class.new(*defaults.merge(overrides).values_at(:start_time, :seed, :seed_used, :files, :parallel_options))
  end

  describe "#add" do
    subject(:reporter) { build_reporter }

    it "adds a ProgressFormatter for 'p'" do
      reporter.add("p", [formatter_output])
      expect(reporter.instance_variable_get(:@formatters).first).to be_a(RSpec::Core::Formatters::ProgressFormatter)
    end

    it "adds a ProgressFormatter for 'progress'" do
      reporter.add("progress", [formatter_output])
      expect(reporter.instance_variable_get(:@formatters).first).to be_a(RSpec::Core::Formatters::ProgressFormatter)
    end

    it "adds a DocumentationFormatter for 'd'" do
      reporter.add("d", [formatter_output])
      expect(reporter.instance_variable_get(:@formatters).first).to be_a(RSpec::Core::Formatters::DocumentationFormatter)
    end

    it "adds a DocumentationFormatter for 'documentation'" do
      reporter.add("documentation", [formatter_output])
      expect(reporter.instance_variable_get(:@formatters).first).to be_a(RSpec::Core::Formatters::DocumentationFormatter)
    end

    it "resolves a custom formatter class via Kernel.const_get" do
      reporter.add("RSpec::Core::Formatters::ProgressFormatter", [formatter_output])
      expect(reporter.instance_variable_get(:@formatters).first).to be_a(RSpec::Core::Formatters::ProgressFormatter)
    end
  end

  describe ".from_config" do
    it "uses $stdout for '-' output" do
      reporter = described_class.from_config(
        [{name: "progress", outputs: ["-"]}], start_time, nil, false, [], {}
      )
      fmtr_output = reporter.instance_variable_get(:@formatters).first.instance_variable_get(:@output)
      expect(fmtr_output).to eq($stdout)
    end

    it "opens a file for non-'-' output", :aggregate_failures do
      tmp_path = File.join(File.expand_path("../../..", __dir__), "tmp", "test_reporter_output.txt")
      FileUtils.mkdir_p(File.dirname(tmp_path))

      begin
        reporter = described_class.from_config(
          [{name: "progress", outputs: [tmp_path]}], start_time, nil, false, [], {}
        )
        expect(reporter.instance_variable_get(:@formatters).first).to be_a(RSpec::Core::Formatters::ProgressFormatter)
        expect(File).to exist(tmp_path)
      ensure
        FileUtils.rm_f(tmp_path)
      end
    end
  end

  describe "#group_started and #group_finished" do
    subject(:reporter) { build_reporter }

    let(:formatter) do
      double(
        "formatter",
        example_group_started: nil,
        example_group_finished: nil,
      ).tap do |f|
        allow(f).to receive(:respond_to?) { |m| %i[example_group_started example_group_finished].include?(m) }
      end
    end

    before { reporter.instance_variable_set(:@formatters, [formatter]) }

    it "delegates group_started to formatters as example_group_started" do
      notification = double("notification")
      expect(formatter).to receive(:example_group_started).with(notification)
      reporter.group_started(notification)
    end

    it "delegates group_finished to formatters as example_group_finished with nil" do
      expect(formatter).to receive(:example_group_finished).with(nil)
      reporter.group_finished
    end
  end

  describe "#example_passed" do
    subject(:reporter) { build_reporter }

    it "adds the example to @all_examples" do
      example = double("example", notification: double("ExampleNotification"))
      reporter.instance_variable_set(:@formatters, [])
      reporter.example_passed(example)
      expect(reporter.instance_variable_get(:@all_examples)).to include(example)
    end
  end

  describe "#example_pending and #example_failed" do
    subject(:reporter) { build_reporter }

    let(:notification) { double("ExampleNotification") }
    let(:example) { double("example", notification: notification) }

    before { reporter.instance_variable_set(:@formatters, []) }

    it "tracks pending examples" do
      reporter.example_pending(example)

      expect(reporter.pending_examples).to include(example)
      expect(reporter.instance_variable_get(:@all_examples)).to include(example)
    end

    it "tracks failed examples" do
      reporter.example_failed(example)

      expect(reporter.failed_examples).to include(example)
      expect(reporter.instance_variable_get(:@all_examples)).to include(example)
    end
  end

  describe "#message and #error_outside_of_examples" do
    subject(:reporter) { build_reporter }

    it "stores regular messages" do
      reporter.instance_variable_set(:@formatters, [])

      reporter.message("hello")

      expect(reporter.instance_variable_get(:@messages)).to eq(["hello"])
    end

    it "increments the error count and stores the message" do
      reporter.instance_variable_set(:@formatters, [])

      reporter.error_outside_of_examples("load error")

      expect(reporter.instance_variable_get(:@errors_outside_of_examples_count)).to eq(1)
      expect(reporter.instance_variable_get(:@messages)).to eq(["load error"])
    end
  end

  describe "#deprecation" do
    subject(:reporter) { build_reporter }

    it "delegates a reconstructed RSpec deprecation notification" do
      formatter = double("formatter", deprecation: nil)
      allow(formatter).to receive(:respond_to?).with(:deprecation).and_return(true)
      reporter.instance_variable_set(:@formatters, [formatter])

      expect(formatter).to receive(:deprecation) do |notification|
        expect(notification).to be_a(RSpec::Core::Notifications::DeprecationNotification)
        expect(notification.deprecated).to eq("old_api")
        expect(notification.message).to eq("old_api is deprecated")
        expect(notification.replacement).to eq("new_api")
        expect(notification.call_site).to eq("spec/foo_spec.rb:4")
      end

      reporter.deprecation(
        deprecated: "old_api",
        message: "old_api is deprecated",
        replacement: "new_api",
        call_site: "spec/foo_spec.rb:4",
      )
    end
  end

  describe "#profile" do
    subject(:reporter) { build_reporter }

    it "delegates a reconstructed RSpec profile notification" do
      formatter = double("formatter", dump_profile: nil)
      allow(formatter).to receive(:respond_to?) { |method| method == :dump_profile }
      reporter.instance_variable_set(:@formatters, [formatter])

      expect(formatter).to receive(:dump_profile) do |notification|
        expect(notification).to be_a(RSpec::Core::Notifications::ProfileNotification)
        expect(notification.duration).to eq(1.23)
        expect(notification.number_of_examples).to eq(1)
        expect(notification.examples.first.execution_result.run_time).to eq(0.12)
      end

      reporter.profile(
        duration: 1.23,
        number_of_examples: 1,
        examples: [
          {
            execution_result: {
              example_skipped?: false,
              pending_message: nil,
              status: "passed",
              pending_fixed?: false,
              exception: nil,
              run_time: 0.12,
            },
            location: "spec/foo_spec.rb:1",
            description: "does something",
            full_description: "Foo does something",
            location_rerun_argument: "spec/foo_spec.rb:1",
            metadata: {
              shared_group_inclusion_backtrace: [],
            },
          },
        ],
      )
    end
  end

  describe "#report_number_of_tests" do
    subject(:reporter) { build_reporter }

    it "handles 0 processes without division by zero" do
      expect { reporter.report_number_of_tests([]) }.to output(/0 processes/).to_stdout
    end

    it "outputs correct counts for non-empty groups" do
      groups = [["spec_a.rb", "spec_b.rb"], ["spec_c.rb"]]
      expect { reporter.report_number_of_tests(groups) }.to output(/2 processes for 3/).to_stdout
    end
  end

  describe "#report" do
    subject(:reporter) { build_reporter(start_time: start_time - 1, seed: 1234, seed_used: true) }

    let(:formatter) do
      double(
        "formatter",
        seed: nil,
        start: nil,
        stop: nil,
        start_dump: nil,
        dump_pending: nil,
        dump_failures: nil,
        dump_summary: nil,
        close: nil,
      ).tap do |formatter|
        allow(formatter).to receive(:respond_to?) do |method|
          %i[seed start stop start_dump dump_pending dump_failures dump_summary close].include?(method)
        end
      end
    end

    before { reporter.instance_variable_set(:@formatters, [formatter]) }

    it "starts, yields, finishes, and closes formatters" do
      yielded = nil

      expect(formatter).to receive(:start)
      expect(formatter).to receive(:dump_summary)
      expect(formatter).to receive(:close)

      reporter.report([["spec/foo_spec.rb"]]) do |inner|
        yielded = inner
      end

      expect(yielded).to eq(reporter)
    end

    it "closes formatters when the report block raises" do
      expect(formatter).to receive(:close)

      expect do
        reporter.report([]) { raise "boom" }
      end.to raise_error("boom")
    end
  end
end
