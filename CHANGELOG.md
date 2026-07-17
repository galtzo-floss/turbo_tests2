# Changelog

[![SemVer 2.0.0][📌semver-img]][📌semver] [![Keep-A-Changelog 1.0.0][📗keep-changelog-img]][📗keep-changelog]

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog][📗keep-changelog],
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html),
and [yes][📌major-versions-not-sacred], platform and engine support are part of the [public API][📌semver-breaking].
Please file a bug if you notice a violation of semantic versioning.

[📌semver]: https://semver.org/spec/v2.0.0.html
[📌semver-img]: https://img.shields.io/badge/semver-2.0.0-FFDD67.svg?style=flat
[📌semver-breaking]: https://github.com/semver/semver/issues/716#issuecomment-869336139
[📌major-versions-not-sacred]: https://tom.preston-werner.com/2022/05/23/major-version-numbers-are-not-sacred.html
[📗keep-changelog]: https://keepachangelog.com/en/1.0.0/
[📗keep-changelog-img]: https://img.shields.io/badge/keep--a--changelog-1.0.0-FFDD67.svg?style=flat

## [Unreleased]

### Added

### Changed

### Deprecated

### Removed

### Fixed

- Worker commands now override RSpec's default options file, then explicitly
  pass filtered project `.rspec` options. File-discovery options such as
  `--pattern` are dropped after `turbo_tests2` has already selected each shard,
  preventing aggregate suite patterns from making every worker run the full
  suite while preserving options like `--require spec_helper`.

### Security

## [3.1.13] - 2026-07-16

- TAG: [v3.1.13][3.1.13t]
- COVERAGE: 97.50% -- 741/760 lines in 10 files
- BRANCH COVERAGE: 88.35% -- 182/206 branches in 10 files
- 35.87% documented

### Fixed

- Duplicate RSpec `Run options:` messages from parallel workers are now
  collapsed so they no longer interrupt progress formatter output repeatedly.

## [3.1.12] - 2026-07-16

- TAG: [v3.1.12][3.1.12t]
- COVERAGE: 97.04% -- 722/744 lines in 10 files
- BRANCH COVERAGE: 85.50% -- 171/200 branches in 10 files
- 35.87% documented

### Fixed

- `file:line` RSpec selectors are now supported when passed to `turbo_tests2`;
  files are grouped by real path and workers receive the original line-filtered
  selectors.

## [3.1.11] - 2026-07-16

- TAG: [v3.1.11][3.1.11t]
- COVERAGE: 97.37% -- 704/723 lines in 10 files
- BRANCH COVERAGE: 88.42% -- 168/190 branches in 10 files
- 36.67% documented

### Fixed

- No-argument runs once again discover the default `spec` tree while still
  honoring `.rspec` pattern overrides.

- Default RSpec file discovery now uses Ruby 2.4-compatible path handling.

## [3.1.10] - 2026-07-15

- TAG: [v3.1.10][3.1.10t]
- COVERAGE: 97.65% -- 706/723 lines in 10 files
- BRANCH COVERAGE: 88.95% -- 169/190 branches in 10 files
- 36.67% documented

### Fixed

- No-argument runs now use RSpec configuration for file discovery, including
  `.rspec` `--pattern` settings, instead of assuming a top-level `spec/`
  directory.

## [3.1.9] - 2026-07-14

- TAG: [v3.1.9][3.1.9t]
- COVERAGE: 97.60% -- 692/709 lines in 10 files
- BRANCH COVERAGE: 89.13% -- 164/184 branches in 10 files
- 37.08% documented

### Fixed

- Buffered non-RSpec worker stdout/stderr so successful parallel runs no longer
  leak interleaved coverage formatter output, while still reporting a single
  concise coverage summary.
- Prevented invalid UTF-8 bytes in worker output from crashing the parent
  runner on JRuby after the underlying RSpec examples pass.

## [3.1.8] - 2026-07-14

- TAG: [v3.1.8][3.1.8t]
- COVERAGE: 97.40% -- 636/653 lines in 10 files
- BRANCH COVERAGE: 89.47% -- 136/152 branches in 10 files
- 37.08% documented

## [3.1.7] - 2026-07-11

- TAG: [v3.1.7][3.1.7t]
- COVERAGE: 97.40% -- 636/653 lines in 10 files
- BRANCH COVERAGE: 89.47% -- 136/152 branches in 10 files
- 37.08% documented

### Changed

- Clarified project metadata, README, and CLI help to describe `turbo_tests2`
  as an RSpec parallel runner built on `parallel_tests`.

### Fixed

- Fixed generated README metadata backticks around `turbo_tests2` in the
  package description.

## [3.1.6] - 2026-07-02

- TAG: [v3.1.6][3.1.6t]
- COVERAGE: 97.40% -- 636/653 lines in 10 files
- BRANCH COVERAGE: 89.47% -- 136/152 branches in 10 files
- 37.08% documented

### Fixed

- Package configured license files in gem release file lists.

## [3.1.5] - 2026-06-23

