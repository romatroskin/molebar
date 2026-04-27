# Roadmap: MoleBar

**Created:** 2026-04-27
**Granularity:** standard (8 phases + 1 inserted = 9 total)
**Coverage:** 80/80 v1 requirements mapped (100%)
**Last revised:** 2026-04-27 — Phase 1.5 inserted via `/gsd-discuss-phase 1` to honor "defer signing setup" decision (DIST-01, DIST-02, DIST-03, DIST-07 moved from Phase 1 → Phase 1.5)

## Overview

MoleBar ships in eight phases that follow the dependency gravity of the project rather than imposing a generic template. Three of the five P0 pitfalls (notarization of the embedded `mole`, Sparkle EdDSA signing — unrotatable post-launch, CI secret hygiene) are distribution-layer concerns, so **Phase 1 builds and ships an end-to-end 0.0.1 dummy release before any feature exists.** Phase 2 then builds the subprocess orchestration core (`MoleClient` actor, versioned models, async pipe draining) on top of which everything else streams. Phase 3 lights up the first end-to-end vertical slice (live stats in the menu bar) to validate the UI/Core split that v2 depends on. Phase 4 builds the Full Disk Access onboarding flow that gates every destructive feature. Phase 5 is the bulk feature phase — clean, optimize, purge, installer-leftovers, notifications, and the operation-log viewer all share one `Command → Confirm → Dry-Run → Execute → Log` state machine, so they ship together. Phase 6 adds the disk analyzer in a second `Window` scene, forcing the multi-scene/UI-agnostic-core split. Phase 7 layers settings, login-item, and scheduling on top of a stable architecture. Phase 8 ships the bundled-CLI auto-updater, the no-telemetry verification, and Homebrew Cask submission for v1.0 launch.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Distribution Foundations** - Unsigned 0.0.1 dummy round-trip through CI pipeline (DMG + Sparkle appcast + 0.0.1 → 0.0.2 update); locks the unrotatable decisions (Sparkle EdDSA key, repo/tap topology, CI secret hygiene) without requiring an Apple Developer ID
- [ ] **Phase 1.5: Sign & Ship for Real** *(INSERTED — depends on Apple Developer Program enrollment)* - Retrofit Phase 1's pipeline with real code signing, notarization (notarytool + stapler), bundled-binary re-signing, and Homebrew Cask publication; cut a signed/notarized release that passes Gatekeeper
- [ ] **Phase 2: CLI Orchestration Core** - `MoleClient` actor with non-deadlocking subprocess streaming, versioned Codable models, and the no-outbound-traffic invariant
- [ ] **Phase 3: UI Foundations & Live System Monitoring** - First end-to-end vertical slice: MenuBarExtra `.window` popover with live CPU/GPU/memory/disk/network from `mo status --json`
- [ ] **Phase 4: Permissions Onboarding** - First-run Full Disk Access flow that gracefully degrades destructive features when denied and re-probes on every activation
- [ ] **Phase 5: Cleaning Pipeline & Destructive Features** - Shared dry-run-first state machine powering clean, optimize, purge, installer-leftovers, notifications, and the operation-log viewer
- [ ] **Phase 6: Disk Analyzer Window** - Separate `Window` scene with squarified treemap, top-N largest-files view, and Trash-routed in-place delete (validates v2 plug-in seam)
- [ ] **Phase 7: Settings, Login Item & Scheduling** - SwiftUI Settings scene, login-item toggle, and `SMAppService.agent` LaunchAgent scheduler with miss-detection
- [ ] **Phase 8: CLI Updater, Cask & v1.0 Launch** - Opt-in bundled-binary auto-updater, no-telemetry verification, Homebrew Cask publication, and v1.0 ship

## Phase Details

