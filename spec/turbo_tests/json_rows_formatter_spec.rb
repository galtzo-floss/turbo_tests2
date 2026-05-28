# frozen_string_literal: true

require "spec_helper"

RSpec.describe TurboTests::JsonRowsFormatter do
  subject(:formatter) { described_class.new(output) }

  let(:output) { StringIO.new }
  let(:output_id) { "TEST_OUTPUT_ID_#{SecureRandom.hex(4)}" }

  around do |example|
    begin
      ENV["RSPEC_FORMATTER_OUTPUT_ID"] = output_id
      example.run
    ensure
      ENV.delete("RSPEC_FORMATTER_OUTPUT_ID")
    end
  end

  def parsed_row
    output.rewind
    raw = output.read
    json_part = raw.split(output_id).last
    JSON.parse(json_part, symbolize_names: true)
  end

  def build_example(shared_group_frames: [])
    execution_result = double(
      "execution_result",
      example_skipped?: false,
      pending_message: nil,
      status: :passed,
      pending_fixed?: false,
      exception: nil,
      pending_exception: nil,
      run_time: 0.12,
    )

    double(
      "example",
      execution_result: execution_result,
      location: "spec/foo_spec.rb:1",
      description: "does something",
      full_description: "Foo does something",
      metadata: {shared_group_inclusion_backtrace: shared_group_frames},
      location_rerun_argument: "spec/foo_spec.rb:1",
    )
  end

  describe "#example_passed" do
    it "outputs an example_passed row" do
      notification = double("notification", example: build_example)
      formatter.example_passed(notification)

      row = parsed_row
      expect(row[:type]).to eq("example_passed")
      expect(row.dig(:example, :description)).to eq("does something")
    end
  end

  describe "#example_failed" do
    it "outputs an example_failed row with exception details" do
      exception = RuntimeError.new("oops")
      exception.set_backtrace(
        [
          "/app/spec/foo_spec.rb:2:in `block'",
          "/app/lib/turbo_tests/json_rows_formatter.rb:10:in `example_failed'",
          "/app/exe/turbo_tests2:5:in `<main>'",
        ],
      )
      execution_result = double(
        "execution_result",
        example_skipped?: false,
        pending_message: nil,
        status: :failed,
        pending_fixed?: false,
        exception: exception,
        pending_exception: nil,
      )
      example = double(
        "example",
        execution_result: execution_result,
        location: "spec/foo_spec.rb:2",
        description: "fails",
        full_description: "Foo fails",
        metadata: {shared_group_inclusion_backtrace: []},
        location_rerun_argument: "spec/foo_spec.rb:2",
      )
      notification = double("notification", example: example)

      formatter.example_failed(notification)

      row = parsed_row
      expect(row[:type]).to eq("example_failed")
      expect(row.dig(:example, :execution_result, :exception, :message)).to eq("oops")
      expect(row.dig(:example, :execution_result, :exception, :backtrace)).to eq(["/app/spec/foo_spec.rb:2:in `block'"])
    end
  end

  describe "#example_pending" do
    it "outputs an example_pending row" do
      execution_result = double(
        "execution_result",
        example_skipped?: true,
        pending_message: "TODO",
        status: :pending,
        pending_fixed?: false,
        exception: nil,
        pending_exception: nil,
      )
      example = double(
        "example",
        execution_result: execution_result,
        location: "spec/foo_spec.rb:3",
        description: "is pending",
        full_description: "Foo is pending",
        metadata: {shared_group_inclusion_backtrace: []},
        location_rerun_argument: "spec/foo_spec.rb:3",
      )
      notification = double("notification", example: example)

      formatter.example_pending(notification)

      row = parsed_row
      expect(row[:type]).to eq("example_pending")
    end
  end

  describe "#deprecation" do
    it "outputs a deprecation row" do
      notification = RSpec::Core::Notifications::DeprecationNotification.new(
        "old_api",
        "old_api is deprecated",
        "new_api",
        "spec/foo_spec.rb:4",
      )

      formatter.deprecation(notification)

      row = parsed_row
      expect(row[:type]).to eq("deprecation")
      expect(row.dig(:deprecation, :deprecated)).to eq("old_api")
      expect(row.dig(:deprecation, :message)).to eq("old_api is deprecated")
      expect(row.dig(:deprecation, :replacement)).to eq("new_api")
      expect(row.dig(:deprecation, :call_site)).to eq("spec/foo_spec.rb:4")
    end
  end

  describe "#dump_profile" do
    it "outputs a profile row with examples" do
      notification = RSpec::Core::Notifications::ProfileNotification.new(
        1.23,
        [build_example],
        1,
        {},
      )

      formatter.dump_profile(notification)

      row = parsed_row
      expect(row[:type]).to eq("profile")
      expect(row.dig(:profile, :duration)).to eq(1.23)
      expect(row.dig(:profile, :number_of_examples)).to eq(1)
      expect(row.dig(:profile, :examples, 0, :execution_result, :run_time)).to eq(0.12)
    end
  end

  describe "example_to_json with shared group inclusion backtrace" do
    it "serializes shared group frames via stack_frame_to_json" do
      shared_frame = double(
        "frame",
        shared_group_name: "shared behaviors",
        inclusion_location: "spec/support/shared.rb:5",
      )
      notification = double("notification", example: build_example(shared_group_frames: [shared_frame]))

      formatter.example_passed(notification)

      row = parsed_row
      frames = row.dig(:example, :metadata, :shared_group_inclusion_backtrace)
      expect(frames.first[:shared_group_name]).to eq("shared behaviors")
      expect(frames.first[:inclusion_location]).to eq("spec/support/shared.rb:5")
    end
  end

  describe "exception_to_json with nil exception" do
    it "returns nil" do
      # exception_to_json(nil) is called for examples without exceptions
      execution_result = double(
        "execution_result",
        example_skipped?: false,
        pending_message: nil,
        status: :passed,
        pending_fixed?: false,
        exception: nil,
        pending_exception: nil,
      )
      example = double(
        "example",
        execution_result: execution_result,
        location: "spec/foo_spec.rb:1",
        description: "no exception",
        full_description: "Foo no exception",
        metadata: {shared_group_inclusion_backtrace: []},
        location_rerun_argument: "spec/foo_spec.rb:1",
      )
      notification = double("notification", example: example)

      formatter.example_passed(notification)

      row = parsed_row
      expect(row.dig(:example, :execution_result, :exception)).to be_nil
    end
  end

  describe "RSpecExt#handle_interrupt (prepended to RSpec::Core::Runner)" do
    let(:host) { Class.new { prepend RSpecExt }.new }

    context "when RSpec.world.wants_to_quit is false (first interrupt)" do
      before { allow(RSpec.world).to receive(:wants_to_quit).and_return(false) }

      it "sets wants_to_quit to true" do
        expect(RSpec.world).to receive(:wants_to_quit=).with(true)
        host.handle_interrupt
      end
    end

    context "when RSpec.world.wants_to_quit is true (second interrupt)" do
      before { allow(RSpec.world).to receive(:wants_to_quit).and_return(true) }

      it "calls exit!(1) to force immediate shutdown" do
        # exit! is a Kernel method; stub on the instance to prevent actual process exit
        expect(host).to receive(:exit!).with(1)
        host.handle_interrupt
      end
    end
  end
end