- TAG: [v3.1.5][3.1.5t]
- COVERAGE: 97.09% -- 634/653 lines in 10 files
- BRANCH COVERAGE: 88.82% -- 135/152 branches in 10 files
- 37.08% documented

### Added

- Added support for JRuby 10.1 and TruffleRuby 34.0.

### Changed

- Retemplated project metadata and CI/development automation with `kettle-jem` v7.0.0.

### Fixed

- Fixed subprocess coverage setup for SimpleCov v1 by starting coverage
  explicitly in the spawn shim and detecting active coverage via Ruby's
  `Coverage.running?` API.
- Fixed SimpleCov boot order so kettle-soup-cover formatter configuration loads
  after SimpleCov finishes requiring its defaults.

- Added `PARALLEL_PID_FILE` to `turbo_tests2 fan` worker environments so
  SimpleCov parallel result collation does not fail when workers inherit
  `PARALLEL_TEST_GROUPS`.
- Made CLI integration specs assert combined stdout/stderr output so older
  Ruby engines that emit warnings or RSpec load errors on stderr are covered.
- Relaxed CLI load-error detail expectations only on TruffleRuby, where some
  supported versions exit nonzero but omit the RSpec load-error summary.

## [3.1.4] - 2026-06-17

- TAG: [v3.1.4][3.1.4t]
- COVERAGE: 94.33% -- 666/706 lines in 16 files
- BRANCH COVERAGE: 79.11% -- 125/158 branches in 16 files
- 37.08% documented

### Fixed

- Prevented parallel test runs from hanging when a worker process exits but its
  stdout or stderr pipe remains open, a failure mode observed on JRuby
  current/head jobs.

- Ensured worker stdout/stderr reader threads are force-stopped after worker
  process exit if an engine keeps them blocked after pipe closure, fixing
  TruffleRuby 25.0 CI failures in the worker pipe cleanup regression spec.

## [3.1.3] - 2026-06-14

- TAG: [v3.1.3][3.1.3t]
- COVERAGE: 94.62% -- 651/688 lines in 16 files
- BRANCH COVERAGE: 79.33% -- 119/150 branches in 16 files
- 37.08% documented

### Fixed

- Restored `docs/CNAME` so the generated documentation site keeps its custom domain.

## [3.1.2] - 2026-06-08

- TAG: [v3.1.2][3.1.2t]
- COVERAGE: 94.62% -- 651/688 lines in 16 files
- BRANCH COVERAGE: 79.33% -- 119/150 branches in 16 files
- 37.08% documented

### Fixed

- `turbo_tests2` now generates and reports a global random seed by default,
  passes it to every worker process, and supports `--order defined` /
  `--no-random` for ordered runs without a seed.
- Worker PID cleanup now uses the `parallel_tests` pid file path captured when the subprocess starts, avoiding JRuby failures after the pid-file environment is restored.

## [3.1.1] - 2026-06-02

- TAG: [v3.1.1][3.1.1t]
- COVERAGE: 94.63% -- 634/670 lines in 16 files
- BRANCH COVERAGE: 78.17% -- 111/142 branches in 16 files
- 36.78% documented

### Fixed

- The CLI now honors documented `turbo_tests2:setup` and `turbo_tests2:cleanup`
  Rake hooks, while still falling back to legacy `turbo_tests:*` hooks.
- Worker processes now receive the full `parallel_tests` environment metadata, so SimpleCov
  defers minimum coverage enforcement to the combined final result instead of checking each
  shard independently.

- Restored Ruby 2.4 compatibility for worker wait-thread cleanup.
- The coverage workflow now runs `kettle-test` through direct RSpec execution,
  so hard coverage thresholds are checked against the complete suite result
  while other gems can still use `turbo_tests2` under `kettle-test`.

## [3.1.0] - 2026-05-28

- TAG: [v3.1.0][3.1.0t]
- COVERAGE: 95.01% -- 609/641 lines in 16 files
- BRANCH COVERAGE: 77.54% -- 107/138 branches in 16 files
- 36.78% documented

### Added

- `-w` / `--workers` aliases for `-n`, matching the worker-count terminology used by other
  parallel test runners.
- `turbo_tests2 fan`, a generic worker fan-out command that runs an arbitrary command once per
  worker with `TEST_ENV_NUMBER` and `PARALLEL_TEST_GROUPS` set.
- `--example-status-log FILE`, which converts RSpec example-status persistence data into a
  `parallel_tests`-compatible runtime log so grouping can use example-level timing history.

### Changed

- Worker subprocess JSON now forwards RSpec deprecation notifications to the parent reporter.
- Worker subprocess JSON now forwards RSpec profile output to the parent reporter.
- Fail-fast runs now report spec groups that were stopped before execution.
- Interrupted runs now report spec groups that had not finished before shutdown.

### Fixed

- Reconstructed failure backtraces now filter internal `turbo_tests2` frames.
- Coverage was refreshed by adding focused specs for the new CLI, reporting, formatter, and
  grouping behaviors.

- RSpec deprecation notification reconstruction now uses the public `from_hash` API so CI passes
  with RSpec versions where `.new` is private.
