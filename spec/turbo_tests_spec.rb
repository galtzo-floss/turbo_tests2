RSpec.describe TurboTests do
  it "has a version number" do
    expect(TurboTests::VERSION).not_to be_nil
  end

  describe "create" do
    context "with nil count" do
      it "creates databases in parallel, count resolved from the environment" do
        allow(RuntimeGroups).to receive(:process_count).with(nil).and_return(1)
        allow(Process).to receive(:spawn).with(
          {"TEST_ENV_NUMBER" => "1", "PARALLEL_TEST_GROUPS" => 1.to_s},
          "bundle", "exec", "rake", "db:create", "RAILS_ENV=test"
        ).and_return(101)
        allow(Process).to receive(:wait2).with(101).and_return([101, double("status", success?: true)])

        expect(TurboTests::Runner.create(nil)).to eq(0)
      end
    end

    context "with count" do
      it "creates databases once per worker" do
        allow(RuntimeGroups).to receive(:process_count).with(4).and_return(4)
        allow(Process).to receive(:spawn).and_return(101, 102, 103, 104)
        allow(Process).to receive(:wait2).with(101).and_return([101, double("status", success?: true)])
        allow(Process).to receive(:wait2).with(102).and_return([102, double("status", success?: true)])
        allow(Process).to receive(:wait2).with(103).and_return([103, double("status", success?: true)])
        allow(Process).to receive(:wait2).with(104).and_return([104, double("status", success?: true)])

        expect(TurboTests::Runner.create(4)).to eq(0)
        expect(Process).to have_received(:spawn).exactly(4).times
      end
    end
  end
end
