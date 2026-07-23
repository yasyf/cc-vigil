# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.0] - 2026-07-23

### Changed

- `config.json` and `state.json` now use exact, fingerprinted v1 envelopes.
  Present files must match the complete current schema; old, partial, malformed,
  or extra-field shapes fail closed without quarantine, repair, or migration.

## [0.5.0] - 2026-07-23

### Changed

- The persistent CLI transport now pins daemonkit 0.8.1 and uses its exact
  `wireBuild` identity surface throughout clients, servers, and tests.

## [0.4.2] - 2026-07-22

### Changed

- CLI daemon operations are asynchronous end to end. The synchronous
  semaphore bridge is gone, so executor pressure cannot deadlock commands or
  strand persistent sessions during teardown.
- Daemon connections, frame writes, and server shutdown use daemonkit's async
  transport boundary, with coalesced connection setup and cancellation that
  does not poison a shared persistent session.

## [0.4.1] - 2026-07-21

### Fixed

- The generated Homebrew cask now requires macOS 15, matching the app and
  daemonkit transport deployment target.

## [0.4.0] - 2026-07-21

### Changed
- CLI, app-control, and daemon traffic now use daemonkit's persistent,
  multiplexed v1 session transport with exact build equality, bounded admission,
  request deadlines, and same-user peer trust. Hook nudges wait for an explicit
  acknowledgement instead of abandoning a one-shot reply.
- The minimum supported system is macOS 15, matching daemonkit's Swift
  transport boundary.

### Removed
- The private four-byte socket framing, one-connection client/server, connection
  throttle, and misleading `CCVigilDaemonKit` module were deleted. Product
  runtime utilities now live in `CCVigilRuntime`; transport lives in
  `CCVigilTransport`.

## [0.3.0] - 2026-07-10

### Added
- Low Power Mode is a cutout: while macOS Low Power Mode is on, the block
  releases and latches off, clearing the moment the mode turns off. On by
  default; `lowPowerCutout` in `config.json` and the Settings window's
  Cutouts section turn it off.
- Shortcuts can drive the daemon: five App Intents — hold, release, pause,
  resume, and status — wrap the existing daemon commands, keep the CLI's
  24-hour cap on durations, return the status summary for chaining, and fail
  with a readable error when the daemon is unreachable. Launch the app once
  after upgrading so Shortcuts indexes them.
- The daemon composes release and cutout notifications itself and stamps
  each with a persisted, monotonically increasing id; the app replays alerts
  it has not yet posted, exactly once across reconnects and app restarts.
  Toasts no longer misfire or go unseen when an edge lands inside an XPC
  disconnect gap. Alerts older than the recent-alert ring fall to the away
  summary, and `events.log` stays the ground truth.
- After two consecutive background-item registration failures, the installer
  points at `sfltool resetbtm` — macOS occasionally wedges registration, and
  only the reset clears it.

### Changed
- The oracle tracks each session's Claude process. A session whose process
  died is discounted immediately — its stale transcript no longer pins the
  Mac awake for up to 12 hours — while a session whose process is alive
  keeps its hold past the old 12-hour cliff for as long as the work runs,
  and its transcript stays in discovery past the scan window. Sessions the
  hooks never reported a pid for behave exactly as before.
- The transcript oracle matches tool names the way Claude Code spells them:
  an `Execute` background command counts as backgrounded Bash, and
  MCP-wrapped tools such as `mcp__<server>__SendMessage` match their
  configured names. This rides the cc-transcript 10.4.0 oracle, which
  captain-hook now consumes too — one predicate decides "waiting"
  everywhere.

## [0.2.0] - 2026-07-09

### Added
- The app posts a macOS notification when the block releases because agents
  finished — what was holding the Mac awake and when it wrapped up — and when
  a battery or thermal cutout latches mid-block, the one moment sleep
  protection drops while agents are still working. The release banner waits
  until nothing is latched, held, paused, or still active, so a protection
  drop never reads as an all-clear, and banners present even while a
  cc-vigil window is frontmost. Both are on by default; the Settings
  window's Notifications section toggles them (`notifyOnRelease` and
  `notifyOnCutout` in `config.json`). The first edge worth posting asks
  macOS for notification permission.
- The daemon re-asserts the sleep block when the Mac switches between AC and
  battery power. Plugging or unplugging an Apple Silicon MacBook with the lid
  closed can instant-sleep it and drop the assertion out from under a run;
  re-asserting on the transition keeps clamshell runs alive across a charger
  swap.
- The sleep hold now names its owner: the idle assertion carries cc-vigil's
  name and a human-readable reason, so `pmset -g assertions` and Activity
  Monitor's Energy tab attribute the hold to cc-vigil instead of an anonymous
  assertion ID. It also arms a 15-minute timeout that releases the hold on
  its own — re-pushes ride the blocking evaluate cadence (with a 60-second
  reconcile floor), and config now caps the poll cadences
  (`pollBlockingSeconds` 1–300, `pollIdleSeconds` 1–600), so even a
  five-minute cadence re-arms with over nine minutes to spare and a wedged
  or orphaned helper loses the hold instead of pinning the Mac awake.
- Sessions in a relocated Claude config root (`CLAUDE_CONFIG_DIR`) now hold
  the Mac awake instead of being invisible to the oracle. The nudge hook runs
  inside the session, so it forwards the relocated transcripts root that the
  launchd daemon's own environment lacks; the daemon admits a root
  it is not already scanning (deduped by real path, so a symlinked `projects`
  directory does not double-count), scans it alongside `~/.claude/projects`,
  and persists it in `state.json` so it survives a restart. Extra roots can
  also be pinned statically with the new `transcriptsRoots` key in
  `config.json`.
