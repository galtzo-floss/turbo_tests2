# frozen_string_literal: true

require "spec_helper"
require "utils/hash_extension"

# rubocop:disable RSpec/SpecFilePathFormat
RSpec.describe CoreExtensions do
  using described_class

  describe "Hash#to_struct" do
    it "converts a flat hash to a Struct" do
      result = {name: "Alice", age: 30}.to_struct
      expect(result).to be_a(Struct)
      expect(result.name).to eq("Alice")
      expect(result.age).to eq(30)
    end

    it "recursively converts nested hashes" do
      result = {outer: {inner: "value"}}.to_struct
      expect(result.outer).to be_a(Struct)
      expect(result.outer.inner).to eq("value")
    end

    it "leaves non-hash values unchanged" do
      result = {num: 42, arr: [1, 2, 3], str: "hello"}.to_struct
      expect(result.num).to eq(42)
      expect(result.arr).to eq([1, 2, 3])
      expect(result.str).to eq("hello")
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
