---
phase: 2
phase_name: CLI Orchestration Core
date: "2026-04-28"
discuss_mode: discuss
---

# Phase 2 Discussion Log

Audit/retrospective record of the discussion that produced `02-CONTEXT.md`. Not consumed by downstream agents.

## Setup

- Phase 2 directory created during this session (no prior `02-CONTEXT.md`).
- No SPEC.md, no checkpoint, no pending todos matched.
- Prior context loaded: PROJECT.md (CLAUDE.md), REQUIREMENTS.md (CORE-01..08, OSS-02), ROADMAP.md (Phase 2 success criteria + dependency on Phase 1), STATE.md (Phase 1 status + Phase 2 spike concerns), Phase 1's 18 D-decisions (D-01..D-18 + D-14 amendment), Phase 1 plan summaries (esp. 01-02 for Swift 6 concurrency lesson, 01-03 for A9 absolute-path observations, 01-04 for SUPublicEDKey + Sparkle wiring carry).
- Codebase scouted: `Packages/MoleBarPackage/` empty 3-module workspace ready; `MoleBarCore/Placeholder.swift` is the deletable seed.

## Gray areas surfaced

Presented 4 implementation gray areas to user; user selected ALL 4.

## Discussion turns

### Area 1 — MoleClient API surface + MoleEvent shape

**Q:** How should MoleClient's public API be shaped?
**Options:**
- Per-subcommand methods, typed streams (each method returns the right shape)
- Generic `run(MoleCommand)` + `MoleEvent` enum (single dispatch, caller switches)
- Hybrid (generic core + typed wrappers)

**Selected:** Per-subcommand methods, typed streams — `streamStats() -> AsyncThrowingStream<StatsSnapshot>`, `runClean(dryRun:) async throws -> CleanReport`, `runVersion()`, etc. No public `MoleEvent` unifying enum.

**Rationale:** type safety at every call site outweighs API-surface growth. Locked as D-19.

### Area 2 — Schema drift + decode error model (3 sub-questions, batched)

**Q1:** How should CORE-03 versioned Codable models work?
**Options:**
- Pinned-version types per supported Mole version
- Single forward-compatible types + lenient decoding (Recommended)
- Schema-fingerprint validation

**Selected:** Single forward-compatible types with optional fields + `extra: [String: AnyCodable]` catch-all. Locked as D-20.

**Q2:** What should CORE-07's nightly upstream-drift CI do on detected drift?
**Options:**
- Fail nightly + auto-open GitHub issue (Recommended)
- Fail nightly, no auto-issue
- Auto-open PR with regenerated fixtures + bumped mole-version.txt

**Selected:** Fail loudly + auto-open issue with payload + diff. Locked as D-21.

**Q3:** How granular should the typed MoleError hierarchy be?
**Options:**
- Flat enum with associated values (Recommended)
- Struct + nested Kind enum + context dict
- Per-method error types

**Selected:** Flat enum with 6 cases. Locked as D-22.

### Area 3 — Cancellation semantics + process-group safety (3 sub-questions, batched)

**Q1:** SIGTERM grace period before SIGKILL?
**Options:** 250 ms (Recommended) / 1000 ms / 500 ms

**Selected:** 250 ms. Gives 4× headroom under success-criterion #1's 1-second cap. Locked as D-23.

**Q2:** What does an in-flight stream emit when consumer Task is cancelled?
**Options:**
- Throw `MoleError.cancelled`, then `finish()` (Recommended)
- Silent `finish()` (no error)
- Throw `MoleError.processFailed(SIGTERM, ...)`

**Selected:** Throw `MoleError.cancelled` then `finish()`. Symmetrical with one-shot async-throws methods. Locked as D-24.

**Q3:** Process-group cleanup strategy?
**Options:**
- `setpgid` in child + signal `-PID` for whole group (Recommended)
- Plain `Process.terminate()` (SIGTERM to PID only)

**Selected:** `setpgid` + signal `-PID`. Catches grandchildren (Go helpers). Locked as D-25.

### Area 4 — Network-traffic invariant verification (OSS-02)

**Q:** How to PROVE zero outbound traffic?
**Options:**
- Build-time import ban + runtime XCTest (Recommended)
- Runtime XCTest only
- Build-time grep only
- Manual Little Snitch + checklist

**Selected:** Two-layer (build-time grep + runtime XCTest with URLProtocol intercept + NWPathMonitor). Locked as D-26.

## Items Claude decided (low-impact, not asked)

- **LICENSE-MOLE.txt sourcing:** static commit at `MoleBar/Resources/LICENSE-MOLE.txt`, refreshed on `mole-version.txt` bump. Locked as D-27. Auditable in git, low-maintenance.
- **AnyCodable implementation:** hand-rolled (~30 LOC) — keeps zero third-party deps in MoleBarCore. Researcher may propose a maintained snippet if cleaner.
- **Subprocess wrapper spike (jamf/Subprocess vs Foundation.Process):** STATE.md "Blockers/Concerns" listed this. Rejected as deferred — PROJECT.md already commits to Foundation.Process; spike was informational only. If perf issues surface in Phase 5+, revisit with measured data.

## Deferred items captured

(See `<deferred>` section in `02-CONTEXT.md`.)

## Research dependencies surfaced

5 items the researcher must verify (`mole stats --watch` flag, Foundation.Process processGroupID API, Mole's env-var support, AnyCodable choice, Phase 2 streaming-subcommand scope). Captured under `<research_dependencies>` in CONTEXT.md.

## Outcome

`02-CONTEXT.md` written with 9 D-decisions (D-19 through D-27) + carried-forward decisions from Phase 1. Ready for `/gsd-plan-phase 2` (research-then-plan). User next-step is `/clear && /gsd-plan-phase 2`.
