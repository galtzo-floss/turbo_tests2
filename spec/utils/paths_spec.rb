# frozen_string_literal: true

require "turbo_tests/utils/paths"

# rubocop:disable RSpec/SpecFilePathFormat
RSpec.describe TurboTests::Utils::Paths do
  subject(:paths) { described_class }

  describe ".relative_from" do
    it "returns the path relative to the root" do
      Dir.mktmpdir("turbo-tests2-paths") do |dir|
        FileUtils.mkdir_p(File.join(dir, "gems", "example", "spec"))
        file = File.join(dir, "gems", "example", "spec", "example_spec.rb")
        FileUtils.touch(file)

        expect(paths.relative_from(file, dir))
          .to eq(File.join("gems", "example", "spec", "example_spec.rb"))
      end
    end

    it "returns '.' when the file is the root itself" do
      Dir.mktmpdir("turbo-tests2-paths") do |dir|
        expect(paths.relative_from(dir, dir)).to eq(".")
      end
    end

    it "returns the expanded path when the file is outside the root" do
      Dir.mktmpdir("turbo-tests2-paths") do |dir|
        outside = File.expand_path("..", dir)

        expect(paths.relative_from(outside, dir)).to eq(outside)
      end
    end

    it "returns the expanded path when the file does not exist" do
      Dir.mktmpdir("turbo-tests2-paths") do |dir|
        missing = File.join(dir, "spec", "nope_spec.rb")

        expect(paths.relative_from(missing, dir)).to eq(File.expand_path(missing))
      end
    end

    # Uses a path relative to the real cwd (specs run from the repo root)
    # rather than Dir.chdir, which is process-wide and unsafe under the
    # parallel runner.
    it "expands a relative file path against the current directory" do
      root = Dir.pwd
      file = File.join("spec", "turbo_tests", "runner_spec.rb")
      expect(File.exist?(file)).to be(true)

      expect(paths.relative_from(file, root)).to eq(file)
    end

    it "expands a '.' root to the current directory" do
      file = File.join("spec", "turbo_tests", "runner_spec.rb")
      expect(File.exist?(file)).to be(true)

      expect(paths.relative_from(file, ".")).to eq(file)
    end

    # Windows regression: `Dir.pwd`/`ENV["TEMP"]` report 8.3 short names
    # (C:/Users/RUNNER~1/...) while Dir.glob, which RSpec uses to expand
    # --pattern, reports long names (C:/Users/runneradmin/...). Both spellings
    # name the same directory, but `File.realpath` does not expand 8.3 names,
    # so string prefix matching fails and Pathname#relative_path_from yields
    # "../../../../../runneradmin/...". A symlinked ancestor reproduces the same
    # class of mismatch portably, and File.identical? resolves it because it
    # compares by filesystem identity rather than by string.
    it "strips the root when the file path is spelled through a symlinked ancestor" do
      Dir.mktmpdir("turbo-tests2-paths") do |dir|
        real_root = File.realpath(dir)
        FileUtils.mkdir_p(File.join(real_root, "gems", "example", "spec"))
        file = File.join(real_root, "gems", "example", "spec", "example_spec.rb")
        FileUtils.touch(file)

        # A second, uniquely-named tmpdir holds the symlink, so both its name
        # and its parent are unique to this run. This avoids the Errno::EEXIST
        # collision a fixed name in the shared system temp dir would cause
        # under the parallel runner, and lets mktmpdir remove the symlink
        # itself (via lstat, without following it into real_root), so there is
        # no manual unlink that could race with or remove another run's link.
        Dir.mktmpdir("turbo-tests2-paths-link") do |link_dir|
          link = File.join(link_dir, "ancestor")
          begin
            File.symlink(real_root, link)
          rescue NotImplementedError, Errno::EACCES, Errno::EPERM
            skip "symlinks unavailable on this filesystem"
          end

          # root spelled via the symlink, file spelled via the real path
          expect(paths.within?(file, link)).to be(true)
          expect(paths.relative_from(file, link))
            .to eq(File.join("gems", "example", "spec", "example_spec.rb"))

          # and the reverse spelling: file via the symlink, root via the real path
          linked_file = File.join(link, "gems", "example", "spec", "example_spec.rb")
          expect(paths.within?(linked_file, real_root)).to be(true)
          expect(paths.relative_from(linked_file, real_root))
            .to eq(File.join("gems", "example", "spec", "example_spec.rb"))
        end
      end
    end
  end

  describe ".within?" do
    it "is false for nil arguments" do
      expect(paths.within?(nil, Dir.pwd)).to be(false)
      expect(paths.within?(Dir.pwd, nil)).to be(false)
    end

    it "is true for a file directly in the root" do
      Dir.mktmpdir("turbo-tests2-paths") do |dir|
        file = File.join(dir, "a_spec.rb")
        FileUtils.touch(file)

        expect(paths.within?(file, dir)).to be(true)
      end
    end

    it "is false for a sibling directory that shares a string prefix" do
      Dir.mktmpdir("turbo-tests2-paths") do |root|
        dir = File.join(root, "project")
        sibling = File.join(root, "project-other")
        FileUtils.mkdir_p(File.join(dir, "spec"))
        FileUtils.mkdir_p(File.join(sibling, "spec"))
        file = File.join(sibling, "spec", "a_spec.rb")
        FileUtils.touch(file)

        # A string prefix check would wrongly report this as inside "project".
        expect(paths.within?(file, dir)).to be(false)
      end
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
