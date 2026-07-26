# frozen_string_literal: true

require "open3"
require "rbconfig"

RSpec.describe "turbo_tests2 executable" do
  let(:root) { File.expand_path("../..", __dir__) }
  let(:executable) { File.join(root, "exe", "turbo_tests2") }
  let(:lib_path) { File.join(root, "lib") }
  let(:version) { TurboTests::Version::VERSION }

  it "prints only the version for executable version flags" do
    %w[-v --version].each do |flag|
      stdout, stderr, status = run_executable(flag)

      expect(status).to be_success
      expect(stderr).to eq("")
      expect(stdout).to eq("#{version}\n")
    end
  end

  it "does not print the executable header by default" do
    stdout, stderr, status = run_executable("--help")

    expect(status).to be_success
    expect(stderr).to eq("")
    expect(stdout).not_to include("== turbo_tests2 v#{version} ==")
  end

  it "prints the executable header when verbose output is requested" do
    stdout, stderr, status = run_executable("--verbose", "--help")

    expect(status).to be_success
    expect(stderr).to eq("")
    expect(stdout).to start_with("== turbo_tests2 v#{version} ==\n")
  end

  def run_executable(*args)
    Open3.capture3({"RUBYLIB" => lib_path}, RbConfig.ruby, executable, *args)
  end
end
