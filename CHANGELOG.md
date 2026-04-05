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
- Multi-process integration spec (`spec/integration/multi_process_spec.rb`):
  dogfoods the library's core value proposition by launching real
  `bundle exec turbo_tests -n 2` subprocesses against multiple fixture
  spec files and asserting on the merged, streamed output.  Covers three
  scenarios: passing+pending, failing+passing, and load-error+passing.
  Full suite now at **97 examples, 0 failures**, LINE 98.87%, BRANCH 100%.

### Changed

### Deprecated

### Removed

[📎simplecov-spawn]: https://github.com/simplecov-ruby/simplecov#running-simplecov-against-spawned-subprocesses

### Fixed

### Security

[🔀rm-wrapper]: https://github.com/serpapi/turbo_tests/pull/45/files#r1456006187

