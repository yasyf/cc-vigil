# cc-vigil Development Guide

Keeps your Mac awake while Claude Code agents are truly working — a transcript-oracle sleep inhibitor with clamshell support. cc-vigil is a Swift macOS menu-bar app plus daemons: it reads Claude Code transcripts to decide whether agents are actually working, and holds a sleep assertion (clamshell included) only while they are. The Xcode project is generated: `xcodegen generate` emits `CCVigil.xcodeproj` from `project.yml`, the source of truth — edit the spec, never the project.

## Repository Structure

```
cc-vigil/
├── .github/workflows/  # CI — swiftformat/swiftlint + xcodebuild build + swift test on macos-26
├── .claude/            # Claude Code config — settings, guard-hook packs, jj config, skills
├── docs/               # Brand assets (mascot, banner, social card)
├── project.yml         # XcodeGen spec — source of truth for CCVigil.xcodeproj (generated, gitignored)
├── Generated/          # XcodeGen-emitted Info.plists (gitignored)
├── Sources/
│   ├── App/            # CCVigil — SwiftUI menu-bar app (LSUIElement, MenuBarExtra), installer, XPC client
│   ├── Daemon/         # CCVigilDaemon — LaunchAgent; oracle loop, power monitors, cli.sock server
│   ├── Helper/         # CCVigilHelper — root LaunchDaemon; IOPM assertion + pmset edges, XPC auth
│   └── CLI/            # cc-vigil — thin @main over CCVigilCLIKit, embedded at Contents/Helpers
├── Resources/          # launchd plists copied into the app bundle next to their binaries
├── CCVigilShared/      # local SPM package all four targets depend on
│   ├── Sources/
│   │   ├── CCVigilShared/    # pure policy core — oracle state, block policy, cutouts, holds, wire, hook installer
│   │   ├── CCVigilDaemonKit/ # daemon adapters — cc-transcript FFI (the pin lives in Package.swift), scanner, event log, state, support paths
│   │   ├── CCVigilCLIKit/    # CLI subcommands, socket client, renderers
│   │   └── CCVigilAppKit/    # app policy — status view model, installer state machine, away digest
│   └── Tests/          # one Swift Testing target per library, fixtures included
├── AGENTS.md           # This file — shared conventions
├── CLAUDE.md           # Claude-only rules; embeds AGENTS.md
├── STYLEGUIDE.md       # Concrete style rules
├── README.md           # Project overview
└── CHANGELOG.md        # Keep a Changelog history
```

## Ask Before Assuming

When the user's request has ambiguity — unclear scope, multiple plausible interpretations, undefined edge cases, or unspecified tradeoffs — stop and ask. Propose 2-4 concrete options and let the user pick, or list the assumptions you'd otherwise make and ask which ones hold. There is no such thing as too many questions; one wrong implementation costs more than ten clarifying exchanges. Default to interrogating the user when in doubt — multiple short questions early beat a wrong direction later.

## Code Review Response (Plan Re-Entry)

When the user reviews code you wrote and re-enters plan mode — whether by leaving inline diff comments, pasting a numbered list of issues, or otherwise sending review-shaped feedback after a recent edit cycle — you MUST:

