# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe TurboTests::TestProgress do
  let(:io) { StringIO.new }
  let(:now) { [0.0] }
  let(:progress) { described_class.new(io: io, interval: 1.0, clock: -> { now[0] }) }

  def events
    io.string.lines.map(&:strip).reject(&:empty?).map { |line| JSON.parse(line) }
  end

  describe ".enabled? / .from_env" do
    it "is off by default" do
      expect(described_class.enabled?({})).to be(false)
      expect(described_class.from_env(env: {})).to be_nil
    end

    it "is on for KETTLE_TEST_EVENTS=1" do
      expect(described_class.from_env(io: io, env: {"KETTLE_TEST_EVENTS" => "1"})).to be_a(described_class)
    end

    it "falls back to the default interval on garbage" do
      env = {"KETTLE_TEST_EVENTS" => "true", "KETTLE_TEST_EVENTS_INTERVAL" => "abc"}
      expect(described_class.from_env(io: io, env: env).instance_variable_get(:@interval)).to eq(1.0)
    end
  end

  it "throttles ticks to the interval and never emits per example" do
    5.times { progress.record(:passed) }
    expect(events.size).to eq(1)
    now[0] = 0.5
    progress.record(:passed)
    expect(events.size).to eq(1)
    now[0] = 1.2
    progress.record(:pending)
    expect(events.size).to eq(2)
    expect(events.last).to include(
      "type" => "test_progress", "event_version" => 1, "kind" => "tick",
      "examples" => 7, "failures" => 0, "pending" => 1, "elapsed" => 1.2
    )
  end

  it "emits an immediate failure event regardless of throttle" do
    progress.record(:passed)
    progress.record(:failed, {location: "./spec/a_spec.rb:3", full_description: "A fails"})
    expect(events.last).to include(
      "kind" => "failure", "failures" => 1, "examples" => 2,
      "location" => "./spec/a_spec.rb:3", "description" => "A fails"
    )
  end

  it "emits a final event" do
    progress.record(:passed)
    progress.finish
    expect(events.last).to include("kind" => "final", "examples" => 1)
  end
end
