# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] - 2026-07-08

### Fixed
- The human-wait hint no longer idles a session with live background work.
  A silent `run_in_background` Bash or compute-only Workflow that outlives the
  agent's `Stop` used to be dropped about a minute later, when Claude Code's
  idle `Notification` fired and the frozen transcript let the hint win — the
  issue #7 regression the transcript oracle exists to prevent. The oracle now
  holds the block while machine-driven work (background jobs, async tasks,
  subagents, workflows) is pending, and discounts only a parked session or one
  the max-age backstop has already retired.
- Uninstall clears the sleep block and confirms it settled while the daemon and
  helper are still alive and registered, before it unregisters the services, so
  a transient `pmset` failure or a SIGKILL-truncated shutdown handler can no
  longer strand `disablesleep=1`. The helper's SIGTERM handler now retries the
  clear until it settles instead of attempting it once.
- The Homebrew cask no longer emits a `depends_on macos` deprecation warning on
  every `brew` operation.

## [0.1.0] - 2026-07-08

First public release of cc-vigil, a transcript-oracle sleep inhibitor for
Claude Code shipped as a signed and notarized menu-bar app.

### Added
- Signed, notarized, and stapled Developer ID release build, distributed as a
  Homebrew cask you install with `brew install yasyf/tap/cc-vigil` on Apple
  Silicon Macs running macOS 14 or newer. The app registers its LaunchAgent and
  root LaunchDaemon via SMAppService at first run, so the cask carries no
  service block.
- Test-only battery seam: when `CC_VIGIL_FAKE_BATTERY_FILE` names a file
  (one line, `battery <percent>` or `ac <percent>`), the daemon polls it in
  place of IOPS battery events — with a loud log — so headless end-to-end
  runs can drive the battery cutout by hand.
- README: Get started (Homebrew cask coming soon, build-from-source path,
  first-run approvals), How it works (the transcript oracle vs hook
  refcounts, sleep mechanics and their invariants), the configuration
  table, and a CLI reference.
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
- The `cc-vigil` CLI (swift-argument-parser, logic in the new CCVigilCLIKit
  library): `nudge` reads hook JSON from stdin, resolves the nearest `claude`
  ancestor pid, and fails open — one stderr warning, always exit 0; `status
  [--json]` renders blocking/helper-connectivity/sessions-with-reasons/holds/
  cutouts/pause (the status wire report now carries a `helper` link field);
  `hold --for <duration> --reason <s>` / `release <key>`; `pause --for` /
  `resume`; `log [-f]` tails `events.log` with rotation-aware follow; and
  `install-hooks`/`uninstall-hooks` drive the tagged HookInstaller against
  `~/.claude/settings.json` (`--settings` override), embedding the CLI's
  symlink-resolved binary path. An integration test spawns the dry-run
  daemon and proves the wire protocol end to end over `cli.sock`.

- The CCVigil menu-bar app (SwiftUI): a MenuBarExtra with distinct icon
  states (idle/blocking/latched/paused, plus daemon-unreachable), a menu
  showing why the Mac is held awake (session names + reasons from the XPC
  status snapshot), a 1-hour pause toggle, a Keep Awake hold submenu
  (30m/2h/8h with release items), and a while-you-were-away digest of
  `events.log` since the menu was last opened. Status arrives over the
  daemon's app XPC service with generation-counted reconnects; control ops
  ride `cli.sock`. Settings cover the battery-floor/thermal-cutout sliders,
  activity window, hide-menu-bar-icon (persisted in the shared
  `config.json`, with a debounced daemon kickstart so cutout changes take
  effect), launch-at-login, open-events-log, service repair, and a full
  uninstall (hooks, services, CLI symlink). A first-run installer walks a
  tested state machine: Gatekeeper translocation guard, SMAppService
  agent+daemon registration with a one-shot unregister/register remediation
  on "Operation not permitted", Login Items approval with 2s status polling,
  hook install via the bundled CLI, and a `/usr/local/bin` CLI symlink
  falling back to `~/.local/bin`. App-side policy (status view model,
  installer state machine, symlinker, away digest) lives in the new
  CCVigilAppKit library under `swift test`.

[Unreleased]: https://github.com/yasyf/cc-vigil/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/yasyf/cc-vigil/releases/tag/v0.1.1
[0.1.0]: https://github.com/yasyf/cc-vigil/releases/tag/v0.1.0
