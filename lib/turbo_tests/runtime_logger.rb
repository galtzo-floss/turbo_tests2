# frozen_string_literal: true

require "rspec/core"
require "runtime_groups"

# RSpec formatter that records per-file runtimes into a runtime log
# (TurboGroups path:seconds format, read back by RuntimeGroups::Grouping).
# Semantics retained from parallel_tests' RuntimeLogger:
# - only records when running in parallel (TEST_ENV_NUMBER is set)
# - accumulates time across nested example groups per top-level file
# - appends at dump time, sorted slowest-first
# Min-merging across re-runs happens in RuntimeGroups::RuntimeLog.read via
# last-write-wins per line, and worker groups are disjoint, so concurrent
# workers never write the same file.
class TurboTests::RuntimeLogger
  RSpec::Core::Formatters.register self, :example_group_started, :example_group_finished, :start_dump

  def initialize(output)
    @output = output
    @example_times = Hash.new(0)
    @group_nesting = 0
    @time = 0.0
  end

  def example_group_started(_notification)
    @group_nesting += 1
    @time = monotonic if @group_nesting == 1
  end

  def example_group_finished(notification)
    @group_nesting -= 1
    if @group_nesting.zero?
      @example_times[notification.group.file_path] += monotonic - @time
    end
  end

  def seed(*)
  end

  def dump_summary(*)
  end

  def dump_failures(*)
  end

  def dump_pending(*)
  end

  def message(*)
  end

  def close(*)
  end

  def start_dump(*)
    return unless ENV["TEST_ENV_NUMBER"] # only record when running in parallel

    log_path = output_path
    return unless log_path

    log = RuntimeGroups::RuntimeLog.new(log_path)
    @example_times.sort_by(&:last).reverse_each do |file, time|
      relative_path = file.sub(%r{^#{Regexp.escape(Dir.pwd)}/}, "").sub(%r{^\./}, "")
      log.log(relative_path, [time, 0].max)
    end
  end

  private

  def monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def output_path
    @output.respond_to?(:path) ? @output.path : @output.to_s
  end
end
