# frozen_string_literal: true

RSpec.describe Gem::Specification do
  it "only ships the turbo_tests2 executable" do
    spec = described_class.load(File.expand_path("../../turbo_tests2.gemspec", __dir__))

    expect(spec.executables).to eq(["turbo_tests2"])
  end
end
