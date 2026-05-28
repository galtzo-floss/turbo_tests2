# frozen_string_literal: true

RSpec.describe TurboTests::FakeExample do
  describe ".from_obj" do
    def build_obj(shared_group_inclusion_backtrace: [])
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
          shared_group_inclusion_backtrace: shared_group_inclusion_backtrace,
        },
      }
    end

    context "with non-empty shared_group_inclusion_backtrace" do
      it "converts frame hashes to SharedExampleGroupInclusionStackFrame objects" do
        frames = [
          {shared_group_name: "shared behaviors", inclusion_location: "spec/support/shared.rb:5"},
        ]
        example = described_class.from_obj(build_obj(shared_group_inclusion_backtrace: frames))

        frame = example.metadata[:shared_group_inclusion_backtrace].first
        expect(frame).to be_a(RSpec::Core::SharedExampleGroupInclusionStackFrame)
        expect(frame.shared_group_name).to eq("shared behaviors")
        expect(frame.inclusion_location).to eq("spec/support/shared.rb:5")
      end
    end

    it "reconstructs exception class names, backtraces, messages, and causes" do
      example = described_class.from_obj(
        build_obj.merge(
          execution_result: {
            example_skipped?: false,
            pending_message: nil,
            status: "failed",
            pending_fixed?: false,
            exception: {
              class_name: "OuterError",
              backtrace: ["spec/foo_spec.rb:1"],
              message: "outer",
              cause: {
                class_name: "InnerError",
                backtrace: ["spec/foo_spec.rb:2"],
                message: "inner",
              },
            },
            run_time: 0.34,
          },
        ),
      )

      exception = example.execution_result.exception
      expect(exception.class.name).to eq("OuterError")
      expect(exception.backtrace).to eq(["spec/foo_spec.rb:1"])
      expect(exception.message).to eq("outer")
      expect(exception.cause.class.name).to eq("InnerError")
      expect(example.execution_result.run_time).to eq(0.34)
    end

    it "returns nil when reconstructing a nil exception" do
      example = described_class.from_obj(build_obj)

      expect(example.execution_result.exception).to be_nil
    end
  end

  describe "#notification" do
    it "builds an RSpec example notification" do
      example = described_class.from_obj(
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
      )

      expect(example.notification).to be_a(RSpec::Core::Notifications::ExampleNotification)
    end
  end
end
