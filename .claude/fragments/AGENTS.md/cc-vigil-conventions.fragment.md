## Style

**Comments are terse and used sparingly — the code documents itself** through names, types, and organization. The one exception is documentation-generation comments (the doc comments your language's doc tool renders for the public API); beyond those, comment only for TODOs, non-obvious workarounds, or disabled code — never to restate the signature.

@STYLEGUIDE.md

## General Rules

**Minimal changes.** Stay within scope; fix the issue, then stop.

**Match surrounding code.** Follow the conventions of the file you're in, then the module.

**No defensive coding.** No fallbacks, shims, or backwards-compat layers; no guards against impossible states. If unused, delete it. Crash on the unexpected.

**Search before writing.** Before creating a helper, query the codebase via `ccx search` (intent) or `ccx symbol` (a named symbol). Sibling modules and base classes win over re-implementation.

**Code stewardship.** When you touch a file, fix nearby bugs, style violations, and broken tests; don't wave them off as pre-existing or out of scope.

**Observe, don't infer.** Inspect actual data — read fixtures, dump objects, run the code — before reasoning from assumption.

**Don't use external failures as an excuse to stop.** API quota, rate-limit, and outage errors rarely block the whole task; trace the catch sites and confirm a failure actually stops you before claiming it does.

**Verify before asserting.** Don't report something as working, fixed, blocked, or impossible until you've checked — run it, read the output, reproduce the failure. "It should work" is not "it works."

**Reproduce before fixing.** When something breaks, isolate the smallest failing case before editing or re-running. Re-running the whole command while changing code between runs hides the root cause; narrow to the one failing call, payload, or test first.

**Research after repeated failure.** After ~2 failed approaches, stop guessing and gather evidence — search the web, read the docs and source — before a third attempt.

**Get a second opinion on a plateau.** On a debugging plateau (2 failed attempts before a 3rd), a non-trivial architectural decision, or algorithmic/security-sensitive code, get an outside check (e.g. `/codex`) before committing to the approach.

**Don't contort code to satisfy a checker.** The type checker and linter serve the code, not the other way around. Don't reshape a data model, widen a type, or bolt on a `cast(...)` / narrowing-only `assert isinstance(...)` / blanket ignore just to silence a diagnostic. If a clean fix isn't obvious, leave the diagnostic — a visible diagnostic is preferable to scar tissue. (Most checker noise isn't worth acting on at all; act only when it flags a real bug.)

**Mechanical linting.** Running `swiftformat .`/`swiftlint` by hand is fine, and encouraged — the pre-commit hooks (prek: swiftformat + swiftlint, calling the brew-installed binaries) also run on every `git commit`; run `uvx prek install` once to activate them. Fix what needs human judgment and let the tooling own the mechanical churn. When reviewing code, don't flag mechanical lint violations (whitespace, ordering, line length).

**Build & run.** `xcodegen generate` emits `CCVigil.xcodeproj` from `project.yml`; build with `xcodebuild -project CCVigil.xcodeproj -scheme CCVigil build`. The CCVigil scheme builds the daemon, helper, and CLI too and embeds them in the app bundle (`Contents/Library/LaunchAgents`, `Contents/Library/LaunchDaemons`, `Contents/Helpers`).

**Testing.** Tests live in `CCVigilShared/Tests/` and use Swift Testing — free `@Test` functions with `#expect`/`#require` against specific expected values, parameterized via `@Test(arguments:)`. Run them with `swift test --package-path CCVigilShared`. Mock the boundaries the code talks to (filesystem, clock, power APIs) and leave the function under test real. Tests never touch the real machine: never write `~/.claude/settings.json`, never register launchd services, never run `pmset` or take IOPM assertions for real — that coverage lives on the manual release checklist. Reading `~/.claude/projects` read-only is allowed. The `DaemonRoundTripTests` integration suite drives the xcodebuild Debug products (`-derivedDataPath build`) and skips visibly when they haven't been built. For headless end-to-end runs, `CC_VIGIL_FAKE_BATTERY_FILE=<path>` makes the daemon poll that file (one line, `battery <percent>` or `ac <percent>`) in place of IOPS so the battery cutout can be driven by hand; the daemon logs loudly when the seam is active.

**XcodeBuildMCP.** If using XcodeBuildMCP, use the installed `xcodebuildmcp-cli` skill before calling XcodeBuildMCP tools.

**Writing docs.** When writing or revising docs, a README, a tutorial, a how-to, or reference, use the `writing-docs` skill (Diataxis modes, voice rules, and runnable code-sample rules) and run `slop-cop check <file> --lang=markdown` before you finish (slop-cop is a Go binary; if it's not on PATH, run the `/slop-cop-check` skill — never `uvx slop-cop`).

**Version control.** This repo is a colocated `jj` repo over git — prefer `jj` (`jj describe` / `jj commit`, `jj git push`) over raw `git` for day-to-day work. Commits stay atomic and scoped: one logical change each. A dirty tree is just the working-copy commit `@` — to land work on an updated remote, `jj git fetch` then `jj rebase` (your in-flight `@` rides along untouched); never `git stash` or a worktree + cherry-pick dance.

**Watch CI after every push.** A push that kicks off CI isn't done until the run is green. After `jj git push` (or `git push`), watch the run to completion before you stop — `gh run watch "$(gh run list -L1 --json databaseId -q '.[0].databaseId')" --exit-status` — and never walk away from a red run: fix it or report it. (`--exit-status` exits non-zero when the run fails; give the run a moment to register before watching.)
