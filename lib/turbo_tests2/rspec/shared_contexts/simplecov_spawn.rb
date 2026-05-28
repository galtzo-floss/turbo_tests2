# frozen_string_literal: true

require "rspec/core"

RSpec.shared_context("with simplecov spawn coverage") do
  let(:simplecov_spawn_path) do
    [Dir.pwd, File.expand_path("..", Dir.pwd)]
      .map { |dir| File.expand_path(".simplecov_spawn.rb", dir) }
      .find { |path| File.file?(path) }
  end

  around do |example|
    original_rubyopt = ENV.fetch("RUBYOPT", nil)
    original_cov_min_hard = ENV.fetch("K_SOUP_COV_MIN_HARD", nil)
    begin
      if defined?(SimpleCov) && SimpleCov.running
        spawn_path = simplecov_spawn_path
        raise ArgumentError, "Expected SimpleCov spawn shim at #{spawn_path}" unless File.file?(spawn_path)

        ENV["K_SOUP_COV_MIN_HARD"] = "false"
        ENV["RUBYOPT"] = ["-r#{spawn_path}", original_rubyopt].compact.join(" ").strip
      end

      example.run
    ensure
      ENV["RUBYOPT"] = original_rubyopt
      ENV["K_SOUP_COV_MIN_HARD"] = original_cov_min_hard
    end
  end
end
