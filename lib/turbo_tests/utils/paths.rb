# frozen_string_literal: true

module TurboTests
  module Utils
    # Makes discovered spec paths relative to the cwd that owns the RSpec
    # configuration, in a way that survives the same directory being spelled
    # two different ways.
    #
    # == Why string comparison of paths is not safe here
    #
    # A path string is a *name*, not an identity. One directory can have
    # several valid names, and the two names can reach this module from
    # different APIs within the same process.
    #
    # On the Windows CI runner (windows-latest, github/actions) this is not
    # hypothetical. Measured from the runner itself:
    #
    #   Dir.pwd        => "C:/Users/RUNNER~1/AppData/Local/Temp/turbo-tests2-...-ujisy2"
    #   ENV["TEMP"]    => "C:\\Users\\RUNNER~1\\AppData\\Local\\Temp"
    #   Dir.tmpdir     => "C:/Users/RUNNER~1/AppData/Local/Temp"
    #   Dir.glob result => "C:/Users/runneradmin/AppData/Local/Temp/turbo-tests2-...-ujisy2/gems/example/spec/example_spec.rb"
    #
    # `RUNNER~1` is an 8.3 short name; `runneradmin` is the long name of the
    # same directory. `Dir.pwd` and the environment report the short form while
    # `Dir.glob` — which RSpec uses to expand `--pattern` — reports the long
    # form. Both are correct, and they are never equal as strings.
    #
    # In this codebase the mismatch has a second, platform-independent face:
    # a symlinked ancestor. On Fedora, `/home/pboling` is a symlink to
    # `/var/home/pboling`, so `Dir.pwd` can report one form while a path built
    # from an ENV var or a stored fixture reports the other. That is what makes
    # this bug reproducible in specs without a Windows runner.
    #
    # == Approaches that do NOT work, and why
    #
    # All four were tried on this branch and all failed. Recorded so nobody
    # repeats the sequence.
    #
    # 1. String prefix, the original code:
    #
    #      root_prefix = "#{root}/"
    #      expanded.start_with?(root_prefix)
    #
    #    Never matches when the two spellings differ, so the absolute temp path
    #    leaks through. parallel_tests then calls File.stat on it during group
    #    sizing. It also wrongly reports "project-other/spec" as inside
    #    "project", which is why spec/utils/paths_spec.rb covers siblings.
    #
    # 2. Canonicalize with File.realpath, then compare:
    #
    #      File.realpath(path) == File.realpath(root) # conceptually
    #
    #    WRONG PREMISE: File.realpath does NOT expand 8.3 short names. Measured
    #    on the runner, realpath of the short path returns the short path
    #    unchanged:
    #
    #      root_realpath => "C:/Users/RUNNER~1/AppData/Local/Temp/turbo-tests2-..."
    #
    #    Canonicalization therefore cannot reconcile the two spellings at all.
    #    (kettle-dev's Kettle::Dev::Paths.canonical documents realpath as
    #    expanding 8.3 names; that comment is inaccurate. Worth correcting if
    #    this module is ever extracted to a shared gem.)
    #
    #    realpath also resolves symlinks, which introduces a second failure
    #    mode: root and file can legitimately traverse different symlink paths
    #    to one directory, and canonicalizing only one side makes them diverge.
    #
    # 3. Component-wise comparison of the canonicalized parts (split on
    #    File::SEPARATOR, compare element by element, case-insensitively on
    #    Windows). Built on the same false premise as #2, so it fails
    #    identically — `RUNNER~1` never equals `runneradmin` in any case
    #    folding. It additionally depended on File::ALT_SEPARATOR, which
    #    measured as "" (empty string, not nil) on that runner, making the
    #    separator-normalizing `tr` a silent no-op. Do not trust ALT_SEPARATOR
    #    to be present.
    #
    # 4. Pathname#relative_path_from, Ruby's own stdlib helper:
    #
    #      Pathname.new(file).relative_path_from(Pathname.new(root)).to_s
    #
    #    It is purely lexical. With differing spellings it walks all the way up
    #    and back down, producing:
    #
    #      "../../../../../runneradmin/AppData/Local/Temp/.../example_spec.rb"
    #
    #    Note it does not raise, so a `rescue ArgumentError` guard cannot catch
    #    it. The result is a plausible-looking but wrong relative path, which is
    #    worse than the leak in #1 because it silently selects the wrong files.
    #    The same nonsense appears on the symlink case:
    #    "../../../../../../var/home/pboling/src/my/...".
    #
    # == The approach that works
    #
    # File.identical? asks the filesystem whether two names denote one object,
    # by inode on Unix and by file index on Windows. It is spelling-agnostic,
    # which is exactly the property needed. Measured on the runner:
    #
    #   File.identical?(root, root) => true
    #   File.identical?(file, file) => true
    #
    # and a walk-up from the long-name file to the short-name root produced the
    # correct "gems/example/spec/example_spec.rb", while the string-prefix and
    # Pathname baselines both failed in the same run.
    #
    # So: ascend from the file, asking at each level "is this the root?", and
    # re-join the basenames on the way back down. The relative path is built
    # from the *file's* spelling, which is what the caller needs, since
    # parallel_tests stats these paths and spawns workers from this cwd.
    #
    # == How this was finally diagnosed
    #
    # The failure only reproduced on the Windows CI runner, and its output was
    # swallowed: these discovery specs run a subprocess via Open3.capture3 whose
    # stderr is only surfaced when the status check fails, and the assertion
    # that failed was the JSON comparison. Four blind fixes failed in a row.
    #
    # What resolved it was a temporary, Windows-guarded spec
    # (`if: Gem.win_platform?`) that deliberately failed with the diagnostic
    # JSON embedded in the expectation message, so the runner's real path forms
    # printed into the CI log. Guarding it kept the other 22 checks green while
    # one job reported the data. That spec is deleted; the findings it produced
    # are this comment plus spec/utils/paths_spec.rb.
    #
    # Lesson: when a bug is environment-specific and the environment is not
    # available locally, spend the iteration on instrumenting the real
    # environment rather than on another hypothesized fix.
    module Paths
      module_function

      # Returns the path of +file+ relative to +root+ when +file+ is +root+
      # itself or lives inside it, compared by filesystem identity rather than
      # by string.
      #
      # Returns the expanded +file+ unchanged when it is not inside +root+
      # (there is nothing to strip) or when identity cannot be established,
      # e.g. because one side does not exist. That matches the long-standing
      # behavior of passing through paths outside the root untouched.
      #
      # @param file [String, Pathname] path to make relative; expanded against
      #   the current directory when relative
      # @param root [String, Pathname] directory to make +file+ relative to
      # @return [String] relative path using File::SEPARATOR, "." when the two
      #   name the same directory, or the expanded +file+ when it is not inside
      #   +root+
      def relative_from(file, root)
        expanded_file = File.expand_path(file.to_s)
        relative = relative_to_root(expanded_file, root)

        relative || expanded_file
      end

      # Returns true when +file+ is +root+ itself or lives inside it, compared
      # by filesystem identity.
      #
      # Unlike a string prefix test this does not treat a sibling directory
      # that merely shares a prefix ("project-other") as being inside "project".
      #
      # @param file [String, Pathname, nil]
      # @param root [String, Pathname, nil]
      # @return [Boolean] false when either argument is nil or empty
      def within?(file, root)
        return false if blank?(file) || blank?(root)

        relative_to_root(File.expand_path(file.to_s), root).is_a?(String)
      end

      # The path of +expanded_file+ relative to +root+: "." when they name the
      # same directory, or nil when +root+ is not an ancestor.
      #
      # Guarded by File.exist? on both sides because File.identical? raises
      # ENOENT rather than returning false for a missing path, and because a
      # path that does not exist has no filesystem identity to compare.
      def relative_to_root(expanded_file, root)
        expanded_root = File.expand_path(root.to_s)
        return nil unless File.exist?(expanded_file) && File.exist?(expanded_root)

        relative_parts(expanded_file, expanded_root)
      end
      private_class_method :relative_to_root

      # Ascend until the two paths are identical by filesystem identity,
      # re-joining basenames on the way back down.
      #
      # Recursion terminates on its own: File.dirname of the filesystem root
      # returns itself ("C:/" or "/"), so the `parent == expanded_file` check
      # ends every walk. No depth constant is needed. Depth is bounded by the
      # path length, which is shallow for any real spec tree; the cost is one
      # stat pair per level.
      #
      # @return [String, nil] relative path, "." for the same directory, or nil
      #   when the root was never reached
      def relative_parts(expanded_file, expanded_root)
        return "." if identical?(expanded_file, expanded_root)

        parent = File.dirname(expanded_file)
        return nil if parent == expanded_file

        append_basename(relative_parts(parent, expanded_root), File.basename(expanded_file))
      end
      private_class_method :relative_parts

      # Prepend +basename+ to the tail produced by the level above. Propagates
      # nil, so "root not found" survives the unwind instead of being rebuilt
      # into a partial path.
      def append_basename(tail, basename)
        return nil unless tail

        (tail == ".") ? basename : File.join(tail, basename)
      end
      private_class_method :append_basename

      # Filesystem-identity comparison that tolerates a missing path, where
      # File.identical? raises ENOENT. Falls back to string equality, which is
      # the correct answer when neither side is a symlink or an 8.3 short name.
      #
      # Rescues SystemCallError rather than Errno::ENOENT alone, because
      # ENOTDIR, ELOOP and EACCES all mean "identity unknown" here, and the
      # string fallback is the safest available answer in each case.
      def identical?(left, right)
        File.identical?(left, right)
      rescue SystemCallError
        left == right
      end
      private_class_method :identical?

      # Treats nil and "" alike. Uses to_s so nil never reaches a nil-check
      # that a linter would flag, and so a Pathname or other to_s-able object
      # is accepted.
      def blank?(value)
        value.to_s.empty?
      end
      private_class_method :blank?
    end
  end
end
