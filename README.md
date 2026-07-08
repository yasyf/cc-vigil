# ![cc-vigil](docs/assets/readme-banner.webp)

**Awake while agents work. Asleep the moment they stop.** cc-vigil keeps your Mac awake while Claude Code agents are truly working — a transcript-oracle sleep inhibitor with clamshell support.

[![CI](https://github.com/yasyf/cc-vigil/actions/workflows/ci.yml/badge.svg)](https://github.com/yasyf/cc-vigil/actions/workflows/ci.yml)
[![License: PolyForm-Noncommercial-1.0.0](https://img.shields.io/badge/License-PolyForm--Noncommercial--1.0.0-blue.svg)](https://github.com/yasyf/cc-vigil/blob/main/LICENSE)

---

## Use cases

### Walk away from an overnight agent run

A long Claude Code run dies the moment macOS decides you're idle — you come back to a sleeping Mac and a half-finished task. cc-vigil watches the session transcripts and holds a sleep assertion for exactly as long as an agent is doing real work.

### Stop babysitting `caffeinate`

A blanket `caffeinate` outlives the work it was started for; forget it once and the fans run all night. cc-vigil's oracle reads the transcripts themselves, so the assertion drops the moment the last agent goes idle — no timers to guess, nothing to remember to kill.

### Close the lid and keep working

Clamshell sleep ignores ordinary idle assertions — shutting a MacBook normally ends the run no matter what. cc-vigil's clamshell support keeps agents working with the lid closed, and releases the machine to sleep as soon as they finish.

## Get started

### Homebrew (coming soon)

```sh
brew install --cask cc-vigil  # not yet published
```

### Build from source

You need Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
git clone https://github.com/yasyf/cc-vigil.git
cd cc-vigil
xcodegen generate
xcodebuild -project CCVigil.xcodeproj -scheme CCVigil \
  -configuration Release -derivedDataPath build ONLY_ACTIVE_ARCH=YES build
cp -R build/Build/Products/Release/CCVigil.app /Applications/
open /Applications/CCVigil.app
```

The first run walks you through everything macOS requires:

1. **Background services** — CCVigil registers a per-user agent (the transcript oracle) and a root helper (the only process that touches power management). Approve both under System Settings → General → Login Items & Extensions when prompted.
2. **Claude Code hooks** — the installer adds tagged `cc-vigil nudge` hooks to `~/.claude/settings.json`. Your existing hooks are preserved untouched, and `cc-vigil uninstall-hooks` removes only the tagged entries.
3. **CLI on your PATH** — the bundled `cc-vigil` binary is symlinked into `/usr/local/bin` (or `~/.local/bin` when that isn't writable).

After that the eye in your menu bar fills whenever the Mac is held awake, and the menu names the sessions holding it.

## How it works

### Hooks say *when* to look, never *what is true*

The obvious design counts hooks: acquire a sleep hold on `UserPromptSubmit`, release it on `Stop`. [adrafinil](https://github.com/kageroumado/adrafinil) works that way, and its [issue #7](https://github.com/kageroumado/adrafinil/issues/7) shows the failure mode: an agent kicks off a background workflow, posts its "running in background" reply, `Stop` fires, the refcount hits zero — and the Mac sleeps while sub-agents are still streaming tokens. Hook events describe the conversation loop, not the work.

cc-vigil inverts the relationship. Hooks carry no idle semantics at all; every hook is a nudge meaning "re-read the transcripts now". The truth lives in the transcripts under `~/.claude/projects`, parsed by [cc-transcript](https://github.com/yasyf/cc-transcript): pending tool calls, background tasks, sub-agent trees, and waiting workflows are all visible there, whether or not any hook ever fires.

### The oracle

A session counts as active only if live `claude` processes exist and the transcript shows one of: an event inside the activity window, an unfinished tool call, or a wait on long-running work (background tasks, sub-agents, workflows). Two discounts keep that honest:

- **Human-wait hint** — a `Notification` hook newer than the last transcript event means the agent is waiting on *you*, so the session stops holding the Mac awake until you reply.
- **Max-age backstop** — pending async work whose transcript hasn't advanced in 12 hours (configurable) stops counting, with a loud log. This is a real case, not paranoia: a stopped workflow leaves "pending" entries in the transcript forever.

The oracle re-evaluates every 15 seconds while blocking, every 45 seconds while idle, and immediately on any nudge.

### Sleep mechanics

While the oracle says "working", cc-vigil holds a `PreventUserIdleSystemSleep` assertion and, because clamshell sleep ignores assertions, sets `pmset -a disablesleep 1` through a minimal root helper whose entire interface is set, get, and version. No policy runs as root.

Two invariants:

- **The display always sleeps normally.** cc-vigil never takes `PreventUserIdleDisplaySleep` and never runs `caffeinate`. The screen goes dark on schedule while the system stays up.
- **`disablesleep` never outlives the daemon.** It's a persistent machine-wide setting, so the helper force-clears it on boot, on shutdown signals, on a 60-second dead-man after the daemon disappears while blocked, and re-reconciles after every wake.

Cutouts protect the hardware: on battery below the floor, or lid-closed at high temperature, the block releases and latches off until conditions recover (with hysteresis, so it doesn't flap). Manual `cc-vigil hold` and `pause` override the oracle in either direction.

## Configuration

Config lives at `~/Library/Application Support/cc-vigil/config.json`. Missing keys take defaults, invalid values fail at startup, and the Settings window edits the same file.

| Key                        | Default | Range | Meaning                                                                                                              |
| -------------------------- | ------- | ----- | -------------------------------------------------------------------------------------------------------------------- |
| `batteryFloorPercent`      | `20`    | 5–50  | On battery below this charge, release the block and latch until charge reaches floor+5 or AC power returns.           |
| `thermalCutoutCelsius`     | `80`    | 70–95 | Lid closed, blocking, and at or above this temperature: release and latch until 5°C cooler or the lid opens.          |
| `activityWindowSeconds`    | `300`   | ≥1    | How recent a transcript event must be to keep a session active on its own.                                            |
| `pendingAsyncMaxAgeSeconds`| `43200` | ≥1    | Pending async work with no transcript advance for longer than this stops counting (the backstop above).               |
| `pollBlockingSeconds`      | `15`    | ≥1    | Oracle cadence while blocking.                                                                                         |
| `pollIdleSeconds`          | `45`    | ≥1    | Oracle cadence while idle.                                                                                             |
| `hideMenuBarExtra`         | `false` | —     | Hide the menu-bar icon; relaunch CCVigil.app to bring it back.                                                         |

## CLI reference

Durations are bare seconds or compound units such as `90`, `30m`, `1h30m`, and `1d`.

| Command                                             | What it does                                                                                     |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `cc-vigil status [--json]`                          | Blocking state, helper connectivity, active sessions with reasons, holds, cutouts, pause.         |
| `cc-vigil hold --for 2h --reason "big rebuild"`     | Keep the Mac awake regardless of the oracle (24h cap); prints the key to release. `--key` to name it. |
| `cc-vigil release <key>`                            | Release a hold.                                                                                   |
| `cc-vigil pause --for 30m` / `cc-vigil resume`      | Stop all blocking for a while / resume immediately.                                               |
| `cc-vigil log [-f] [-n N]`                          | Show `events.log` (block edges with oracle snapshots, cutouts, holds); `-f` follows across rotation. |
| `cc-vigil install-hooks` / `cc-vigil uninstall-hooks` | Add or remove the tagged hooks in `~/.claude/settings.json` (`--settings` for another file).     |
| `cc-vigil nudge`                                    | The hook entry point: reads hook JSON on stdin, always exits 0. Not for humans.                   |
| `cc-vigil version`                                  | Print the version.                                                                                |

Every block and unblock lands in `~/Library/Application Support/cc-vigil/events.log` as JSONL with the full oracle snapshot — per-session reasons for why the Mac was held awake or let go.

Licensed under [PolyForm-Noncommercial-1.0.0](LICENSE).
