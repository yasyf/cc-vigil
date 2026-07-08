# ![cc-vigil](docs/assets/readme-banner.webp)

**Awake while agents work. Asleep the moment they stop.** cc-vigil keeps your Mac awake while Claude Code agents are truly working — a transcript-oracle sleep inhibitor with clamshell support.

[![CI](https://github.com/yasyf/cc-vigil/actions/workflows/ci.yml/badge.svg)](https://github.com/yasyf/cc-vigil/actions/workflows/ci.yml)
[![License: PolyForm-Noncommercial-1.0.0](https://img.shields.io/badge/License-PolyForm--Noncommercial--1.0.0-blue.svg)](https://github.com/yasyf/cc-vigil/blob/main/LICENSE)

Status: pre-release — the menu-bar app, daemons, and CLI compile and run as skeletons; the transcript oracle and sleep assertions land next.

---

## Use cases

### Walk away from an overnight agent run

A long Claude Code run dies the moment macOS decides you're idle — you come back to a sleeping Mac and a half-finished task. cc-vigil watches the session transcripts and holds a sleep assertion for exactly as long as an agent is doing real work.

### Stop babysitting `caffeinate`

A blanket `caffeinate` outlives the work it was started for; forget it once and the fans run all night. cc-vigil's oracle reads the transcripts themselves, so the assertion drops the moment the last agent goes idle — no timers to guess, nothing to remember to kill.

### Close the lid and keep working

Clamshell sleep ignores ordinary idle assertions — shutting a MacBook normally ends the run no matter what. cc-vigil's clamshell support keeps agents working with the lid closed, and releases the machine to sleep as soon as they finish.

Licensed under [PolyForm-Noncommercial-1.0.0](LICENSE).