- Every block edge in `events.log` now carries the active holds, so a
  hold-driven block — `cc-vigil hold` with no active sessions — explains
  itself in the log instead of needing a separate hold event to correlate.

### Changed
- The daemon's block-composition and push-decision logic moved into the
  tested CCVigilShared core, so a regression in "should the Mac be held awake
  right now" fails the unit suite instead of surfacing on hardware. No
  behavior change.
- The hardware acceptance playbook lives in the repo's cc-notes store instead
  of a markdown file; the README's Verification section says how to open it.

### Fixed
- The Mac no longer sleeps partway through a long approved tool call such as
  a 25-minute `cargo build`. Approving a permission prompt writes nothing to
  the transcript and fired no installed hook, so the human-wait hint the
  prompt set outlived the approval and idled the still-working session.
  cc-vigil now installs a `PreToolUse` nudge — approval fires it, and the
  transcript does not advance until the tool returns, so it is the only
  signal the approval landed — and clears the hint on it. The nudge is
  fire-and-forget, so the pre-tool hook, which blocks the tool it precedes,
  never waits on the daemon. Existing installs pick up the new hook the next
  time the app runs its installer, or when you run `cc-vigil install-hooks`.
- Background work that outlives its turn — a `run_in_background` build, a
  detached subagent, or a session cron — now holds the sleep block across new
  prompts and auto-compaction. Such work never advances the transcript, so a
  quick follow-up question moved it out of the oracle's view: nothing pended,
  the idle hint discounted the session, and the Mac slept mid-build. Claude
  Code v2.1.145+ reports still-running work on every `Stop`/`SubagentStop`
  payload (`background_tasks`/`session_crons`); the nudge forwards those
  counts and the oracle pins the session awake — immune to the idle hint —
  until a top-level `Stop` reports none running. A `SubagentStop` describes
  only the finishing subagent, so it can add to the hold but never clear it,
  and the pending-async max-age backstop still bounds the pin. The bumped
  cc-transcript pin brings the matching delivery-aware oracle: async
  completions count when their notification is delivered, not when it is
  enqueued.
- Finished subagents no longer pin the Mac awake for hours. Subagent
  sidechain transcripts were probed with main-session semantics, so any
  background task inside a completed subagent read as pending until the
  12-hour backstop — battery drain in a bag, the inverse of the tool's
  promise. Discovery now skips `subagents/` directories (matched on resolved
  paths, so symlinked layouts stay excluded); the parent transcript already
  carries the authoritative pending state.
- A transcript that stops parsing no longer silently drops its session from
  the active set — one malformed line could idle the busiest session. A
  failed probe now reasserts the session's last good probe, or falls back to
  file recency when there is none, so the oracle fails toward keeping the Mac
  awake.
- A helper crash during an in-flight push can no longer swallow the forced
  re-assert and leave the Mac unprotected for up to a minute; re-asserts are
  generation-counted so the next evaluation re-pushes instead of being
  suppressed.
- The daemon no longer dies of SIGPIPE when a fire-and-forget nudge
  disconnects before the reply — the exact traffic the new `PreToolUse` hook
  produces on every tool call.
- Uninstall can no longer boot out the root helper on an unconfirmed clear
  and strand `disablesleep=1`: the clear path's timeouts are coherent
  end-to-end, and a caller timeout means "may still be clearing", not
  permission to proceed. The daemon also caps socket concurrency and recovers
  from an aborted uninstall clear instead of staying stuck shutting down.
- Rebooting while blocked no longer risks stranding `disablesleep=1` until
  login when one `pmset` call fails: the helper's boot-time force-clear
  retries until it confirms, like the SIGTERM and dead-man paths already did.
- CLI hardening: `cc-vigil log --lines` rejects a negative count instead of
  crashing; `pause --for` clamps to the same 24-hour cap as `hold`; `nudge`
  bounds its stdin read instead of buffering a runaway hook payload; and
  `hold` prints the release key before sending, so a reply timeout can no
  longer orphan an already-applied hold.
- Hook installs survive unusual filesystems: the installed nudge command path
  is shell-quoted (a space in the bundle path no longer breaks every nudge),
  `settings.json` writes follow symlinks instead of replacing the link node,
  and uninstall resolves the bundle path before matching the CLI symlink so a
  dangling link is still removed.
- A corrupt `state.json` or `config.json` used to crash-loop the daemon,
  leaving zero sleep protection. The bad file is now quarantined to a
  `.corrupt` sibling with a loud log, and the daemon starts fresh (a corrupt
  config falls back to the built-in defaults).

### Security
- The daemon's app XPC endpoint now verifies callers with the same
  team-pinned verifier the helper uses, so another same-user process can no
  longer read active-session status and transcript paths.

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

[Unreleased]: https://github.com/yasyf/cc-vigil/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/yasyf/cc-vigil/compare/v0.4.2...v0.5.0
[0.4.2]: https://github.com/yasyf/cc-vigil/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/yasyf/cc-vigil/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/yasyf/cc-vigil/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/yasyf/cc-vigil/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/yasyf/cc-vigil/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/yasyf/cc-vigil/releases/tag/v0.1.1
[0.1.0]: https://github.com/yasyf/cc-vigil/releases/tag/v0.1.0