### Phase 1: Distribution Foundations
**Goal**: Ship an UNSIGNED 0.0.1 dummy release end-to-end through the entire CI pipeline (build → DMG → Sparkle appcast → 0.0.1 → 0.0.2 round-trip) so the unrotatable decisions (Sparkle EdDSA key, repo/tap topology, CI secret hygiene, bundle ID, appcast URL) are locked before any feature ships. Code signing and notarization steps are scaffolded into the pipeline as stubbed/skipped jobs — they activate in Phase 1.5 once an Apple Developer ID is available.
**Depends on**: Nothing (first phase)
**Requirements**: DIST-04, DIST-05, DIST-06, DIST-08, OSS-01, OSS-04
**Success Criteria** (what must be TRUE):
  1. Pushing a `vX.Y.Z` tag triggers the GitHub Actions release workflow on `macos-15`, which produces an unsigned `.dmg` artifact via `create-dmg` (standard drag-to-Applications layout) and uploads it to a GitHub Release.
  2. A 0.0.1 → 0.0.2 Sparkle update completes end-to-end with EdDSA verification (with `SURequireSignedFeed` enabled): user manually triggers "Check for Updates…" from the MenuBarExtra stub, sees the update prompt, and the new version installs and launches with the correct `CFBundleShortVersionString` from the git tag.
  3. The Sparkle appcast is published at `https://puffpuff.dev/molebar/appcast.xml` via the `gh-pages` branch; CI commits the EdDSA-signed appcast on every release.
  4. The bundled real `mole` binary (Universal2 lipo of a pinned upstream `tw93/mole` release) is present at `Contents/Helpers/mole` and is launchable from the dummy app's process — validating the bundle path resolution that Phase 2's `MoleClient` depends on.
  5. The repository at `github.com/romatroskin/molebar` is public, MIT-licensed, has a contributor-friendly README, and CI logs across the most recent 5 runs contain zero raw secrets (Sparkle EdDSA private key, ASC API key) — verified by `git log --all -p` grep + secret-scanning push protection.
**Plans**: TBD

### Phase 1.5: Sign & Ship for Real *(INSERTED)*
**Goal**: Retrofit Phase 1's CI pipeline with real Apple Developer ID signing (`--options runtime --timestamp`), notarization (`xcrun notarytool` + `xcrun stapler`), bundled-binary re-signing (inside-out, no `--deep`), and Homebrew Cask publication via a personal tap. Cut the first signed/notarized release that passes Gatekeeper on a clean Mac and is installable via `brew install --cask`.
**Depends on**: Phase 1 (and externally: Apple Developer Program enrollment is complete with a Developer ID Application certificate available)
**Requirements**: DIST-01, DIST-02, DIST-03, DIST-07
**Success Criteria** (what must be TRUE):
  1. A clean Mac (no prior dev build) can install the signed `.dmg` from a GitHub Release, see Gatekeeper accept it, and launch MoleBar without security warnings.
  2. The bundled `mole` binary at `Contents/Helpers/mole` is re-signed with hardened runtime + timestamp (independently of the .app, never via `--deep`) and passes `spctl --assess --type execute -vvv` plus `codesign --verify --deep --strict --verbose=2`.
  3. CI authenticates to Apple's notarization service via App Store Connect API Key (Issuer ID + Key ID + .p8 stored in GitHub Actions secrets) and signs + notarizes + staples on tag push without manual intervention.
  4. `brew tap romatroskin/tap && brew install --cask molebar` installs the same notarized artifact end-to-end on a fresh Mac; the Cask formula is auto-bumped on each tag push (`auto_updates true`).
  5. The first signed release ships with release notes linking to the GitHub Release page, and Sparkle still performs a successful update round-trip (signed → newer signed) with EdDSA verification continuing to pass — proving the signing retrofit didn't break Phase 1's update plumbing.
**Plans**: TBD

### Phase 2: CLI Orchestration Core
**Goal**: Build the UI-agnostic `MoleBarCore` SwiftPM module with a non-deadlocking subprocess wrapper, versioned Codable models, the `MoleClient` actor public API, and the no-outbound-network-traffic invariant — so every later feature streams from a stable foundation.
**Depends on**: Phase 1
**Requirements**: CORE-01, CORE-02, CORE-03, CORE-04, CORE-05, CORE-06, CORE-07, CORE-08, OSS-02
**Success Criteria** (what must be TRUE):
  1. A 10-concurrent-invocation stress test of `MoleClient.runAction(_:dryRun:)` followed by per-invocation `Task.cancel()` leaves zero zombie `mole` PIDs in Activity Monitor and produces no deadlocks (cancel-during-large-stdout completes within 1 second via process-group SIGTERM → SIGKILL).
  2. A schema-incompatible `mole` JSON payload surfaces as a typed `MoleEvent` decode error (with the offending payload preserved for diagnostics) and is recoverable — never a silent loss and never a crash.
  3. The bundled `mole` resolves correctly from `Contents/Helpers/mole`, with explicit `PATH`/`HOME`/`LANG` environment that is immune to user shell config (oh-my-zsh, asdf, Homebrew/Nix shadows) — verified by an integration test that runs against a poisoned `~/.zshrc`.
  4. A nightly CI job downloads the latest upstream `tw93/mole` `main`, runs MoleBar's parser test suite against it, and opens an issue/PR on schema drift — visible in the repo's Actions tab.
  5. Little Snitch in deny-all mode shows zero outbound network calls from MoleBar at startup or during stats streaming (only the explicitly-allowed Sparkle appcast URL appears, and only on user-initiated update check); `LICENSE-MOLE.txt` is present in `Contents/Resources/` for upstream attribution.
