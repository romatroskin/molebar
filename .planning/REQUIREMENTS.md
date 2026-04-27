# Requirements: MoleBar

**Defined:** 2026-04-27
**Core Value:** Full Mole feature parity in the menu bar — every capability of the Mole CLI must eventually be reachable from the MoleBar UI.

## v1 Requirements

Initial public release. Each requirement maps to exactly one roadmap phase.

### Distribution & Release Pipeline

- [ ] **DIST-01**: App is signed with the project's Apple Developer ID (Application certificate) using `--options runtime --timestamp`
- [ ] **DIST-02**: App is notarized via `xcrun notarytool` and the notarization ticket is stapled with `xcrun stapler`
- [ ] **DIST-03**: Bundled `mole` binary lives at `Contents/Helpers/mole` and is re-signed with hardened runtime independently of the .app
- [ ] **DIST-04**: A signed/notarized `.dmg` is produced via `create-dmg` for every release
- [ ] **DIST-05**: GitHub Actions workflow builds, signs, notarizes, staples, packages, and uploads release artifacts on tag push
- [ ] **DIST-06**: Sparkle 2.x in-app updater fetches a signed appcast from a project-controlled URL with EdDSA verification
- [ ] **DIST-07**: Homebrew Cask formula is published and bumped automatically on each release (`auto_updates true`)
- [ ] **DIST-08**: A round-trip 0.0.1 → 0.0.2 update succeeds end-to-end before any feature ships (Sparkle smoke test)

### CLI Orchestration Core

- [ ] **CORE-01**: `actor MoleClient` is the only place subprocesses are spawned in the codebase
- [ ] **CORE-02**: `MoleClient` exposes `AsyncThrowingStream<MoleEvent, Error>` for streaming subcommands and `async throws` for one-shot subcommands
- [ ] **CORE-03**: All Mole JSON output is decoded into versioned Codable models with explicit failure modes (corrupt JSON ≠ silent loss)
- [ ] **CORE-04**: `mole` subprocess is launched from `Contents/Helpers/mole` (or `~/Library/Application Support/MoleBar/bin/mole` after binary auto-update) with explicit PATH/HOME so user shell config can't poison it
- [ ] **CORE-05**: Subprocesses are cancellable via `Task.cancel()`; cancellation propagates to child via `SIGTERM`, then `SIGKILL` after timeout — no zombie children
- [ ] **CORE-06**: All stdout/stderr pipes are drained asynchronously (no synchronous reads) — verified by 10-concurrent-invocation stress test
- [ ] **CORE-07**: A nightly CI job runs MoleBar's test suite against the latest upstream `tw93/mole` `main` to surface JSON schema drift early
- [ ] **CORE-08**: License attribution file `LICENSE-MOLE.txt` ships in `Contents/Resources/`

### Permissions & Onboarding

- [ ] **PERM-01**: First-run window guides the user through granting Full Disk Access with a deep link to System Settings
- [ ] **PERM-02**: App detects FDA grant state on every launch and on `NSWorkspace.didActivate` (FDA can be revoked); UI reflects state
- [ ] **PERM-03**: When FDA is denied, destructive actions are disabled with an inline "Grant access" CTA (the app does NOT crash or silently fail)
- [ ] **PERM-04**: After FDA grant, the app re-launches itself to inherit the new TCC permissions
- [ ] **PERM-05**: Onboarding shows what MoleBar will and will not do, and links to the open-source repo and operation log path as trust signals

### Live System Monitoring

