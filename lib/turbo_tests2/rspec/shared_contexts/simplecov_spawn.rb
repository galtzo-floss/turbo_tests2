# frozen_string_literal: true

require "bundler"
require "rspec/core"

RSpec.shared_context "with simplecov spawn coverage" do
  let(:simplecov_spawn_path) do
    File.expand_path(".simplecov_spawn.rb", Bundler.root.to_s)
  end

  around do |example|
    original_rubyopt = ENV.fetch("RUBYOPT", nil)
    begin
      if defined?(SimpleCov) && SimpleCov.running
        spawn_path = simplecov_spawn_path
        raise ArgumentError, "Expected SimpleCov spawn shim at #{spawn_path}" unless File.file?(spawn_path)

        ENV["RUBYOPT"] = ["-r#{spawn_path}", original_rubyopt].compact.join(" ").strip
      end

      example.run
    ensure
      ENV["RUBYOPT"] = original_rubyopt
    end
  end
end