**Plans**: TBD

### Phase 3: UI Foundations & Live System Monitoring
**Goal**: Stand up the SwiftUI app shell (`MenuBarExtra` `.window` style + `StatsStore` + popover skeleton) and wire it to a long-lived `mo status --json` stream so users see live CPU / GPU / memory / disk / network / health-score in the menu bar — the first end-to-end demonstration that the architecture works.
**Depends on**: Phase 2
**Requirements**: MON-01, MON-02, MON-03, MON-04, MON-05, MON-06
**Success Criteria** (what must be TRUE):
  1. User opens the popover and sees live CPU, GPU, memory, disk, and network metrics updating in real time, plus Mole's 0–100 health score in the popover header.
  2. User can toggle each metric independently in Settings, and the menu-bar display mode (icon-only / single inline metric / popover-only — default) reflects the user's choice across launches.
  3. When the popover is closed, the long-lived `mole status --json` subprocess is suspended or torn down (verified by Activity Monitor), so MoleBar's idle energy impact is ≤0.1 in the Energy tab over a 1-hour battery test.
  4. When `mole`'s status JSON is malformed or the stream silences for >30 seconds, the popover renders "—" for the affected metric (never "0"), logs the failure via `os.Logger`, and the watchdog restarts the subprocess on the next user activation — the app does not crash.
  5. The popover renders correctly on macOS 14.0, the latest 14.x, and the latest 15.x (no FB13683957/FB11984872/14.6.1-popover-crash regressions); on any blocker, the thin-shell `PopoverRootView` swaps to an `NSStatusItem` host without rewriting content.
**Plans**: TBD
**UI hint**: yes

### Phase 4: Permissions Onboarding
**Goal**: Build the Full Disk Access onboarding flow — first-run guidance, deep link to System Settings, re-probe on every activation, graceful degradation of destructive actions when denied — so the cleaning phase that follows can assume FDA is granted-or-explicitly-disabled.
**Depends on**: Phase 3
**Requirements**: PERM-01, PERM-02, PERM-03, PERM-04, PERM-05
**Success Criteria** (what must be TRUE):
  1. On first launch, a clear onboarding sheet explains why MoleBar needs Full Disk Access, what it will and will not do with that access, and links to the open-source repo plus the operation-log path as trust signals; user can deep-link to System Settings → Privacy & Security → Full Disk Access from a single button.
  2. After the user grants FDA in System Settings, MoleBar re-launches itself automatically so the new TCC permissions are inherited; the popover indicator flips from "FDA = Denied" to "FDA = Granted" without further user action.
  3. If the user revokes FDA after launch, the next popover open detects the revocation (via the "attempt + catch" probe of a known-protected file, never `TCC.db`) and disables every destructive action with an inline "Grant access" CTA — the app does not crash, hang, or silently fail.
  4. Stats continue to render in degraded mode when FDA is denied (the metrics that work without FDA still update), with a banner explaining what is missing and how to fix it.
  5. A "Diagnostic: FDA = Granted/Denied" indicator is visible in the popover footer at all times, and clicking it re-opens the onboarding sheet.
**Plans**: TBD
**UI hint**: yes

