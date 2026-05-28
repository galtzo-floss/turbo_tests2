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
      print_failed_group = false
      create = false
      nice = false

      OptionParser.new do |opts|
        opts.banner = <<~BANNER
          Run all tests in parallel, giving each process ENV['TEST_ENV_NUMBER'] ('1', '2', '3', ...).

          Reports test results incrementally. Uses methods from `parallel_tests` gem to split files to groups.

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
          "Choose a formatter. Available formatters: progress (p), documentation (d). Default: progress",
        ) do |name|
          formatters << {
            name: name,
            outputs: [],
          }
        end

        opts.on("-t", "--tag TAG", "Run examples with the specified tag.") do |tag|
          tags << tag
        end

        opts.on("-o", "--out FILE", "Write output to a file instead of $stdout") do |filename|
          if formatters.empty?
            formatters << {
              name: "progress",
              outputs: [],
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

        opts.on("-v", "--verbose", "More output") do
          verbose = true
        end

        opts.on("--fail-fast=[N]") do |n|
          n = begin
            Integer(n)
          rescue StandardError
            nil
          end
          fail_fast = (n.nil? || n < 1) ? 1 : n
        end

        opts.on("--seed SEED", "Seed for rspec") do |s|
          seed = s
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
      end.parse!(@argv)

      if create
        return TurboTests::Runner.create(count)
      end

      requires.each { |f| require(f) }

      if formatters.empty?
        formatters << {
          name: "progress",
          outputs: [],
        }
      end

      formatters.each do |formatter|
        formatter[:outputs] << "-" if formatter[:outputs].empty?
      end

      load_rake

      invoke_rake_task("turbo_tests:setup")

      files = @argv.empty? ? ["spec"] : @argv
      parallel_options = {}

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
        nice: nice,
        print_failed_group: print_failed_group,
        parallel_options: parallel_options,
      )

      invoke_rake_task("turbo_tests:cleanup")

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
      pids = (1..processes).map do |process_id|
        env = {
          "TEST_ENV_NUMBER" => process_id.to_s,
          "PARALLEL_TEST_GROUPS" => processes.to_s,
        }
        Process.spawn(env, *args)
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
        "       turbo_tests2 shim remove [--path PATH]",
      ]
      lines << "Unknown shim command: #{command}" if command && !%w[install remove].include?(command)
      lines.join("\n")
    end

    def load_rake
      begin
        require "rake"
      rescue LoadError
        # :nocov:
        return # rake is optional
        # :nocov:
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
  end
end