- The shim command result object no longer depends on `Struct#keyword_init`, restoring Ruby 2.4
  compatibility.
- Backtrace output specs now accept JRuby 9.2's legacy `block in <main>` frame wording.
- GitHub Actions test jobs now force `kettle-test` to use its direct RSpec runner so coverage
  aggregation remains stable while testing `turbo_tests2` itself.
- GitHub Actions appraisal jobs now pass explicit parent-directory RSpec paths so direct RSpec
  runs execute the real suite instead of finding zero examples from `gemfiles/`.
- Spawned-process coverage setup now locates `.simplecov_spawn.rb` from the working directory
  instead of `Bundler.root`, so appraisal gemfiles do not point it at `gemfiles/`.
- The coverage workflow now uses the same hard coverage thresholds as local development.
- The dedicated coverage workflow now runs RSpec directly so coverage artifacts are written under
  the repository root for upload steps.
- Removed the advanced CodeQL workflow because GitHub CodeQL default setup is enabled and rejects
  SARIF uploads from advanced configurations.

### Security

- Refreshed pinned GitHub Action SHAs.
- Added checksums for the `v3.0.0` release artifacts.

## [3.0.0] - 2026-05-22

- TAG: [v3.0.0][3.0.0t]
- COVERAGE: 96.94% -- 538/555 lines in 17 files
- BRANCH COVERAGE: 90.35% -- 103/114 branches in 17 files
- 37.97% documented

### Added

- Initial release

[Unreleased]: https://github.com/galtzo-floss/turbo_tests2/compare/v3.1.13...HEAD
[3.1.13]: https://github.com/galtzo-floss/turbo_tests2/compare/v3.1.12...v3.1.13
[3.1.13t]: https://github.com/galtzo-floss/turbo_tests2/releases/tag/v3.1.13
[3.1.12]: https://github.com/galtzo-floss/turbo_tests2/compare/v3.1.11...v3.1.12
[3.1.12t]: https://github.com/galtzo-floss/turbo_tests2/releases/tag/v3.1.12
[3.1.11]: https://github.com/galtzo-floss/turbo_tests2/compare/v3.1.10...v3.1.11
[3.1.11t]: https://github.com/galtzo-floss/turbo_tests2/releases/tag/v3.1.11
[3.1.10]: https://github.com/galtzo-floss/turbo_tests2/compare/v3.1.9...v3.1.10
[3.1.10t]: https://github.com/galtzo-floss/turbo_tests2/releases/tag/v3.1.10
[3.1.9]: https://github.com/galtzo-floss/turbo_tests2/compare/v3.1.8...v3.1.9
[3.1.9t]: https://github.com/galtzo-floss/turbo_tests2/releases/tag/v3.1.9
[3.1.8]: https://github.com/galtzo-floss/turbo_tests2/compare/v3.1.7...v3.1.8
[3.1.8t]: https://github.com/galtzo-floss/turbo_tests2/releases/tag/v3.1.8
[3.1.7]: https://github.com/galtzo-floss/turbo_tests2/compare/v3.1.6...v3.1.7
[3.1.7t]: https://github.com/galtzo-floss/turbo_tests2/releases/tag/v3.1.7
[3.1.6]: https://github.com/galtzo-floss/turbo_tests2/compare/v3.1.5...v3.1.6
[3.1.6t]: https://github.com/galtzo-floss/turbo_tests2/releases/tag/v3.1.6
[3.1.5]: https://github.com/galtzo-floss/turbo_tests2/compare/v3.1.4...v3.1.5
[3.1.5t]: https://github.com/galtzo-floss/turbo_tests2/releases/tag/v3.1.5
[3.1.4]: https://github.com/galtzo-floss/turbo_tests2/compare/v3.1.3...v3.1.4
[3.1.4t]: https://github.com/galtzo-floss/turbo_tests2/releases/tag/v3.1.4
[3.1.3]: https://github.com/galtzo-floss/turbo_tests2/compare/v3.1.2...v3.1.3
[3.1.3t]: https://github.com/galtzo-floss/turbo_tests2/releases/tag/v3.1.3
[3.1.2]: https://github.com/galtzo-floss/turbo_tests2/compare/v3.1.1...v3.1.2
[3.1.2t]: https://github.com/galtzo-floss/turbo_tests2/releases/tag/v3.1.2
[3.1.1]: https://github.com/galtzo-floss/turbo_tests2/compare/v3.1.0...v3.1.1
[3.1.1t]: https://github.com/galtzo-floss/turbo_tests2/releases/tag/v3.1.1
[3.1.0]: https://github.com/galtzo-floss/turbo_tests2/compare/v3.0.0...v3.1.0
[3.1.0t]: https://github.com/galtzo-floss/turbo_tests2/releases/tag/v3.1.0
[3.0.0]: https://github.com/galtzo-floss/turbo_tests2/compare/7d4064e5b8acc2f53929fccf7be3eb63f8a9f140...v3.0.0
[3.0.0t]: https://github.com/galtzo-floss/turbo_tests2/releases/tag/v3.0.0
