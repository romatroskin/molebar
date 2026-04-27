---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: Launch
status: executing
stopped_at: Phase 1 context gathered
last_updated: "2026-04-27T21:48:33.538Z"
last_activity: 2026-04-27 -- Phase 1 execution started
progress:
  total_phases: 9
  completed_phases: 0
  total_plans: 7
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-27)

**Core value:** Full Mole feature parity in the menu bar — every capability of the Mole CLI must eventually be reachable from the MoleBar UI.
**Current focus:** Phase 1 — Distribution Foundations

## Current Position

Phase: 1 (Distribution Foundations) — EXECUTING
Plan: 1 of 7
Status: Executing Phase 1
Last activity: 2026-04-27 -- Phase 1 execution started

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: —
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**

- Last 5 plans: —
- Trend: — (no data yet)

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Phase ordering: Distribution-first (Phase 1) before features — three of the five P0 pitfalls live at the distribution layer and the Sparkle EdDSA key is unrotatable post-launch (research conflict #2 resolved).
- Subprocess wrapper: `Foundation.Process` actor-wrapped for v1 (with Phase 2 spike vs `jamf/Subprocess`); migrate to `swift-subprocess` post-1.0 in v1.x (research conflict #1 resolved).
- MenuBarExtra style: `.window` mandatory; thin-shell architecture so AppKit `NSStatusItem` swap is cheap if blockers surface (research conflict #3 resolved).
- Deletion primitive: `NSFileManager.trashItem` (not `rm`) for every destructive op — deletions executed in Swift using paths discovered via `mole --dry-run`, never `mole clean -y` directly (Pitfall #7 mitigation).

### Pending Todos

None yet.

### Blockers/Concerns

Spike items flagged for Phase 2 / Phase 6 / Phase 7 / Phase 8 (informational, not blocking):

- Phase 2: Subprocess wrapper benchmark vs `jamf/Subprocess`; verify `mole stats --json --watch` flag combination exists; produce notarization smoke-test for minimal entitlement set.
- Phase 6: Treemap rendering perf ceiling (Canvas-squarified vs YMTreeMap at 100k–1M entries); activation-policy juggle for window-open + popover-open simultaneity.
- Phase 7: `SMAppService.agent` registration UX flow on macOS 14 + 15; LaunchAgent EnvironmentVariables behavior with bundled-vs-system mole.
- Phase 8: End-to-end test that ad-hoc-signed CLI binaries pass Gatekeeper when invoked by a notarized parent.

## Deferred Items

Items acknowledged and carried forward — explicitly v2 / v1.x per PROJECT.md:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| v2 | Smart App Uninstall (UNINSTALL-01..03) | Deferred | Init |
| v2 | Full GUI window app (GUI-01, GUI-02) | Deferred | Init |
| v1.x | Polish (POL-01..06: live op-log streaming, process-watch alerts, Bluetooth battery, Touch ID, "recently freed" tally, localization) | Deferred | Init |

## Session Continuity

Last session: 2026-04-27T18:56:29.496Z
Stopped at: Phase 1 context gathered
Resume file: .planning/phases/01-distribution-foundations/01-CONTEXT.md
