# Manual E2E Checklist

The drills headless testing cannot cover: real SMAppService approvals, real
`pmset`/IOPM state, the lid, the battery, the display, launchd recovery, and
the real `~/.claude/settings.json`. Run them in order on real hardware after a
release build. Every step is action → expected observation → verify command.

Escape hatch at any point: `sudo pmset -a disablesleep 0` restores normal
sleep by hand.

## Prerequisites

- Apple Silicon Mac on macOS 14+, admin account, AC adapter within reach.
- Battery charged between 20% and 45% before starting drill 7 (the floor
  trick needs the charge below the maximum floor of 50).
- Two spare terminals for watchers you keep open through every drill:

```sh
# Terminal A: the event log, live
cc-vigil log -f

# Terminal B: the two power facts every drill asserts on
while true; do
  date "+%T  $(pmset -g assertions | grep -c 'cc-vigil: agents active') assertion(s)  $(pmset -g | grep SleepDisabled | xargs)"
  sleep 5
done
```

Daemon and helper logs, when a drill asks for them:

```sh
log stream --predicate 'subsystem == "dev.yasyf.cc-vigil"' --level info
```

## 1. First-run install and approvals

**Action.** Build and install per the README, then launch:

```sh
xcodegen generate
xcodebuild -project CCVigil.xcodeproj -scheme CCVigil \
  -configuration Release -derivedDataPath build ONLY_ACTIVE_ARCH=YES build
cp -R build/Build/Products/Release/CCVigil.app /Applications/
open /Applications/CCVigil.app
```

**Expect.** The installer window walks through registration. macOS prompts for
background items; System Settings → General → Login Items & Extensions lists
CCVigil with both services toggled on. After approval the eye appears in the
menu bar (outline while idle).

**Verify.**

```sh
launchctl print "gui/$(id -u)/dev.yasyf.cc-vigil.daemon" | grep -E "state|pid"
sudo launchctl print system/dev.yasyf.cc-vigil.helper | grep -E "state|pid"
cc-vigil status                      # helper reachable, no active sessions
readlink "$(which cc-vigil)"         # points into /Applications/CCVigil.app
grep -c _cc_vigil ~/.claude/settings.json   # 4 (UserPromptSubmit, Stop, SubagentStop, Notification)
```

## 2. Idle baseline

**Action.** Quit every `claude` process; wait one idle poll (45 s).

**Expect.** No block: Terminal B shows `0 assertion(s)` and `SleepDisabled 0`.

**Verify.**

```sh
cc-vigil status          # no active sessions, no holds, no cutouts
pmset -g assertions | grep cc-vigil   # no output
```

## 3. The issue-#7 drill: background work outlives Stop