0. **Delegate context-gathering to a subagent.** Spawn one `Explore` subagent with every cite (file:line + the user's verbatim comment text). Instruct it to, per cite, `Grep` the file with ~5 lines of context either side of the cited line (`-B 5 -A 5`), and only escalate to a full `Read` when the ±5-line window is insufficient (e.g. the comment refers to a function defined further up). Have it also surface sibling call sites with the same issue (Grep across the module). Use the subagent's digest as your source of truth when drafting the plan. Do NOT bulk-`Read` the cited files yourself in the main turn — it bloats the main context window before you've even started writing the plan.
1. **Draft a new plan**, not a code change. Plan-mode re-entry is the user asking "let's align on what you'll do next," not "go fix it."
2. **Inline every comment verbatim** in the plan. Each comment gets a short anchor (`#N`, the file:line if provided, or a quoted excerpt) plus the user's exact wording in a blockquote or `*"…"*` italics. Do not paraphrase. The user must be able to scan the plan and see every comment they wrote reproduced exactly.
3. **Cluster when many.** If there are more than ~5 comments, group them into themes (e.g. "T1 — Guards against impossible states") and list every verbatim trigger per theme. Address every cited line *and* extrapolate the rule to other call sites that have the same problem.
4. **Map every comment.** Maintain a "verbatim feedback table" near the end of the plan with one row per comment: `# | file:line | verbatim | cluster`. No comment may be silently dropped.
5. **Do NOT start implementing** before the plan is approved via `ExitPlanMode`. Delegating reads via #0 is fine; editing source is not.

The canonical shape is the `Overarching themes` table + per-cluster `**#N (verbatim):** *"…"*` anchors + final mapping table. When a comment is ambiguous, ask via `AskUserQuestion` rather than guessing.

### Plan follow-up questions

After you write a plan, the user may respond with questions ("why this approach?", "what about X?", "did you consider Y?") rather than approval. In that case you MUST NOT edit the plan to bake in answers. Instead:

1. **Answer the question conversationally** in your text response — explain the reasoning, the tradeoffs, and what you'd recommend.
2. **Propose options via `AskUserQuestion`** — one question per ambiguity, each with 2–4 concrete options the user can pick from. Batch related questions into one `AskUserQuestion` call.
3. **Wait for the user's choice** before editing the plan. The plan edit then reflects the user's pick, not your assumption.

Editing the plan first robs the user of the choice and forces them to diff the plan to find what you decided. Surface the decision point first.

## Parallelize Independent Work

Sequential is the exception, not the default. Two steps that don't consume each other's output run at the same time; when unsure whether they're independent, assume they are and fan out. The orchestrator routes and synthesizes — it never executes work a subagent could. Pick the surface by scale:

- **Batch tool calls in one message** — the cheapest parallelism and the most missed. Independent reads, greps, globs, and read-only Bash go in a *single* message, never one per turn.
- **Parallel subagent calls in one message** — ad-hoc independent investigations: "explore X while I check Y", multi-file reviews, independent edits. One message, N `Agent` tool uses, results gathered in parallel.
- **Dynamic workflow** — default for substantive multi-step work; the script holds the loop, branching, and intermediate results. See CLAUDE.md `## Plan Execution & Orchestration`.
- **Named team** — long-running peers needing agent-to-agent handoffs mid-run, via `TeamCreate`.

Single-step exception: one task, no parallel sibling, no follow-on → one subagent call is fine.

## Writing Plans

When you write a plan — in plan mode, or any "here's what I'll do" before you start editing — use this shape so it's fast to scan and complete enough to execute:

- **Context** — why this change: the problem or need, what prompted it, the intended outcome.
- **Approach** — the recommended approach only (not every alternative you weighed), as ordered steps. Name the critical files to touch; for a pattern repeated across many files, describe it once with a few representative paths instead of listing them all. Cite existing utilities/patterns you'll reuse, with their paths.
- **Potential Pitfalls** — the sharp edges specific to this work: ordering constraints, code that looks safe to change but isn't, prior art that must not be "fixed", state that diverges from how it's described. One bullet each — front-load the gotchas you'd otherwise hit mid-implementation.
- **Workflow Plan** — required in every plan; a plan without it is incomplete. One line on what the main agent alone does (track state, dispatch, decide, report), then a `Phase | Shape | Agents | Verification` table covering every fan-out the plan anticipates: Shape is `pipeline` / `parallel` / `loop`; Agents names each phase's model and effort per the Models table (e.g. `opus xhigh ×4`, `sonnet low → codex`); Verification names the check that gates each phase's output. When nothing fans out, one line saying everything stays at the main-agent level replaces the table.
- **Verification** — how to prove it works end to end: the exact commands to run, tests to add, and behavior to observe.

## Compact Context (ccx)

`cc-context` — the `ccx` CLI and the `cc-context` MCP (its `mcp__cc-context__*` tools mirror the CLI 1:1) — is the DEFAULT for reading code, finding symbols, searching, and reviewing diffs. It returns token-bounded output (signatures + line numbers, explicit overflow, never silent truncation) instead of raw dumps, and the capt-hook `ccx` guard pack BLOCKS the token-heavy primitives — so reach for ccx first.

1. **Orient a repo** → `ccx overview`
2. **"How does X work / where is Y" (intent)** → `ccx search "<question>"` (semantic, semble-backed)
3. **A specific symbol (def + callers + callees)** → `ccx symbol <name>` (alias `ccx grok`)
4. **Literal / structural text** → `ccx grep <text> [--glob G]`
5. **List files** → `ccx find "<glob>"`
6. **Read a file** → `ccx outline <file>` first, then `ccx read <file> --section A-B` for the part you need (whole file: `ccx read <file> --full`)
7. **Review changes** → `ccx diff [src]` (structural, jj-aware; exact hunks: `git diff -- <file>`)

Reach for your **LSP** when the answer must be exhaustive/structural (findReferences, rename, goToImplementation). Use **Grep/Glob** only for literal content in non-source files (logs, JSON, YAML).

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
