# frozen_string_literal: true

require "json"
require "fileutils"
require "parallel_tests/rspec/runner"
require "rspec/core"
require "shellwords"
require "tempfile"

require_relative "../utils/hash_extension"

module TurboTests
  class Runner
    using CoreExtensions
    DEFAULT_RUNTIME_LOG = "tmp/turbo_rspec_runtime.log"
    DEFAULT_WORKER_OUTPUT_MODE = :warnings
    WORKER_OUTPUT_MODES = %i[warnings stream buffered quiet].freeze

    class << self
      def create(count)
        # We are unable to load parallel tests' tasks in the normal way (top of file)
        # because it requires that the Rails.application instance already be configured
        require "parallel_tests/tasks"

        ENV["PARALLEL_TEST_FIRST_IS_1"] = "true"
        command = ["bundle", "exec", "rake", "db:create", "RAILS_ENV=#{ParallelTests::Tasks.rails_env}"]
        args = {count: count.to_s}
        ParallelTests::Tasks.run_in_parallel(command, args)
      end

      def run(opts = {})
        default_file_discovery = !opts.key?(:files) || opts[:files].nil?
        files = default_file_discovery ? rspec_configured_files_to_run : opts[:files]
        file_selection = normalize_rspec_file_selection(files)
        formatters = opts[:formatters]
        tags = opts[:tags]
        parallel_options = opts[:parallel_options] || {}

        start_time = opts.fetch(:start_time) { RSpec::Core::Time.now }
        runtime_log = opts.fetch(:runtime_log, nil) || DEFAULT_RUNTIME_LOG
        example_status_log = opts.fetch(:example_status_log, nil)
        verbose = opts.fetch(:verbose, false)
        fail_fast = opts.fetch(:fail_fast, nil)
        count = opts.fetch(:count, nil)
        order = normalize_order(opts.fetch(:order, nil))
        seed = opts.fetch(:seed, nil)
        seed_used = order != "defined"
        seed = generate_seed if seed_used && seed.nil?
        print_failed_group = opts.fetch(:print_failed_group, false)
        nice = opts.fetch(:nice, false)
        worker_output = normalize_worker_output_mode(
          opts[:worker_output] || ENV["TURBO_TESTS2_WORKER_OUTPUT"]
        )

        use_runtime_info = default_file_discovery
        parallel_options[:runtime_log] ||= runtime_log

        if example_status_log
          runtime_log = runtime_log_from_example_status(example_status_log)
          parallel_options[:runtime_log] = runtime_log
        elsif use_runtime_info
          parallel_options[:runtime_log] ||= runtime_log
        else
          parallel_options[:group_by] ||= :filesize
        end
        parallel_options[:group_by] ||= :filesize if parallel_options[:only_group]

        warn("VERBOSE") if verbose

        reporter = Reporter.from_config(formatters, start_time, seed, seed_used, files, parallel_options)

        new(
          reporter: reporter,
          formatters: formatters,
          start_time: start_time,
          files: file_selection.fetch(:files),
          test_selectors: file_selection.fetch(:selectors),
          tags: tags,
          runtime_log: runtime_log,
          example_status_log: example_status_log,
          verbose: verbose,
          fail_fast: fail_fast,
          count: count,
          seed: seed,
          seed_used: seed_used,
          order: order,
          print_failed_group: print_failed_group,
          use_runtime_info: use_runtime_info,
          parallel_options: parallel_options,
          nice: nice,
          worker_output: worker_output
        ).run
      end

      def normalize_worker_output_mode(mode)
        value = mode.to_s.strip.downcase.tr("-", "_")
        return DEFAULT_WORKER_OUTPUT_MODE if value.empty?

        normalized = value.to_sym
        return normalized if WORKER_OUTPUT_MODES.include?(normalized)

        raise ArgumentError,
          "Unsupported worker output mode #{mode.inspect}; expected one of: #{WORKER_OUTPUT_MODES.join(", ")}"
      end

      def normalize_rspec_file_selection(files)
        selectors = {}
        files.each do |entry|
          file, selector = split_rspec_location(entry)
          selectors[file] ||= []
          if selector == file
            selectors[file] = [file]
          elsif !selectors[file].include?(file)
            selectors[file] << selector unless selectors[file].include?(selector)
          end
        end

        {files: selectors.keys, selectors: selectors}
      end

      def split_rspec_location(entry)
        value = entry.to_s
        return [value, value] if File.exist?(value)

        match = value.match(/\A(.+):(\d+)\z/)
        return [value, value] unless match && File.exist?(match[1])

        [match[1], value]
      end

      def runtime_log_from_example_status(example_status_log)
        statuses = RSpec::Core::ExampleStatusPersister.load_from(example_status_log)
        runtimes = statuses.each_with_object(Hash.new(0.0)) do |status, sums|
          next unless status.fetch(:status).match?(/pass/i)

          file_name = RSpec::Core::Example.parse_id(status.fetch(:example_id)).first
          sums[file_name] += status.fetch(:run_time).to_s[/\d+(\.\d+)?/].to_f
        end

        path = File.join("tmp", "turbo_tests2_example_status_runtime.log")
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, runtimes.sort.map { |file, runtime| "#{file}:#{runtime}" }.join("\n"))
        path
      end

      def normalize_order(order)
        order = order.to_s.strip.downcase
        return "random" if order.empty?
        return order if %w[random defined].include?(order)

        raise ArgumentError, "Unsupported order #{order.inspect}; use random or defined"
      end

      def generate_seed
        (Random.new_seed % 65_535).to_s
      end

      def rspec_configured_files_to_run
        configuration = RSpec::Core::Configuration.new
        RSpec::Core::ConfigurationOptions.new(["spec"]).configure(configuration)
        root = "#{Dir.pwd}/"
        configuration.files_to_run.map do |path|
          path = path.to_s
          path.start_with?(root) ? path[root.length..-1] : path
        end
      end

      def worker_spec_opts(spec_opts)
        args = project_rspec_options + Array(spec_opts)
        filtered = []
        skip_next = false

        args.each do |arg|
          if skip_next
            skip_next = false
            next
          end

          case arg
          when "--pattern", "-P", "--default-path", "--format", "-f", "--out", "-o"
            skip_next = true
          when /\A--pattern=/, /\A-P.+/, /\A--default-path=/,
            /\A--format=/, /\A-f.+/, /\A--out=/, /\A-o.+/
            next
          else
            filtered << arg
          end
        end

        filtered
      end

      def project_rspec_options(root = Dir.pwd)
        %w[.rspec .rspec-local].flat_map do |path|
          option_file = File.join(root, path)
          next [] unless File.file?(option_file)

          Shellwords.split(File.read(option_file))
        end
      end
    end

    def initialize(**opts)
      @formatters = opts[:formatters]
      @reporter = opts[:reporter]
      @files = opts[:files]
      @test_selectors = opts[:test_selectors] || {}
      @tags = opts[:tags]
      @verbose = opts[:verbose]
      @fail_fast = opts[:fail_fast]
      @start_time = opts[:start_time]
      @count = opts[:count]
      @seed = opts[:seed]
      @seed_used = opts[:seed_used]
      @order = opts[:order]
      @nice = opts[:nice]
      @use_runtime_info = opts[:use_runtime_info]

      @load_time = 0
      @load_count = 0
      @failure_count = 0

      # Supports runtime_log as a top level option,
      #   but also nested inside parallel_options
      @runtime_log = opts[:runtime_log] || DEFAULT_RUNTIME_LOG
      @parallel_options = opts.fetch(:parallel_options, {})
      @parallel_options[:runtime_log] ||= @runtime_log
      @record_runtime = true

      @messages = Thread::Queue.new
      @threads = []
      @wait_threads = []
      @exited_process_ids = []
      @worker_output = Hash.new { |hash, process_id| hash[process_id] = {stdout: +"", stderr: +""} }
      @worker_output_mutex = Mutex.new
      @deferred_run_options_messages = Hash.new { |hash, message| hash[message] = [] }
      @error = false
      @print_failed_group = opts[:print_failed_group]
      @worker_output_mode = self.class.normalize_worker_output_mode(opts.fetch(:worker_output, DEFAULT_WORKER_OUTPUT_MODE))
    end

    def run
      parallel_tests_options = @parallel_options.reject { |key, _value| key == :only_group }
      tests_with_size = ParallelTests::RSpec::Runner.tests_with_size(@files, parallel_tests_options.merge(quiet: true))
      @num_processes = [
        ParallelTests.determine_number_of_processes(@count),
        tests_with_size.size
      ].min

      if @num_processes.zero?
        @tests_in_groups = []
        @reporter.report([]) { |_reporter| }
        return 0
      end

      tests_in_groups =
        ParallelTests::RSpec::Runner.tests_in_groups(
          @files,
          @num_processes,
          **parallel_tests_options
        )
      tests_in_groups = selected_groups(tests_in_groups) if @parallel_options[:only_group]
      @tests_in_groups = tests_in_groups

      subprocess_opts = {
        record_runtime: @record_runtime
      }

      ParallelTests.with_pid_file do
        exit_status = nil
        report_coverage = false

        @reporter.report(tests_in_groups) do |_reporter|
          old_signal = Signal.trap(:INT) { handle_interrupt }

          @wait_threads = tests_in_groups.map.with_index do |tests, process_id|
            start_regular_subprocess(tests, process_id + 1, **subprocess_opts)
          end.compact
          @interrupt_handled = false

          handle_messages

          @threads.each(&:join)

          report_failed_group(tests_in_groups) if @print_failed_group

          Signal.trap(:INT, old_signal)

          statuses = @wait_threads.map(&:value)

          if @reporter.failed_examples.empty? && statuses.all?(&:success?)
            flush_successful_worker_output
            report_coverage = true
            exit_status = 0
          else
            flush_worker_output unless stream_worker_output?
            # From https://github.com/galtzo-floss/turbo_tests2/pull/20/
            exit_status = statuses.map(&:exitstatus).max
          end
        end

        flush_coverage_summary if report_coverage
        exit_status
      end
    end

    private

    def selected_groups(tests_in_groups)
      requested_groups = @parallel_options[:only_group]
      missing_groups = requested_groups.select { |index| index > tests_in_groups.size }
      unless missing_groups.empty?
        raise ArgumentError,
          "Selected group index(es) out of range: #{missing_groups.join(", ")} " \
          "(available groups: #{tests_in_groups.size})"
      end

      requested_groups.map { |index| tests_in_groups[index - 1] }
    end

    def handle_interrupt
      if @interrupt_handled
        Kernel.exit
      else
        puts "\nShutting down subprocesses..."
        report_unfinished_groups("Groups not finished")
        @wait_threads.each do |wait_thr|
          begin
            child_pid = wait_thr.pid
            pgid = Process.respond_to?(:getpgid) ? Process.getpgid(child_pid) : 0
            Process.kill(:INT, child_pid) if Process.pid != pgid
          rescue Errno::ESRCH, Errno::ENOENT
            # process already gone — ignore
          end
        end
        @interrupt_handled = true
      end
    end

    def start_regular_subprocess(tests, process_id, **opts)
      start_subprocess(
        {
          "TEST_ENV_NUMBER" => process_id.to_s,
          "PARALLEL_TEST_GROUPS" => @num_processes.to_s,
          "PARALLEL_PID_FILE" => parallel_pid_file_path
        },
        @tags.map { |tag| "--tag=#{tag}" },
        tests.flat_map { |test| selectors_for_test(test) },
        process_id,
        **opts
      )
    end

    def start_subprocess(env, extra_args, tests, process_id, record_runtime:)
      if tests.empty?
        @messages << {
          type: "exit",
          process_id: process_id
        }

        nil
      else
        env["RSPEC_FORMATTER_OUTPUT_ID"] = SecureRandom.uuid
        env["RUBYOPT"] = ["-I#{File.expand_path("..", __dir__)}", ENV["RUBYOPT"]].compact.join(" ")
        env["RSPEC_SILENCE_FILTER_ANNOUNCEMENTS"] = "1"

        command_name =
          if ENV["RSPEC_EXECUTABLE"]
            ENV["RSPEC_EXECUTABLE"].split
          elsif ENV["BUNDLE_BIN_PATH"]
            [ENV["BUNDLE_BIN_PATH"], "exec", "rspec"]
          else
            "rspec"
          end

        record_runtime_options =
          if record_runtime
            FileUtils.mkdir_p(File.dirname(@runtime_log))
            [
              "--format",
              "ParallelTests::RSpec::RuntimeLogger",
              "--out",
              @runtime_log
            ]
          else
            []
          end

        seed_option = if @seed_used
          [
            "--seed", @seed
          ]
        elsif @order
          [
            "--order", @order
          ]
        else
          []
        end

        spec_opts = self.class.worker_spec_opts(ParallelTests::RSpec::Runner.send(:spec_opts))

        command = [
          *command_name,
          "--options",
          File::NULL,
          *extra_args,
          *seed_option,
          "--format",
          "TurboTests::JsonRowsFormatter",
          *record_runtime_options,
          *spec_opts,
          *tests
        ]
        command.unshift("nice") if @nice

        if @verbose
          command_str = [
            env.map { |k, v| "#{k}=#{v}" }.join(" "),
            command.join(" ")
          ].select { |x| x.size > 0 }.join(" ")

          warn("Process #{process_id}: #{command_str}")
        end

        pid_file_path = env["PARALLEL_PID_FILE"] || parallel_pid_file_path
        stdin, stdout, stderr, wait_thr = Open3.popen3(env, *command)
        track_parallel_pid(wait_thr.pid, pid_file_path)
        stdin.close

        # rubocop:disable ThreadSafety/NewThread
        stdout_thread =
          Thread.new do
            begin
              output_id = env["RSPEC_FORMATTER_OUTPUT_ID"].b
              stdout.each_line do |line|
                result = line.b.split(output_id)

                initial = result.shift
                append_worker_output(process_id, :stdout, initial) unless initial.empty?

                message = result.shift
                next unless message

                message = message.dup.force_encoding(Encoding::UTF_8).scrub
                message = JSON.parse(message, symbolize_names: true)

                message[:process_id] = process_id
                @messages << message
              end
            rescue IOError
              nil
            end

            @messages << {type: "exit", process_id: process_id}
          end
        # rubocop:enable ThreadSafety/NewThread
        @threads << stdout_thread

        stderr_thread = start_copy_thread(stderr, process_id, :stderr)
        @threads << stderr_thread

        # rubocop:disable ThreadSafety/NewThread
        @threads << Thread.new do
          begin
            status = wait_thr.value
            @messages << {type: "error", process_id: process_id} unless status.success?
            @messages << {type: "exit", process_id: process_id}
          ensure
            stop_reader_thread(stdout_thread, stdout)
            stop_reader_thread(stderr_thread, stderr)
            untrack_parallel_pid(wait_thr.pid, pid_file_path)
          end
        end
        # rubocop:enable ThreadSafety/NewThread

        wait_thr
      end
    end

    def parallel_pid_file_path
      ENV["PARALLEL_PID_FILE"]
    end

    def selectors_for_test(test)
      @test_selectors.fetch(test) { [test] }
    end

    def track_parallel_pid(pid, pid_file_path = parallel_pid_file_path)
      ParallelTests::Pids.new(pid_file_path).add(pid) if pid && pid_file_path
    end

    def untrack_parallel_pid(pid, pid_file_path = parallel_pid_file_path)
      ParallelTests::Pids.new(pid_file_path).delete(pid) if pid && pid_file_path
    end

    def start_copy_thread(src, process_id, stream)
      # rubocop:disable ThreadSafety/NewThread
      Thread.new do
        # rubocop:enable ThreadSafety/NewThread
        loop do
          begin
            msg = src.readpartial(4096)
          rescue EOFError
            close_io(src)
            break
          rescue IOError
            break
          else
            append_worker_output(process_id, stream, msg)
          end
        end
      end
    end

    def append_worker_output(process_id, stream, msg)
      return if msg.empty?

      msg = msg.dup.force_encoding(Encoding::UTF_8).scrub
      @worker_output_mutex.synchronize do
        @worker_output[process_id][stream] << msg
      end

      io = (stream == :stderr) ? $stderr : $stdout
      io.write(msg) if stream_worker_output?
    end

    def stream_worker_output?
      @verbose || @worker_output_mode == :stream
    end

    def flush_successful_worker_output
      case @worker_output_mode
      when :warnings
        flush_worker_warnings unless stream_worker_output?
      when :buffered
        flush_worker_output unless stream_worker_output?
      when :quiet, :stream
        nil
      else
        raise ArgumentError,
          "Unsupported worker output mode #{@worker_output_mode.inspect}; expected one of: #{WORKER_OUTPUT_MODES.join(", ")}"
      end
    end

    def flush_worker_output
      output_by_process = @worker_output_mutex.synchronize do
        @worker_output.transform_values(&:dup)
      end

      output_by_process.each do |process_id, streams|
        streams.each do |stream, output|
          next if output.empty?

          io = (stream == :stderr) ? $stderr : $stdout
          io.puts
          io.puts("TurboTests worker #{process_id} #{stream}:")
          io.write(output)
          io.puts unless output.end_with?("\n")
        end
      end
    end

    def flush_worker_warnings
      output_by_process = @worker_output_mutex.synchronize do
        @worker_output.transform_values(&:dup)
      end

      output_by_process.each do |process_id, streams|
        streams.each do |stream, output|
          warnings = warning_lines(output)
          next if warnings.empty?

          io = (stream == :stderr) ? $stderr : $stdout
          io.puts
          io.puts("TurboTests worker #{process_id} #{stream} warnings:")
          warnings.each { |line| io.puts(line) }
        end
      end
    end

    def warning_lines(output)
      output.each_line.each_with_object([]) do |line, warnings|
        stripped = line.strip
        next if stripped.empty?
        next unless warning_line?(stripped)
        next if coverage_output_line?(stripped)

        warnings << stripped
      end
    end

    def warning_line?(line)
      line.match?(/warning:/i) || line.match?(/deprecat/i)
    end

    def coverage_output_line?(line)
      line.start_with?("Coverage report generated for ", "JSON Coverage report generated for ", "Line coverage:", "Branch coverage:", "Line Coverage:", "Branch Coverage:")
    end

    def flush_coverage_summary
      line_coverage = nil
      branch_coverage = nil
      @worker_output_mutex.synchronize do
        @worker_output.each_value do |streams|
          streams.each_value do |output|
            output.each_line do |line|
              stripped = line.strip
              line_coverage = coverage_line("Line", stripped, line_coverage)
              branch_coverage = coverage_line("Branch", stripped, branch_coverage)
            end
          end
        end
      end

      return unless line_coverage || branch_coverage

      puts
      puts("Coverage:")
      puts(line_coverage) if line_coverage
      puts(branch_coverage) if branch_coverage
    end

    def coverage_line(kind, line, current)
      return line if line.start_with?("#{kind} Coverage:")
      return current if current&.start_with?("#{kind} Coverage:")

      match = line.match(/\A#{kind} coverage:\s*(\d+)\s*\/\s*(\d+)\s*\(([^)]+)\)\z/i)
      return current unless match

      "#{kind} Coverage: #{match[3]} (#{match[1]} / #{match[2]})"
    end

    def stop_reader_thread(thread, io)
      return if thread.join(0.1)

      close_io(io)
      return if thread.join(0.1)

      thread.kill
      thread.join(0.1)
    end

    def handle_messages
      exited_process_ids = {}

      loop do
        message = @messages.pop
        case message[:type]
        when "example_passed"
          example = FakeExample.from_obj(message[:example])
          @reporter.example_passed(example)
        when "group_started"
          @reporter.group_started(message[:group].to_struct)
        when "group_finished"
          @reporter.group_finished
        when "example_pending"
          example = FakeExample.from_obj(message[:example])
          @reporter.example_pending(example)
        when "load_summary"
          message = message[:summary]
          # NOTE: notifications order and content is not guaranteed hence the fetch
          #       and count increment tracking to get the latest accumulated load time
          @reporter.load_time = message[:load_time] if message.fetch(:count, 0) > @load_count
        when "example_failed"
          example = FakeExample.from_obj(message[:example])
          @reporter.example_failed(example)
          @failure_count += 1
          if fail_fast_met
            report_unfinished_groups("Groups stopped by fail-fast")
            @threads.each(&:kill)
            break
          end
        when "message"
          if message[:message].include?("An error occurred") || message[:message].include?("occurred outside of examples")
            @reporter.error_outside_of_examples(message[:message])
            @error = true
          elsif run_options_message?(message[:message])
            defer_run_options_message(message[:message], message[:process_id])
          else
            @reporter.message(message[:message])
          end
        when "deprecation"
          @reporter.deprecation(message[:deprecation])
        when "profile"
          @reporter.profile(message[:profile])
        when "seed", "close", "error"
          # Do nothing
          nil
        when "exit"
          process_id = message[:process_id]
          next if exited_process_ids.key?(process_id)

          exited_process_ids[process_id] = true
          @exited_process_ids << process_id
          break if exited_process_ids.size == @num_processes
        else
          warn("Unhandled message in main process: #{message}")
        end

        $stdout.flush
      end

      flush_deferred_run_options_messages
    rescue Interrupt
    end

    def run_options_message?(message)
      message.to_s.start_with?("Run options:")
    end

    def defer_run_options_message(message, process_id)
      @deferred_run_options_messages[message] << process_id
    end

    def flush_deferred_run_options_messages
      return if @deferred_run_options_messages.empty?

      if @deferred_run_options_messages.one?
        @reporter.message(@deferred_run_options_messages.keys.first)
      else
        lines = @deferred_run_options_messages.map do |message, process_ids|
          "  workers #{process_ids.uniq.sort.join(", ")}: #{message}"
        end
        @reporter.message(["Run options by worker:", *lines].join("\n"))
      end
      @deferred_run_options_messages.clear
    end

    def close_io(io)
      io.close unless io.closed?
    rescue IOError
      nil
    end

    def fail_fast_met
      !@fail_fast.nil? && @failure_count >= @fail_fast
    end

    def report_failed_group(tests_in_groups)
      @wait_threads.map(&:value).each_with_index do |value, index|
        next if value.success?

        failing_group = tests_in_groups[index].join(" ")
        puts "Group that failed: #{failing_group}"
      end
    end

    def report_unfinished_groups(label)
      groups = Array(@tests_in_groups)
      unfinished_groups = groups.each_with_index.with_object([]) do |(tests, index), unfinished|
        process_id = index + 1
        unfinished << tests unless @exited_process_ids.include?(process_id)
      end

      return if unfinished_groups.empty?

      puts "#{label}:"
      unfinished_groups.each_with_index do |tests, index|
        puts "  #{index + 1}) #{tests.join(" ")}"
      end
    end
  end
end