The failure mode cc-vigil exists to fix
([adrafinil #7](https://github.com/kageroumado/adrafinil/issues/7)): hook
refcounts release the moment `Stop` fires, while background work is still
running.

**Action.** In any project, start `claude` and send exactly:

> Run this exact command with the Bash tool with run_in_background set to
> true: `sleep 300 && echo done`. The moment it launches, tell me it is
> running and end your turn. Do not wait for it or poll it.

**Expect, step by step.**

1. While the turn runs: session active, block held (assertion + SleepDisabled 1).
2. The moment the "it is running" reply lands, `Stop` fires. This is the
   instant a hook-refcount design would release. cc-vigil must still hold:
   within 15 s,
   `cc-vigil status` lists the session with reason `waiting` and Terminal B
   still shows 1 assertion, SleepDisabled 1. This is the drill's core check.
3. Keep your hands off. About 60 s after the reply, Claude Code fires the
   idle `Notification` hook ("Claude is waiting for your input"). Terminal A
   logs the block release with a `human-wait-hint` discount for the session,
   and Terminal B drops to 0 assertions, SleepDisabled 0. This release is by
   design: nothing advanced the transcript, and the harness itself reported
   the agent as waiting on you. If your setup never fires idle
   notifications, the block instead persists while the item pends; note
   which behavior you saw.
4. Type any prompt (`status?`). `UserPromptSubmit` clears the hint: the block
   returns within seconds while the new turn runs.
5. Exit `claude` entirely. Process gate: within one idle poll (45 s)
   everything idles regardless of the still-pending background item.

**Verify.** `cc-vigil log -n 30` shows the block/unblock edges, each carrying
the oracle snapshot with the session path and per-session reasons
(`waiting`, then the `human-wait-hint` discount).

**Full-fidelity variant.** Repeat with real streaming work — a prompt that
spawns subagents or a workflow ("launch a subagent to summarize every file
under src/, reply immediately, end your turn"). Because subagent events keep
advancing the transcript, the hold must persist past the 60 s notification
(reasons include `recent-activity`) and release only after the work finishes
plus the 5-minute activity window, or as soon as `claude` exits.

**Stale-activity backstop.** A mid-tool or waiting session whose transcript has
not advanced in over `pendingAsyncMaxAgeSeconds` (~12 h) is treated as idle even
though it is mid-tool/waiting: the oracle discounts it and Terminal A logs
`stale-activity max-age backstop discounted` naming the session. The live-process
gate, not the age, is the real-work signal — this backstop only aligns the oracle
with discovery's mtime window so both express one idle policy. The 12 h horizon
makes it impractical to drill by hand.

## 4. Display still sleeps

The display must go dark on schedule while the system stays up: cc-vigil
never takes `PreventUserIdleDisplaySleep`.

**Action.**

```sh
pmset -g | grep displaysleep          # note the current value to restore
sudo pmset -a displaysleep 1
cc-vigil hold --for 20m --reason display-drill
```

Start a heartbeat you will reuse in the lid drill:

```sh
nohup sh -c 'while true; do date +%s >> /tmp/cc-vigil-heartbeat.txt; sleep 5; done' >/dev/null 2>&1 &
```

Confirm the assertion before going hands-off:

```sh
pmset -g assertions | grep -B1 -A1 "cc-vigil: agents active"   # PreventUserIdleSystemSleep only
pmset -g assertions | grep "PreventUserIdleDisplaySleep"        # summary count 0, no cc-vigil row
```

Leave the Mac untouched for 3 minutes.

**Expect.** The display sleeps after ~1 minute. The system does not: the
heartbeat has no gap.

**Verify.** Wake the display, then:

```sh
awk 'NR>1 && $1-prev>15 {print "GAP", prev, $1} {prev=$1}' /tmp/cc-vigil-heartbeat.txt   # no output
sudo pmset -a displaysleep <original value>
```

Keep the hold and heartbeat for the next drill.

## 5. Lid-close clamshell

**Action.** On AC, hold still active from drill 4, SleepDisabled 1 in
Terminal B. Close the lid for 3 minutes, then reopen.

**Expect.** The machine never slept: no heartbeat gap across the closed-lid
window. Terminal A logged `lid closed` / `lid opened` events.

**Verify.**

```sh
awk 'NR>1 && $1-prev>15 {print "GAP", prev, $1} {prev=$1}' /tmp/cc-vigil-heartbeat.txt   # still no output
```

**Counter-check.** Release the hold, confirm SleepDisabled 0, close the lid
for 2 minutes, reopen:

```sh
cc-vigil release display-drill   # or the key `hold` printed
```

The heartbeat now shows exactly one GAP spanning the closed-lid window: the
Mac slept normally once released. Kill the heartbeat loop afterwards.

## 6. Config fail-fast: the floor-at-99 check

**Action.** Set an out-of-range battery floor and restart the daemon:

```sh
cd ~/Library/Application\ Support/cc-vigil
jq '.batteryFloorPercent = 99' config.json > c.tmp && mv c.tmp config.json
launchctl kickstart -k "gui/$(id -u)/dev.yasyf.cc-vigil.daemon"
```

**Expect.** The daemon refuses to start (fail fast: `batteryFloorPercent`
allows 5-50) and launchd keeps retrying.

**Verify.**

```sh
log show --last 2m --predicate 'subsystem == "dev.yasyf.cc-vigil"' | grep -i outOfRange
cc-vigil status   # daemon unreachable
```

Leave the config invalid; drill 7 fixes it.

## 7. Battery-floor cutout

Validation caps the floor at 50, so the trick is a floor of 50 with the
charge below it (hence the <45% prerequisite).

**Action.**

```sh
cd ~/Library/Application\ Support/cc-vigil
jq '.batteryFloorPercent = 50' config.json > c.tmp && mv c.tmp config.json
launchctl kickstart -k "gui/$(id -u)/dev.yasyf.cc-vigil.daemon"
cc-vigil hold --for 30m --reason battery-drill   # on AC: block applies
```

Unplug the AC adapter.

**Expect.** Within a few seconds (power-source change nudges the daemon):
Terminal A logs `cutout latched: battery`, the block releases (0 assertions,
SleepDisabled 0), and the hold remains listed but cannot re-acquire while
latched.

**Verify.**

```sh
cc-vigil status --json | jq '{shouldBlock, blockApplied, latchedCutouts, holds: [.holds[].key]}'
# shouldBlock false, blockApplied false, latchedCutouts ["battery"], hold still present
```

Plug AC back in.

**Expect.** `cutout cleared: battery` within seconds; the block re-applies
(hysteresis clears on AC without waiting for floor+5 charge).

**Cleanup.**

```sh
cc-vigil release battery-drill
cd ~/Library/Application\ Support/cc-vigil
jq '.batteryFloorPercent = 20' config.json > c.tmp && mv c.tmp config.json
launchctl kickstart -k "gui/$(id -u)/dev.yasyf.cc-vigil.daemon"
```

## 8. Crash drills

Run each with a block held: `cc-vigil hold --for 30m --reason crash-drill`.

### 8a. kill -9 the helper

**Action.**

```sh
sudo launchctl print system/dev.yasyf.cc-vigil.helper | grep pid
sudo kill -9 <pid>
```

**Expect.** The assertion vanishes instantly (the kernel drops a dead
process's assertions). launchd restarts the helper within seconds
(KeepAlive); its init force-clear briefly shows SleepDisabled 0; the daemon's
XPC interruption handler forces a re-push. Total outage: seconds, never more
than one blocking poll (15 s).

**Verify.** Terminal B returns to `1 assertion(s)` and `SleepDisabled 1`
within ~15 s. Helper log shows `init force-clear`.

### 8b. kill -9 the daemon

**Action.**

```sh
launchctl print "gui/$(id -u)/dev.yasyf.cc-vigil.daemon" | grep pid
kill -9 <pid>
```

**Expect.** The block never drops: the helper holds the assertion and pmset
state, arms its 60 s dead-man on the connection drop, and the relaunched
daemon (KeepAlive, seconds) reconnects and re-pushes long before it fires.
The hold survives the restart (state.json, same boot). Terminal B shows no
flap at all.

**Verify.** `cc-vigil status` after ~10 s: hold present, block applied.
Helper log shows `dead-man armed` with no `dead-man fired`.

### 8c. Dead-man: daemon gone for good

**Action.** Disable first so launchd cannot resurrect it:

```sh
launchctl disable "gui/$(id -u)/dev.yasyf.cc-vigil.daemon"
launchctl kill SIGKILL "gui/$(id -u)/dev.yasyf.cc-vigil.daemon"
```

**Expect.** For ~60 s the block persists (helper still holds it). At the 60 s
dead-man grace, the helper force-clears: 0 assertions, SleepDisabled 0.
Helper log: `dead-man armed …`, then `dead-man fired: no daemon reconnected
within 60.0s; force-clearing`, then `dead-man clear confirmed`. The clear is
self-healing: if `pmset` does not confirm, the helper logs `dead-man clear
unconfirmed, retrying …` and re-attempts every 5 s until it confirms, so a
failed clear is never terminal (a reconnect cancels the pending retries).

**Verify and recover.**

```sh
launchctl enable "gui/$(id -u)/dev.yasyf.cc-vigil.daemon"
launchctl kickstart "gui/$(id -u)/dev.yasyf.cc-vigil.daemon"
cc-vigil status   # reachable again; hold restored; block re-applies
```

### 8d. Graceful SIGTERM

**Action.**

```sh
launchctl kill SIGTERM "gui/$(id -u)/dev.yasyf.cc-vigil.daemon"
```

**Expect.** Bounded cleanup (8 s cap): the daemon pushes clear before
exiting — SleepDisabled 0 and 0 assertions almost immediately, a
`daemon-stopped` event in Terminal A. KeepAlive restarts it; the block
returns within one poll because the hold is still active.

**Cleanup.** `cc-vigil release crash-drill`.

## 9. Hook idempotence on the real settings file

**Action.**

```sh
cp ~/.claude/settings.json /tmp/settings-before.json
cc-vigil install-hooks
diff ~/.claude/settings.json /tmp/settings-before.json && echo IDENTICAL
cc-vigil install-hooks
diff ~/.claude/settings.json /tmp/settings-before.json && echo STILL-IDENTICAL
```

**Expect.** Both diffs are empty: installing over an installed file is a
no-op.

**Then.**

```sh
cc-vigil uninstall-hooks
grep -c _cc_vigil ~/.claude/settings.json    # 0
```

Spot-check that your own hooks survived verbatim (open the file and compare
against `/tmp/settings-before.json` minus the tagged entries). Reinstall:

```sh
cc-vigil install-hooks
grep -c _cc_vigil ~/.claude/settings.json    # 4
```

## 10. Uninstall

**Action.** Menu bar eye → Settings → Uninstall… → confirm.

**Expect.** The maintenance log in the window reports hooks removed, both
services unregistered, and the CLI symlink removed.

**Verify.**

```sh
grep -c _cc_vigil ~/.claude/settings.json                        # 0
launchctl print "gui/$(id -u)/dev.yasyf.cc-vigil.daemon"         # could not find service
sudo launchctl print system/dev.yasyf.cc-vigil.helper            # could not find service
which cc-vigil                                                   # nothing
pmset -g | grep SleepDisabled                                    # 0
pmset -g assertions | grep cc-vigil                              # nothing
```

System Settings → Login Items & Extensions no longer lists CCVigil. Quit the
app and move it to the Trash.
