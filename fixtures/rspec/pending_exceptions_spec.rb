RSpec.describe("Fixture of spec file with pending failed examples") do
  it "is implemented but skipped with 'pending'" do
    pending("TODO: skipped with 'pending'")

    expect(2).to(eq(3))
  end

  it "is implemented but skipped with 'skip'", skip: "TODO: skipped with 'skip'" do
    # simplecov:disable
    expect(100).to(eq(500))
    # simplecov:enable
  end

  xit "is implemented but skipped with 'xit'" do
    # simplecov:disable
    expect(1).to(eq(42))
    # simplecov:enable
  end
end