- [ ] **MON-01**: Live menu-bar metrics stream from a single long-lived `mole status --json` subprocess (no 1Hz polling)
- [ ] **MON-02**: Metrics include CPU, GPU, memory, disk, and network — each independently toggleable in Settings
- [ ] **MON-03**: Display mode is configurable: icon-only, single inline metric, or popover-only (default = popover-only)
- [ ] **MON-04**: Health score (Mole's 0–100 composite) is shown prominently in the popover header
- [ ] **MON-05**: When the menu bar popover is closed, the stats subprocess is suspended or torn down to respect App Nap and battery
- [ ] **MON-06**: Stats parsing failures degrade gracefully (show "—" not "0", log the failure, do not crash)

### Cleaning Actions

- [ ] **CLEAN-01**: Popover surfaces every `mo clean` submodule (App Caches, Orphaned Apps, Homebrew, System Caches, Developer Tools, System Cleanup, User Cleanup) as toggleable groups
- [ ] **CLEAN-02**: Every cleaning action runs `--dry-run` first by default; user reviews the preview before confirming execution
- [ ] **CLEAN-03**: Dry-run preview shows a tree of files/paths and bytes-to-be-freed, with per-item opt-out checkboxes
- [ ] **CLEAN-04**: Files are moved to the user Trash via `NSFileManager.trashItem` whenever possible — direct unlink is reserved for paths Trash cannot reach (system-owned, etc.) and is explicitly flagged in the UI
- [ ] **CLEAN-05**: Action progress streams live from the running subprocess into the popover (not just a spinner)
- [ ] **CLEAN-06**: A power-user toggle unlocks one-click execution (skipping dry-run) for a given action category after the user has used it 3+ times
- [ ] **CLEAN-07**: After a clean completes, a notification reports bytes freed and number of items removed
- [ ] **CLEAN-08**: Cancel during execution stops the subprocess cleanly and reports partial progress

### System Optimization

- [ ] **OPT-01**: Popover surfaces `mo optimize` tasks (DB rebuilds, network reset, Finder/Dock refresh, Spotlight reindex, swap purge, launch services rebuild) — each task individually selectable or "run all"
- [ ] **OPT-02**: Disruptive optimize tasks (network reset, Spotlight reindex) are visually flagged with explicit warnings about user-visible side effects
- [ ] **OPT-03**: Optimize follows the same dry-run-first → confirm → execute pipeline as cleaning
- [ ] **OPT-04**: When `osascript … with administrator privileges` is needed, the auth prompt is presented through a single shared helper with consistent UX

### Project Cruft Purge

- [ ] **PURGE-01**: Popover surfaces `mo purge` to remove `node_modules`, `target`, `.build`, `build`, `dist`, `venv` across user-configured roots
- [ ] **PURGE-02**: Settings includes a "Project roots" editor that reads/writes `~/.config/mole/purge_paths` (one path per line, supports `~`, `#` comments)
- [ ] **PURGE-03**: Purge follows the dry-run-first → confirm → execute pipeline
- [ ] **PURGE-04**: Recently-modified directories (Mole's 7-day-old auto-deselection) are pre-deselected in the preview but visible

### Installer Leftovers

- [ ] **INST-01**: Popover surfaces `mo installer` to find/remove `.pkg` and `.dmg` files from Downloads, Desktop, Homebrew caches, iCloud Drive, and Mail attachments
- [ ] **INST-02**: Installer leftovers follow the dry-run-first → confirm → execute pipeline
- [ ] **INST-03**: User can per-item opt out of the proposed cleanup before confirming

### Disk Analyzer

- [ ] **ANALYZE-01**: A separate `Window` scene (not a popover) hosts the disk analyzer
- [ ] **ANALYZE-02**: Analyzer scans a user-selected root via `mo analyze --json`, decoding into `{path, overview, entries[], large_files[], total_size, total_files}`
- [ ] **ANALYZE-03**: Analyzer renders a treemap (Canvas-based squarified treemap) showing folders proportional to size
- [ ] **ANALYZE-04**: Analyzer also offers a top-N largest files view backed by Mole's `large_files` heap
- [ ] **ANALYZE-05**: User can right-click any item to "Show in Finder", "Open", or "Move to Trash" (Trash routes through the dry-run-first safety pipeline)
- [ ] **ANALYZE-06**: Activation policy is juggled correctly so opening the analyzer window doesn't dock-icon-leak the menu-bar app

### Scheduling & Automation

- [ ] **SCHED-01**: User can schedule recurring runs of any cleaning, optimize, purge, or installer-leftover action (daily / weekly / monthly cadence, plus per-day-of-week)
- [ ] **SCHED-02**: Scheduling is implemented via `SMAppService.agent` (LaunchAgent installed in `~/Library/LaunchAgents/`) — it survives app quit, system sleep, and reboots
- [ ] **SCHED-03**: Scheduled runs default to dry-run + notification (not silent execution); user must opt into headless execution per schedule
- [ ] **SCHED-04**: Scheduled runs can be gated on preconditions: on AC power, screen unlocked, no fullscreen app
- [ ] **SCHED-05**: Missed schedules (machine asleep at fire time) trigger on next wake within a configurable window
- [ ] **SCHED-06**: Notification reports schedule outcome (success/failure, bytes freed, link to operation log)

### Operation Log Viewer

- [ ] **LOG-01**: Popover/window has a panel that tails `~/Library/Logs/mole/operations.log` in real time during action execution
- [ ] **LOG-02**: Op-log viewer offers "Reveal in Finder" and "Open in Console" links
- [ ] **LOG-03**: Op-log viewer summarizes recent activity (last N actions with bytes-freed totals)

### Settings & Preferences

- [ ] **SET-01**: Settings is a SwiftUI `Settings` scene with tabs: General, Display, Cleaning, Notifications, Schedule, Advanced
- [ ] **SET-02**: General tab includes Login-item toggle (`SMAppService.mainApp.register`) and global hotkey to summon the popover
- [ ] **SET-03**: Display tab controls per-metric inline display, popover layout, dark-mode follow-system
- [ ] **SET-04**: Cleaning tab exposes the per-action power-user override, default dry-run behavior, and confirmation thresholds
- [ ] **SET-05**: Notifications tab controls completion alerts, process-watch alerts, schedule outcome notifications
- [ ] **SET-06**: Advanced tab exposes the protected-items / whitelist editor (writing `~/.config/mole/whitelist`, `~/.config/mole/whitelist_optimize`), project roots editor (`~/.config/mole/purge_paths`), and a "Reveal MoleBar Application Support folder" link
- [ ] **SET-07**: Settings persistence uses `UserDefaults`/`@AppStorage`; defaults are migrated forward across app version upgrades without user input

### Notifications

- [ ] **NOTIF-01**: User Notifications permission is requested with clear copy at the moment the user first opts into a notification-emitting feature (not on first launch)
- [ ] **NOTIF-02**: Action-completion notifications report bytes freed, action name, and outcome
- [ ] **NOTIF-03**: Notifications respect the user's Focus / Do Not Disturb state — no overrides

### Bundled CLI Updater

- [ ] **UPD-01**: A built-in `MoleBinaryUpdater` polls the upstream `tw93/mole` GitHub Releases feed for new versions
- [ ] **UPD-02**: Updates are opt-in (default OFF for v1); user is prompted before any binary swap, and the in-bundle binary is always retained as fallback
- [ ] **UPD-03**: Downloaded `mole` binaries are checksum-verified against a project-maintained SHA-256 allowlist before being made executable
- [ ] **UPD-04**: Updated binary is staged at `~/Library/Application Support/MoleBar/bin/mole` (NOT inside the .app — preserves the app signature) and the resolver prefers it over the bundled one
- [ ] **UPD-05**: A binary update never interrupts an in-flight Mole subprocess; new version takes effect on the next invocation

### Open-Source Posture

- [ ] **OSS-01**: Repo is public, MIT-licensed, with a `LICENSE` file and a contributor-friendly `README.md`
- [ ] **OSS-02**: No outbound network traffic occurs other than Sparkle's appcast and (when enabled by user) the bundled-CLI updater check — verified at startup
- [ ] **OSS-03**: No analytics/telemetry of any kind in v1; opt-in crash reporting via Sparkle is allowed but default-OFF
- [ ] **OSS-04**: Signing keys, EdDSA private keys, and Developer ID secrets live in GitHub Actions secrets — never in the repo, never logged

## v2 Requirements

Acknowledged and deferred. Not in current roadmap.

### Smart App Uninstall

- **UNINSTALL-01**: User can drag-target an app onto the popover to uninstall it (or pick from a list)
- **UNINSTALL-02**: UI shows a leftover-diff (Application Support / Caches / Preferences / Logs / WebKit / Cookies / Extensions / Plugins / Launch daemons) with per-item checkboxes
- **UNINSTALL-03**: Uninstall executes via `mo uninstall` and respects the dry-run-first → confirm → execute pipeline

### Full GUI App

- **GUI-01**: Primary window app target is added (separate scene or target) re-using `MoleBarCore` and `MoleBarStores` without modification
- **GUI-02**: Full GUI surfaces every popover capability with richer layouts (multi-pane, larger charts, persistent action history)

### v1.x Polish (post-v1, pre-v2)

- **POL-01**: Live op-log streaming inline in popover during a clean
- **POL-02**: Process-watch alerts (sustained CPU > threshold over window) using `mo status` `--proc-cpu-*` flags
- **POL-03**: Bluetooth peripheral battery panel (AirPods, Magic Mouse) from `mo status` Bluetooth metrics
- **POL-04**: Touch ID for sudo one-click setup via `mo touchid`
- **POL-05**: "Recently freed" running tally in popover (sums bytes-freed from operation log)
- **POL-06**: Localized strings beyond English (Mole supports ~40 languages — follow once core is stable)

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| macOS < 14 (Sonoma) support | New app, no legacy users; targeting 14+ unlocks modern SwiftUI MenuBarExtra/Observation/Charts without compat shims |
| Mac App Store distribution | Sandbox forbids the Full Disk Access writes that Mole's deep-clean requires |
| Reimplementing Mole's logic in Swift | Loses upstream lockstep; re-derives the safety model; defeats the project's value proposition |
| Real-time auto-clean (delete-on-detect, no preview) | Violates dry-run-first safety model; one bad delete = lost user trust |
| Custom user-scripted cleaners | Diverges from Mole's audited safety model; turns MoleBar into a footgun |
| Background telemetry / usage analytics | Trust violation for a destructive tool with FDA; opt-in crash-only is the upper bound |
| Auto-running Mole on first launch | Destructive ops without user consent are nuclear; even a dry-run consumes I/O |
| Replicating iStat Menus weather/world-clock widgets | Not in Mole; outside MoleBar's "Mole feature parity" mission |
| Custom themes / icon packs | Distracts from safety mission; light/dark follow-system is enough |
| Closed-source or paid Pro tier | Breaks Mole MIT ethos; trust signal for a destructive tool requires open source |
| Native iOS / iPadOS / Linux ports | Mole is macOS-specific; the wrapper inherits that constraint |
| Reimplementing the Mole TUI inside the app | Pure UI duplication; the popover IS the new UI |
| In-app purchase / "premium clean profiles" | Same as Pro tier — breaks open-source ethos |
| Live update/patching of bundled `mole` mid-session | Breaks running operations; signature changes mid-flight are user-hostile |
| Auto-installing Raycast/Alfred quick-launchers on user behalf | Territorial conflict with Raycast/Alfred owners; let users opt in via Mole directly |

## Traceability

Populated 2026-04-27 by `gsd-roadmapper`. Each v1 requirement maps to exactly one phase.

| Requirement | Phase | Status |
|-------------|-------|--------|
| DIST-01 | Phase 1 — Distribution Foundations | Pending |
| DIST-02 | Phase 1 — Distribution Foundations | Pending |
| DIST-03 | Phase 1 — Distribution Foundations | Pending |
| DIST-04 | Phase 1 — Distribution Foundations | Pending |
| DIST-05 | Phase 1 — Distribution Foundations | Pending |
| DIST-06 | Phase 1 — Distribution Foundations | Pending |
| DIST-07 | Phase 1 — Distribution Foundations | Pending |
| DIST-08 | Phase 1 — Distribution Foundations | Pending |
| CORE-01 | Phase 2 — CLI Orchestration Core | Pending |
| CORE-02 | Phase 2 — CLI Orchestration Core | Pending |
| CORE-03 | Phase 2 — CLI Orchestration Core | Pending |
| CORE-04 | Phase 2 — CLI Orchestration Core | Pending |
| CORE-05 | Phase 2 — CLI Orchestration Core | Pending |
| CORE-06 | Phase 2 — CLI Orchestration Core | Pending |
| CORE-07 | Phase 2 — CLI Orchestration Core | Pending |
| CORE-08 | Phase 2 — CLI Orchestration Core | Pending |
| MON-01 | Phase 3 — UI Foundations & Live System Monitoring | Pending |
| MON-02 | Phase 3 — UI Foundations & Live System Monitoring | Pending |
| MON-03 | Phase 3 — UI Foundations & Live System Monitoring | Pending |
| MON-04 | Phase 3 — UI Foundations & Live System Monitoring | Pending |
| MON-05 | Phase 3 — UI Foundations & Live System Monitoring | Pending |
| MON-06 | Phase 3 — UI Foundations & Live System Monitoring | Pending |
| PERM-01 | Phase 4 — Permissions Onboarding | Pending |
| PERM-02 | Phase 4 — Permissions Onboarding | Pending |
| PERM-03 | Phase 4 — Permissions Onboarding | Pending |
| PERM-04 | Phase 4 — Permissions Onboarding | Pending |
| PERM-05 | Phase 4 — Permissions Onboarding | Pending |
| CLEAN-01 | Phase 5 — Cleaning Pipeline & Destructive Features | Pending |
| CLEAN-02 | Phase 5 — Cleaning Pipeline & Destructive Features | Pending |
| CLEAN-03 | Phase 5 — Cleaning Pipeline & Destructive Features | Pending |
| CLEAN-04 | Phase 5 — Cleaning Pipeline & Destructive Features | Pending |
| CLEAN-05 | Phase 5 — Cleaning Pipeline & Destructive Features | Pending |
| CLEAN-06 | Phase 5 — Cleaning Pipeline & Destructive Features | Pending |
| CLEAN-07 | Phase 5 — Cleaning Pipeline & Destructive Features | Pending |
| CLEAN-08 | Phase 5 — Cleaning Pipeline & Destructive Features | Pending |
| OPT-01 | Phase 5 — Cleaning Pipeline & Destructive Features | Pending |
| OPT-02 | Phase 5 — Cleaning Pipeline & Destructive Features | Pending |
| OPT-03 | Phase 5 — Cleaning Pipeline & Destructive Features | Pending |
| OPT-04 | Phase 5 — Cleaning Pipeline & Destructive Features | Pending |
| PURGE-01 | Phase 5 — Cleaning Pipeline & Destructive Features | Pending |
| PURGE-02 | Phase 5 — Cleaning Pipeline & Destructive Features | Pending |
| PURGE-03 | Phase 5 — Cleaning Pipeline & Destructive Features | Pending |
| PURGE-04 | Phase 5 — Cleaning Pipeline & Destructive Features | Pending |
| INST-01 | Phase 5 — Cleaning Pipeline & Destructive Features | Pending |
| INST-02 | Phase 5 — Cleaning Pipeline & Destructive Features | Pending |
| INST-03 | Phase 5 — Cleaning Pipeline & Destructive Features | Pending |
| NOTIF-01 | Phase 5 — Cleaning Pipeline & Destructive Features | Pending |
| NOTIF-02 | Phase 5 — Cleaning Pipeline & Destructive Features | Pending |
| NOTIF-03 | Phase 5 — Cleaning Pipeline & Destructive Features | Pending |
| LOG-01 | Phase 5 — Cleaning Pipeline & Destructive Features | Pending |
| LOG-02 | Phase 5 — Cleaning Pipeline & Destructive Features | Pending |
| LOG-03 | Phase 5 — Cleaning Pipeline & Destructive Features | Pending |
| ANALYZE-01 | Phase 6 — Disk Analyzer Window | Pending |
| ANALYZE-02 | Phase 6 — Disk Analyzer Window | Pending |
| ANALYZE-03 | Phase 6 — Disk Analyzer Window | Pending |
| ANALYZE-04 | Phase 6 — Disk Analyzer Window | Pending |
| ANALYZE-05 | Phase 6 — Disk Analyzer Window | Pending |
| ANALYZE-06 | Phase 6 — Disk Analyzer Window | Pending |
| SET-01 | Phase 7 — Settings, Login Item & Scheduling | Pending |
| SET-02 | Phase 7 — Settings, Login Item & Scheduling | Pending |
| SET-03 | Phase 7 — Settings, Login Item & Scheduling | Pending |
| SET-04 | Phase 7 — Settings, Login Item & Scheduling | Pending |
| SET-05 | Phase 7 — Settings, Login Item & Scheduling | Pending |
| SET-06 | Phase 7 — Settings, Login Item & Scheduling | Pending |
| SET-07 | Phase 7 — Settings, Login Item & Scheduling | Pending |
| SCHED-01 | Phase 7 — Settings, Login Item & Scheduling | Pending |
| SCHED-02 | Phase 7 — Settings, Login Item & Scheduling | Pending |
| SCHED-03 | Phase 7 — Settings, Login Item & Scheduling | Pending |
| SCHED-04 | Phase 7 — Settings, Login Item & Scheduling | Pending |
| SCHED-05 | Phase 7 — Settings, Login Item & Scheduling | Pending |
| SCHED-06 | Phase 7 — Settings, Login Item & Scheduling | Pending |
| UPD-01 | Phase 8 — CLI Updater, Cask & v1.0 Launch | Pending |
| UPD-02 | Phase 8 — CLI Updater, Cask & v1.0 Launch | Pending |
| UPD-03 | Phase 8 — CLI Updater, Cask & v1.0 Launch | Pending |
| UPD-04 | Phase 8 — CLI Updater, Cask & v1.0 Launch | Pending |
| UPD-05 | Phase 8 — CLI Updater, Cask & v1.0 Launch | Pending |
| OSS-01 | Phase 1 — Distribution Foundations | Pending |
| OSS-02 | Phase 2 — CLI Orchestration Core | Pending |
| OSS-03 | Phase 8 — CLI Updater, Cask & v1.0 Launch | Pending |
| OSS-04 | Phase 1 — Distribution Foundations | Pending |

**Coverage:**
- v1 requirements: 80 total across 15 categories
- Mapped to phases: 80 (100%)
- Unmapped: 0

**Per-phase distribution:**

| Phase | REQ count | Categories |
|-------|-----------|------------|
| Phase 1 — Distribution Foundations | 10 | DIST (8), OSS (2: 01, 04) |
| Phase 2 — CLI Orchestration Core | 9 | CORE (8), OSS (1: 02) |
| Phase 3 — UI Foundations & Live System Monitoring | 6 | MON (6) |
| Phase 4 — Permissions Onboarding | 5 | PERM (5) |
| Phase 5 — Cleaning Pipeline & Destructive Features | 25 | CLEAN (8), OPT (4), PURGE (4), INST (3), NOTIF (3), LOG (3) |
| Phase 6 — Disk Analyzer Window | 6 | ANALYZE (6) |
| Phase 7 — Settings, Login Item & Scheduling | 13 | SET (7), SCHED (6) |
| Phase 8 — CLI Updater, Cask & v1.0 Launch | 6 | UPD (5), OSS (1: 03) |
| **Total** | **80** | **15 categories** |

---
*Requirements defined: 2026-04-27*
*Last updated: 2026-04-27 — traceability populated by `gsd-roadmapper` (8 phases, 80/80 requirements mapped)*
