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

Next release should be `3.1.0`.

This is a minor release: it adds backward-compatible CLI options and developer workflow features,
and fixes reporting fidelity. No breaking changes are known.

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

### Deprecated

### Removed

### Fixed

- Reconstructed failure backtraces now filter internal `turbo_tests2` frames.
- Coverage was refreshed by adding focused specs for the new CLI, reporting, formatter, and
  grouping behaviors.

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

[Unreleased]: https://github.com/galtzo-floss/turbo_tests2/compare/v3.0.0...HEAD
[3.0.0]: https://github.com/galtzo-floss/turbo_tests2/compare/7d4064e5b8acc2f53929fccf7be3eb63f8a9f140...v3.0.0
[3.0.0t]: https://github.com/galtzo-floss/turbo_tests2/releases/tag/v3.0.0