### Phase 5: Cleaning Pipeline & Destructive Features
**Goal**: Build the `Command → Confirm → Dry-Run → Execute → Log` state machine once and slot every destructive feature into it — `mo clean` modules, `mo optimize` tasks, `mo purge`, `mo installer` — with `NSFileManager.trashItem` as the deletion primitive (not `rm`), the 3+-uses power-user toggle, completion notifications, and the operation-log viewer.
**Depends on**: Phase 4
**Requirements**: CLEAN-01, CLEAN-02, CLEAN-03, CLEAN-04, CLEAN-05, CLEAN-06, CLEAN-07, CLEAN-08, OPT-01, OPT-02, OPT-03, OPT-04, PURGE-01, PURGE-02, PURGE-03, PURGE-04, INST-01, INST-02, INST-03, NOTIF-01, NOTIF-02, NOTIF-03, LOG-01, LOG-02, LOG-03
**Success Criteria** (what must be TRUE):
  1. User taps any cleaning, optimize, purge, or installer-leftover action and sees a dry-run preview tree showing every file/path and bytes-to-be-freed, with per-item opt-out checkboxes; only after explicit confirmation do files move to Trash (recoverable via Cmd+Z in Finder), with system-owned paths Trash cannot reach explicitly flagged in the UI.
  2. After a clean completes, the user sees a notification reporting bytes freed and items removed (respecting Focus / Do Not Disturb), and the operation log viewer in the popover surfaces a real-time tail of `~/Library/Logs/mole/operations.log` plus a recent-activity summary with "Reveal in Finder" / "Open in Console" links.
  3. After 3+ uses of a given action category, the per-category power-user toggle becomes available; once the user opts in, that category's confirmation step is skipped (but every deletion is still logged to JSONL for audit) — confirmation wording varies across categories to defeat muscle-memory click-through.
  4. Disruptive optimize tasks (network reset, Spotlight reindex) display explicit warnings about user-visible side effects, route privilege escalation through a single shared `osascript … with administrator privileges` helper with consistent UX, and the project-purge view pre-deselects (but still shows) directories modified in the last 7 days.
  5. Cancel during execution stops the subprocess cleanly (process-group SIGTERM → SIGKILL), reports partial progress, and logs the partial result; user-facing notification permission is requested at the moment the user first opts into a notification-emitting feature, not on first launch.
**Plans**: TBD
**UI hint**: yes

### Phase 6: Disk Analyzer Window
**Goal**: Add a separate `Window` scene hosting `mo analyze --json` results as a Canvas-based squarified treemap plus a top-N largest-files view, with right-click "Show in Finder / Open / Move to Trash" actions routed through the shared dry-run-first safety pipeline — the forcing function for the multi-scene, UI-agnostic-core split that v2 depends on.
**Depends on**: Phase 5
**Requirements**: ANALYZE-01, ANALYZE-02, ANALYZE-03, ANALYZE-04, ANALYZE-05, ANALYZE-06
**Success Criteria** (what must be TRUE):
  1. From the popover, user picks a folder root (or types a path) and the disk analyzer opens in its own `Window` scene (not a popover); a Canvas-based squarified treemap renders with folders sized proportionally to their on-disk byte total.
  2. User can switch between the treemap view and a top-N largest-files list backed by Mole's `large_files` heap, with both views responsive on directories containing at least 100k entries (no main-thread stalls).
  3. User can right-click any item to "Show in Finder", "Open", or "Move to Trash" — the Trash route flows through the shared dry-run-first safety pipeline from Phase 5, with the 60-second-modification guard and JSONL audit log.
  4. Opening the disk-analyzer window flips the activation policy to `.regular` (so the window appears with normal app focus), and closing the last window flips it back to `.accessory` (so the menu-bar app stays menu-bar — no leaked Dock icon).
  5. `mo analyze --json` decoding errors (corrupt or unexpectedly-shaped payloads) are reported in the window's status bar with a "report bug" link, never silently lose data, and never crash the analyzer or the host menu-bar app.
**Plans**: TBD
**UI hint**: yes

### Phase 7: Settings, Login Item & Scheduling
**Goal**: Build the SwiftUI `Settings` scene (General / Display / Cleaning / Notifications / Schedule / Advanced tabs), the `SMAppService.mainApp` login-item toggle, and the `SMAppService.agent` LaunchAgent scheduler with explicit miss-detection — so users can fully customize MoleBar and run cleanups on a recurring schedule that survives app quit, sleep, and reboots.
**Depends on**: Phase 6
**Requirements**: SET-01, SET-02, SET-03, SET-04, SET-05, SET-06, SET-07, SCHED-01, SCHED-02, SCHED-03, SCHED-04, SCHED-05, SCHED-06
**Success Criteria** (what must be TRUE):
  1. User opens Settings (Cmd+,), navigates the General / Display / Cleaning / Notifications / Schedule / Advanced tabs, and finds every documented setting (login-item toggle, global hotkey, per-metric inline display, dark-mode follow-system, default dry-run behavior, completion alerts, project-roots editor for `~/.config/mole/purge_paths`, whitelist editor for `~/.config/mole/whitelist` and `whitelist_optimize`, and a "Reveal Application Support folder" link) — settings persist across launches and migrate forward across app version upgrades without user input.
  2. User schedules a recurring run (daily / weekly / monthly cadence + per-day-of-week) of any clean, optimize, purge, or installer-leftover action; the schedule is implemented via `SMAppService.agent` (LaunchAgent in `~/Library/LaunchAgents/`) and survives app quit, system sleep, and reboot.
  3. Scheduled runs default to dry-run + notification (never silent destructive execution); user must opt into headless execution per schedule via an explicit "I understand this will delete files without preview" confirmation, and a pre-run notification ("Cleanup running in 60 seconds, click to cancel") fires before any destructive scheduled run.
  4. User can gate scheduled runs on preconditions (on AC power, screen unlocked, no fullscreen app); a missed schedule (machine asleep at fire time) triggers on next wake within a configurable window with explicit user notification — never silently skipped, never silently double-fired.
  5. A "Test schedule now" button fires the configured action immediately (catching plist / environment / launchd registration bugs in seconds), and the schedule outcome notification reports success/failure, bytes freed, and a deep link to the operation log.
