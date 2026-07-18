# frozen_string_literal: true

require "optparse"

module TurboTests
  class CLI
    def initialize(argv)
      @argv = argv
    end

    def run
      handle_shim_command if shim_command?
      handle_fan_command if fan_command?

      requires = []
      formatters = []
      tags = []
      count = nil
      runtime_log = nil
      example_status_log = nil
      verbose = false
      fail_fast = nil
      seed = nil
      order = nil
      print_failed_group = false
      create = false
      nice = false
      parallel_options = {}
      cli_args, parallel_args = split_parallel_args(@argv)

      OptionParser.new do |opts|
        opts.banner = <<~BANNER
          Run RSpec files in parallel, giving each process ENV['TEST_ENV_NUMBER'] ('1', '2', '3', ...).

          Uses `parallel_tests` to split files into groups, then reports RSpec results incrementally.

          Source code of `turbo_tests2` gem is based on Discourse and RubyGems work in this area (see README file of the source repository).

          Usage: turbo_tests2 [options]

          [optional] Only selected files & folders:
            turbo_tests2 spec/bar spec/baz/xxx_spec.rb

          Options:
        BANNER

        opts.on("-n [PROCESSES]", "-w [PROCESSES]", "--workers [PROCESSES]", Integer, "How many processes to use, default: available CPUs") do |n|
          count = n
        end

        opts.on("-r", "--require PATH", "Require a file.") do |filename|
          requires << filename
        end

        opts.on(
          "-f",
          "--format FORMATTER",
          "Choose a formatter. Available formatters: progress (p), documentation (d). Default: progress"
        ) do |name|
          formatters << {
            name: name,
            outputs: []
          }
        end

        opts.on("-t", "--tag TAG", "Run examples with the specified tag.") do |tag|
          tags << tag
        end

        opts.on("-o", "--out FILE", "Write output to a file instead of $stdout") do |filename|
          if formatters.empty?
            formatters << {
              name: "progress",
              outputs: []
            }
          end
          formatters.last[:outputs] << filename
        end

        opts.on("--runtime-log FILE", "Location of previously recorded test runtimes") do |filename|
          runtime_log = filename
        end

        opts.on("--example-status-log FILE", "Use RSpec example status persistence timings for grouping") do |filename|
          example_status_log = filename
        end

        opts.on("--pattern PATTERN", "Run spec files matching this regex pattern") do |pattern|
          parallel_options[:pattern] = compile_pattern(pattern)
        end

        opts.on("--exclude-pattern PATTERN", "Exclude spec files matching this regex pattern") do |pattern|
          parallel_options[:exclude_pattern] = compile_pattern(pattern)
        end

        opts.on("--only-group GROUP_INDEX[,GROUP_INDEX]", "Run only the selected 1-based parallel_tests group index(es)") do |groups|
          parallel_options[:only_group] = parse_only_groups(groups)
        end

        opts.on("--group-by MODE", "Group files by runtime, filesize, or found order") do |mode|
          parallel_options[:group_by] = parse_group_by(mode)
        end

        opts.on("--allowed-missing PERCENT", Integer, "Allowed percentage of missing runtimes for runtime grouping") do |percent|
          parallel_options[:allowed_missing_percent] = parse_allowed_missing(percent)
        end

        opts.on("--unknown-runtime SECONDS", Float, "Runtime in seconds to assign files missing runtime history") do |seconds|
          parallel_options[:unknown_runtime] = parse_unknown_runtime(seconds)
        end

        opts.on("-v", "--verbose", "More output") do
          verbose = true
        end

        opts.on("--fail-fast=[N]") do |n|
          n = begin
            Integer(n)
          rescue
            nil
          end
          fail_fast = (n.nil? || n < 1) ? 1 : n
        end

        opts.on("--seed SEED", "Seed for RSpec") do |s|
          seed = s
        end

        opts.on("--order ORDER", "RSpec example order: random (default) or defined") do |value|
          order = value
        end

        opts.on("--no-random", "Run examples in defined order without passing a seed") do
          order = "defined"
        end

        opts.on("--create", "Create databases") do
          create = true
        end

        opts.on("--print_failed_group", "Prints group that had failures in it") do
          print_failed_group = true
        end

        opts.on("--nice", "execute test commands with low priority") do
          nice = true
        end
      end.parse!(cli_args)

      parse_parallel_args(parallel_args, parallel_options) unless parallel_args.empty?

      if create
        return TurboTests::Runner.create(count)
      end

      requires.each { |f| require(f) }

      if formatters.empty?
        formatters << {
          name: "progress",
          outputs: []
        }
      end

      formatters.each do |formatter|
        formatter[:outputs] << "-" if formatter[:outputs].empty?
      end

      load_rake

      invoke_rake_hook("setup")

      files = cli_args.empty? ? nil : cli_args

      exitstatus = TurboTests::Runner.run(
        formatters: formatters,
        tags: tags,
        files: files,
        runtime_log: runtime_log,
        example_status_log: example_status_log,
        verbose: verbose,
        fail_fast: fail_fast,
        count: count,
        seed: seed,
        order: order,
        nice: nice,
        print_failed_group: print_failed_group,
        parallel_options: parallel_options
      )

      invoke_rake_hook("cleanup")

      # From https://github.com/galtzo-floss/turbo_tests2/pull/20/
      exit(exitstatus)
    end

    private

    def shim_command?
      @argv.first == "shim"
    end

    def fan_command?
      @argv.first == "fan"
    end

    def split_parallel_args(args)
      separator_index = args.index("--")
      return [args, []] unless separator_index

      [
        args[0...separator_index],
        args[(separator_index + 1)..-1]
      ]
    end

    def parse_parallel_args(args, parallel_options)
      OptionParser.new do |opts|
        opts.on("--pattern PATTERN", "Run spec files matching this regex pattern") do |pattern|
          parallel_options[:pattern] = compile_pattern(pattern)
        end

        opts.on("--exclude-pattern PATTERN", "Exclude spec files matching this regex pattern") do |pattern|
          parallel_options[:exclude_pattern] = compile_pattern(pattern)
        end

        opts.on("--only-group GROUP_INDEX[,GROUP_INDEX]", "Run only the selected 1-based parallel_tests group index(es)") do |groups|
          parallel_options[:only_group] = parse_only_groups(groups)
        end

        opts.on("--group-by MODE", "Group files by runtime, filesize, or found order") do |mode|
          parallel_options[:group_by] = parse_group_by(mode)
        end

        opts.on("--allowed-missing PERCENT", Integer, "Allowed percentage of missing runtimes for runtime grouping") do |percent|
          parallel_options[:allowed_missing_percent] = parse_allowed_missing(percent)
        end

        opts.on("--unknown-runtime SECONDS", Float, "Runtime in seconds to assign files missing runtime history") do |seconds|
          parallel_options[:unknown_runtime] = parse_unknown_runtime(seconds)
        end
      end.parse!(args)

      return if args.empty?

      raise OptionParser::InvalidArgument, "unsupported parallel_tests argument(s): #{args.join(" ")}"
    end

    def compile_pattern(pattern)
      /#{pattern}/
    rescue RegexpError => error
      raise OptionParser::InvalidArgument, "invalid regex pattern #{pattern.inspect}: #{error.message}"
    end

    def parse_only_groups(groups)
      groups.to_s.split(",").map do |group|
        group = group.strip
        raise OptionParser::InvalidArgument, "invalid group index #{group.inspect}" unless group.match?(/\A[1-9]\d*\z/)

        group.to_i
      end
    end

    def parse_group_by(mode)
      value = mode.to_s.strip
      supported_modes = %w[runtime filesize found]
      unless supported_modes.include?(value)
        raise OptionParser::InvalidArgument, "invalid group-by mode #{value.inspect}; expected one of: #{supported_modes.join(", ")}"
      end

      value.to_sym
    end

    def parse_allowed_missing(percent)
      unless (0..100).cover?(percent)
        raise OptionParser::InvalidArgument, "invalid allowed missing percent #{percent.inspect}; expected 0 through 100"
      end

      percent
    end

    def parse_unknown_runtime(seconds)
      unless seconds.finite? && !seconds.negative?
        raise OptionParser::InvalidArgument, "invalid unknown runtime #{seconds.inspect}; expected a finite non-negative number"
      end

      seconds
    end

    def handle_fan_command
      args = @argv.drop(1)
      count = nil
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: turbo_tests2 fan [options] COMMAND [ARGS]"
        opts.on("-n [PROCESSES]", "-w [PROCESSES]", "--workers [PROCESSES]", Integer, "How many processes to use, default: available CPUs") do |n|
          count = n
        end
      end
      parser.order!(args)

      if args.empty?
        warn(parser)
        exit(1)
      end

      processes = ParallelTests.determine_number_of_processes(count)
      pids = ParallelTests.with_pid_file do
        (1..processes).map do |process_id|
          env = {
            "TEST_ENV_NUMBER" => process_id.to_s,
            "PARALLEL_TEST_GROUPS" => processes.to_s,
            "PARALLEL_PID_FILE" => ParallelTests.pid_file_path
          }
          Process.spawn(env, *args)
        end
      end
      statuses = pids.map { |pid| Process.wait2(pid).last }

      exit(statuses.all?(&:success?) ? 0 : 1)
    rescue OptionParser::ParseError => e
      warn(e.message)
      warn(parser)
      exit(1)
    end

    def handle_shim_command
      command = @argv[1]
      args = @argv.drop(2)

      result =
        case command
        when "install"
          TurboTests::Shim.install(project_root: Dir.pwd, path: parse_shim_path(args, command: command))
        when "remove"
          TurboTests::Shim.remove(project_root: Dir.pwd, path: parse_shim_path(args, command: command))
        else
          warn(shim_usage(command))
          exit(1)
        end

      io = result.exit_code.zero? ? $stdout : $stderr
      io.puts(result.message)
      exit(result.exit_code)
    end

    def parse_shim_path(args, command:)
      path_override = nil
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: turbo_tests2 shim #{command} [--path PATH]"
        opts.on("--path PATH", "Use a custom shim path instead of bin/turbo_tests") { |value| path_override = value }
      end

      remaining = parser.parse(args.dup)
      if remaining.size > 1 || (remaining.any? && path_override)
        warn(shim_usage(command))
        exit(1)
      end

      remaining.first || path_override
    rescue OptionParser::ParseError => e
      warn(e.message)
      warn(shim_usage(command))
      exit(1)
    end

    def shim_usage(command = nil)
      lines = [
        "Usage: turbo_tests2 shim install [--path PATH]",
        "       turbo_tests2 shim remove [--path PATH]"
      ]
      lines << "Unknown shim command: #{command}" if command && !%w[install remove].include?(command)
      lines.join("\n")
    end

    def load_rake
      begin
        require "rake"
      rescue LoadError
        # simplecov:disable
        return # rake is optional
        # simplecov:enable
      end

      # Pass an empty argv so Rake doesn't parse the current process's ARGV,
      # which may contain non-Rake arguments (e.g. RSpec's --pattern flag when
      # tests are run via `rake spec`).
      Rake.application.init("rake", [])
      Rake.application.load_rakefile
    end

    def invoke_rake_task(name)
      return unless defined?(Rake) && Rake::Task.task_defined?(name)

      Rake::Task[name].invoke
    end

    def invoke_rake_hook(name)
      current_task = "turbo_tests2:#{name}"
      legacy_task = "turbo_tests:#{name}"

      return invoke_rake_task(current_task) if defined?(Rake) && Rake::Task.task_defined?(current_task)

      invoke_rake_task(legacy_task)
    end
  end
end
