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
end
