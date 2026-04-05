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
end
