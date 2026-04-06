RSpec.describe TurboTests do
  it "has a version number" do
    expect(TurboTests::VERSION).not_to be_nil
  end

  describe "create" do
    context "with nil count" do
      it "creates databases" do
        expect(ParallelTests::Tasks)
          .to receive(:run_in_parallel)
          .with(["bundle", "exec", "rake", "db:create", "RAILS_ENV=test"], {count: ""})

        TurboTests::Runner.create(nil)
      end
    end

    context "with count" do
      it "creates databases" do
        expect(ParallelTests::Tasks)
          .to receive(:run_in_parallel)
          .with(["bundle", "exec", "rake", "db:create", "RAILS_ENV=test"], {count: "4"})

        TurboTests::Runner.create(4)
      end
    end
  end
end

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
  end
end
