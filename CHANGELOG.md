# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial scaffolding.
- Xcode project skeleton (XcodeGen `project.yml`): the CCVigil menu-bar app with
  CCVigilDaemon (LaunchAgent), CCVigilHelper (LaunchDaemon), and the `cc-vigil`
  CLI embedded in its bundle, all sharing the local CCVigilShared package.
- CI on macos-26: swiftformat/swiftlint, `xcodebuild` build of the CCVigil
  scheme, and `swift test` for CCVigilShared.
- CCTranscript oracle dependency (revision-pinned SwiftPM git package from
  [cc-transcript](https://github.com/yasyf/cc-transcript)) wired into
  CCVigilDaemon, with a placeholder `sessionActivity` probe.
- CCVigilShared policy core (pure logic, injected `WallClock`, no IOKit/XPC/
  filesystem): `OracleState` transcript-activity composition with human-wait
  hint discount, pending-async max-age backstop, and the global claude-process
  gate; `SleepBlockPolicy` idempotence/crash-recovery state machine composing
  IOPM + `pmset` outcomes; battery/thermal `CutoutLatch` with hysteresis;
  `HoldRegistry` manual holds (24h TTL clamp, boot/pid restore filter); the
  `[UInt32 BE][JSON]` wire codec with nudge/status/hold/release/pause/ping
  ops; and the surgical `HookInstaller` for `_cc_vigil`-tagged Claude
  settings hooks. Replaces the `Verdict` placeholder.
- CCVigilHelper root LaunchDaemon: the deliberately tiny XPC surface
  (`setSleepBlocked`/`sleepBlockedState`/`version` on
  `dev.yasyf.cc-vigil.helper`), gated at runtime by `CallerVerifier` —
  audit token to `SecCode`, a team-pinned requirement with the exact daemon
  identifier, and a name-only fallback for ad-hoc builds. Sleep mechanics
  run through the shared `SleepBlocker`, composing `SleepBlockPolicy` with
  an idempotent IOPM idle assertion and `pmset -a disablesleep` under a 10s
  watchdog with a concurrent stderr drain. Force-clears on helper init, on
  SIGTERM, and via a 60s generation-counted dead-man after the last daemon
  connection drops while blocked. `SMAuthorizedClients` templates the team
  requirement from `DEVELOPMENT_TEAM` at build time (name-checked in Debug).

[Unreleased]: https://github.com/yasyf/cc-vigil/commits/main
