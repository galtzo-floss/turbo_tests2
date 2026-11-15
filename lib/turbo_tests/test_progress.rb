# frozen_string_literal: true

require "kettle/ndjson"

module TurboTests
  # Opt-in live progress for machine consumers (e.g. `kettle-family test`).
  #
  # Aggregates example outcomes from every worker in the parent process and emits
  # NDJSON `test_progress` events (see README "Live test progress events"):
  # a throttled `tick` (default at most 1/s), an immediate `failure` per failed
  # example, and one `final` event. Never one event per example.
  #
  # Enabled with KETTLE_TEST_EVENTS=1 (or true/yes/on). Off by default.
  class TestProgress
    ENV_KEY = "KETTLE_TEST_EVENTS"
    INTERVAL_ENV_KEY = "KETTLE_TEST_EVENTS_INTERVAL"
    EVENT_TYPE = "test_progress"
    DEFAULT_INTERVAL = 1.0
    TRUTHY = %w[1 true yes on].freeze

    def self.enabled?(env = ENV)
      TRUTHY.include?(env[ENV_KEY].to_s.strip.downcase)
    end

    # @return [TestProgress, nil] nil unless opted in
    def self.from_env(io: $stdout, env: ENV)
      return unless enabled?(env)

      interval = begin
        Float(env.fetch(INTERVAL_ENV_KEY, DEFAULT_INTERVAL.to_s))
      rescue ArgumentError
        DEFAULT_INTERVAL
      end
      new(io: io, interval: interval.negative? ? DEFAULT_INTERVAL : interval)
    end

    attr_reader :examples, :failures, :pending

    def initialize(io: $stdout, interval: DEFAULT_INTERVAL, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @io = io
      @interval = interval
      @clock = clock
      @events = Kettle::Ndjson.event_stream(io, types: EVENT_TYPE, event_types: [EVENT_TYPE])
      @examples = 0
      @failures = 0
      @pending = 0
      @started_at = clock.call
      @last_tick = nil
      @mutex = Mutex.new
    end

    # @param status [Symbol] :passed, :failed or :pending
    # @param example [Hash, nil] row payload (uses :location / :full_description)
    def record(status, example = nil)
      @mutex.synchronize do
        @examples += 1
        case status
        when :failed
          @failures += 1
          emit("failure", location: example && example[:location], description: example && example[:full_description])
          @last_tick = @clock.call
        when :pending
          @pending += 1
        end
        tick_if_due unless status == :failed
      end
    end

    def finish
      @mutex.synchronize { emit("final") }
    end

    private

    def tick_if_due
      now = @clock.call
      return if @last_tick && now - @last_tick < @interval

      @last_tick = now
      emit("tick")
    end

    def emit(kind, extra = {})
      # Leading newline: dots from the progress formatter share stdout and would
      # otherwise prefix the JSON on the same line.
      @io.write("\n") if @io.respond_to?(:write)
      Kettle::Ndjson.emit_event(
        @events,
        EVENT_TYPE,
        {
          kind: kind,
          source: "turbo_tests2",
          examples: @examples,
          failures: @failures,
          pending: @pending,
          elapsed: (@clock.call - @started_at).round(2)
        }.merge(extra)
      )
    end
  end
end
