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

#### From `VitalConnectInc/turbo_tests`, now part of `turbo_tests2`

- `--create` flag: create test database(s) before running the suite,
  mirroring the same feature from `parallel_tests`.
- `--print-failed-group` option: after a run, print which subprocess group
  contained the failures so flaky-group triage is easier.
- `--parallel-options` flag: pass arbitrary options through to `parallel_tests`
  (e.g. `--parallel-options "--tests-per-process 5"`).
- `--nice` flag: prefix subprocess invocations with `nice` to run them at
  reduced CPU priority without blocking interactive work.
- Read `.rspec_parallel` config file: honours the parallel-specific RSpec
  options file the same way `parallel_tests` does.
- `RSPEC_EXECUTABLE` environment variable: substitute a custom executable in
  place of the default `rspec` command (useful for Binstubs or wrappers).
- `parallel_tests` v5 compatibility.
- Forward additional `Runner` options to `Reporter` for richer output control.
- Custom-formatter documentation added to README.

#### New in `turbo_tests2`

- `exe/turbo_tests` binary: primary drop-in replacement for the original
  `serpapi/turbo_tests` gem's executable — existing scripts and CI configs
  that call `turbo_tests` work without modification.
- `exe/turbo_tests2` binary: alias for the above; useful when both gems are
  present or when the rename needs to be explicit.
- SimpleCov subprocess coverage via `RUBYOPT` + `.simplecov_spawn.rb`: spawned
  `rspec` child processes now report their coverage back to the parent
  SimpleCov result set, matching the technique described in the
  [SimpleCov README §"Running simplecov against spawned subprocesses"][📎simplecov-spawn].
- Comprehensive test suite built from scratch: line coverage 97.71%,
  branch coverage 90.36% (up from ~27% line / 0% branch at fork time).
  Covers `CLI`, `Runner` (option parsing, subprocess spawning, message
  handling, interrupt handling, failed-group reporting), `Reporter`,
  `JsonRowsFormatter`, and `CoreExtensions::Hash`.
- `kettle-jem` template bootstrap: project tooling, gemfiles, CI, and
  developer-facing configuration aligned with the `galtzo-floss` workspace
  conventions.

[📎simplecov-spawn]: https://github.com/simplecov-ruby/simplecov#running-simplecov-against-spawned-subprocesses

### Changed

- Gem renamed from `turbo_tests` to `turbo_tests2`; the `turbo_tests` binary
  is retained as the canonical entry point for drop-in compatibility.
- Bumped to **v3.0.0** to distinguish the fork from the original
  `serpapi/turbo_tests` gem series, which ended at v2.2.5.
- Use `parallel_tests` directly instead of routing through the now-removed
  `parallel_tests/rspec_runner` wrapper layer
  ([upstream discussion][🔀rm-wrapper]).
- Development Ruby pinned to 4.0.1; CI matrix extended to cover Ruby 2.3 –
  4.x, JRuby, and TruffleRuby.
- Appraisals replaced with `appraisal2` for better `eval_gemfile` support.
- Upgraded GitHub Actions to `actions/checkout@v4` and
  `actions/upload-artifact@v4`.

[🔀rm-wrapper]: https://github.com/serpapi/turbo_tests/pull/45/files#r1456006187

### Deprecated

### Removed

### Fixed

- Delay loading of `parallel_tests` Rake tasks: loading them eagerly at
  require-time caused errors when the tasks weren't needed
  ([VitalConnectInc#13][🐛vitals-13]).
- Improved SIGINT handling: on the first interrupt the runner sends `SIGINT`
  to each subprocess process group (with `Errno::ESRCH` rescue for already-
  gone processes) and sets a handled flag; a second interrupt calls
  `Kernel.exit` immediately, preventing hung CI jobs.

[🐛vitals-13]: https://github.com/VitalConnectInc/turbo_tests/issues/13
[🔀upstream]: https://github.com/serpapi/turbo_tests
[🔀fork-point]: https://github.com/serpapi/turbo_tests/commit/7d4064e5b8acc2f53929fccf7be3eb63f8a9f140
[🔀vitals]: https://github.com/VitalConnectInc/turbo_tests

### Security

[Unreleased]: https://github.com/galtzo-floss/turbo_tests2/compare/v3.0.0...HEAD
[3.0.0]: https://github.com/galtzo-floss/turbo_tests2/compare/7d4064e5b8acc2f53929fccf7be3eb63f8a9f140...v3.0.0
[3.0.0t]: https://github.com/galtzo-floss/turbo_tests2/releases/tag/v3.0.0
