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
- CCVigilDaemon, the per-user policy owner: a transcript oracle loop
  (mtime-windowed discovery under `~/.claude/projects` with realpath dedupe,
  per-file CCTranscript probes cached by path/mtime/size, per-session
  skip-with-loud-log on parse failures, and a sysctl `KERN_PROCARGS2` scan
  gating everything on live `claude` processes) driving the root helper over
  XPC with call timeouts, exponential-backoff reconnect, 60s reconcile
  re-pushes while blocking, and re-assert on wake. Monitors feed the cutout
  latch: IOPS battery events plus a 60s lid-closed safety poll, SMC
  thermal reads (Apple Silicon `Tp*`/`Te*` flt average, Intel `TC0P`/`TC0D`
  fallback) polled only while blocking, and an IOPMrootDomain clamshell
  interest notification. The `cli.sock` wire server (0600, 5s socket
  timeouts) serves nudge/status/hold/release/pause/ping; hooks carry no idle
  semantics — `Notification`/`UserPromptSubmit` only maintain human-wait
  hints and every nudge forces an immediate re-evaluation. Recordkeeping
  lands in `~/Library/Application Support/cc-vigil`: fail-fast `config.json`,
  atomic `state.json` with boot/pid hold restore, and a 10MB
  single-rotation `events.log` whose block edges carry full oracle
  snapshots. App XPC pushes status snapshots to subscribers, and a
  `--dry-run` mode (alternate roots, log-only blocking) supports headless
  testing. The transcript FFI adapter lives in the new CCVigilDaemonKit
  library (with the cc-transcript pin now in `CCVigilShared/Package.swift`)
  so oracle composition is exercised by `swift test` against fixture and
  real transcripts.

[Unreleased]: https://github.com/yasyf/cc-vigil/commits/main