**Plans**: TBD
**UI hint**: yes

### Phase 8: CLI Updater, Cask & v1.0 Launch
**Goal**: Ship the opt-in `MoleBinaryUpdater` (default OFF for v1) that polls `tw93/mole` GitHub Releases with SHA-256 verification and atomic staged-binary swap, verify the no-telemetry invariant end-to-end, finalize the Homebrew Cask submission, and cut the v1.0 release.
**Depends on**: Phase 7
**Requirements**: UPD-01, UPD-02, UPD-03, UPD-04, UPD-05, OSS-03
**Success Criteria** (what must be TRUE):
  1. User opts in to the bundled-CLI auto-update toggle (default OFF for v1) and is prompted before any binary swap; updated binaries are downloaded to `~/Library/Application Support/MoleBar/bin/mole.staged`, SHA-256-verified against MoleBar's project-maintained allowlist, made executable via `chmod 755`, and atomically renamed via `rename(2)` — never overwriting the bundled fallback at `Contents/Helpers/mole`.
  2. After a binary update, the resolver prefers the user copy over the bundled fallback on the next subprocess spawn; an in-flight `mo status --json --watch` or cleaning operation is never interrupted mid-execution by an update — the new version takes effect on the next invocation.
  3. A binary that fails SHA-256 verification (or is signed with an unexpected team prefix) is rejected with an explicit user-visible notification, and the bundled fallback continues to be used — Gatekeeper does not block subprocess invocation of the staged binary by an already-notarized parent (verified end-to-end on a clean Mac).
  4. Little Snitch in deny-all mode confirms there is zero analytics or telemetry traffic in v1; opt-in crash reporting via Sparkle is allowed but defaults OFF, and the README's first paragraph explicitly documents the "Sparkle appcast + opt-in upstream-Mole release check are the only outbound network calls" invariant.
  5. v1.0 ships: the Homebrew Cask passes `brew audit --cask --new` and `brew install --cask molebar` end-to-end on a fresh user's Mac; release notes link to upstream `tw93/mole`, document the compatibility matrix (which MoleBar versions support which Mole CLI versions), and a fresh-install user can complete the FDA onboarding, run a dry-run clean, and see the result notification — the full v1.0 happy path.
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 1.5 → 2 → 3 → 4 → 5 → 6 → 7 → 8

**Note:** Phase 1.5 is blocked on Apple Developer Program enrollment. Phases 2+ can begin in parallel with Phase 1.5 once Phase 1 is complete; Phase 1.5 retrofits signing into the existing pipeline rather than gating downstream feature work.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Distribution Foundations | 0/TBD | Not started | - |
| 1.5. Sign & Ship for Real *(INSERTED)* | 0/TBD | Not started — blocked on Apple Developer Program enrollment | - |
| 2. CLI Orchestration Core | 0/TBD | Not started | - |
| 3. UI Foundations & Live System Monitoring | 0/TBD | Not started | - |
| 4. Permissions Onboarding | 0/TBD | Not started | - |
| 5. Cleaning Pipeline & Destructive Features | 0/TBD | Not started | - |
| 6. Disk Analyzer Window | 0/TBD | Not started | - |
| 7. Settings, Login Item & Scheduling | 0/TBD | Not started | - |
| 8. CLI Updater, Cask & v1.0 Launch | 0/TBD | Not started | - |

---
*Roadmap created: 2026-04-27 by `gsd-roadmapper`*
*Coverage: 80/80 v1 requirements mapped (100%)*
