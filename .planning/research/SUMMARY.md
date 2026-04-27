# Project Research Summary

**Project:** MoleBar
**Domain:** Public, MIT-licensed, notarized native macOS 14+ menu-bar app wrapping the third-party `tw93/mole` Shell+Go CLI to perform destructive filesystem operations. Single-developer indie posture; distributed via GitHub Releases + Homebrew Cask + Sparkle 2; not Mac App Store.
**Researched:** 2026-04-27
**Confidence:** HIGH on stack core, features, architecture; MEDIUM on a small set of decisions flagged below as Phase 0/1 spikes (subprocess library choice, mole JSON schema stability, treemap rendering ceiling).

---

## TL;DR

MoleBar is a native macOS 14+ SwiftUI menu-bar app that orchestrates a bundled `tw93/mole` binary as a child subprocess and surfaces every Mole capability — minus app-uninstall, deferred to v2 — through a `MenuBarExtra(style: .window)` popover plus a single `Window` scene for the disk analyzer. The architecture is a thin app target over a SwiftPM package (`MoleBarCore` UI-agnostic, `MoleBarStores` `@Observable @MainActor`, `MoleBarUI` SwiftUI), which forces a clean v2 plug-in seam from day one. The single biggest project risk is the destructive-action trust surface (Pitfalls #1, #2, #4, #7, #12 are all P0 ship-blockers); the recommended sequencing is therefore **Phase 0 = signing/Sparkle/CI pipeline before any feature**, **Phase 1 = subprocess orchestration core with proper async pipe draining and process-group cleanup**, then features layered on top in dependency order. Two open conflicts surfaced across the four research files (subprocess library, MenuBarExtra style, phase ordering) are resolved below with explicit rationale.

---

## Executive Summary

MoleBar belongs to the small, well-trodden category of "SwiftUI menu-bar utility that bundles a Unix CLI" (alongside published peers like exelban/Stats, AlDente, and Maccy). The expert path is well-documented: ship a notarized `.dmg` via GitHub Releases + a Homebrew Cask + Sparkle 2 in-app updates, target macOS 14+ to unlock `MenuBarExtra` / `@Observable` / Charts without compatibility shims, and isolate all subprocess orchestration behind an `actor` boundary so the UI never touches `Foundation.Process` directly. The recommended stack is mostly a HIGH-confidence default set (Swift 6 / SwiftUI / `@Observable` / `os.Logger` / Sparkle 2.9.x / `SMAppService` LaunchAgents / Hardened Runtime); the only soft calls are project-generation (raw Xcode project chosen over Tuist for a single-developer scope) and the subprocess wrapper (resolved below).

The dominant risk is **trust loss through a destructive bug, a leaked signing key, or a flaky update channel**. PITFALLS identifies five P0 ship-blockers (notarization of the embedded `mole` binary, subprocess pipe deadlock, Sparkle EdDSA signature drift, Full Disk Access permission loop, no-undo on cleanup) and one P0-if-exploited (CI secret leak). The mitigation pattern is consistent across all of them: build the safety/distribution infrastructure **first**, before any feature. This argues strongly for adopting PITFALLS' **Phase 0 (Distribution Foundations)** ordering over STACK's feature-first sketch — and aligns with PROJECT.md's "trust is the differentiator" framing.

The recommended approach is therefore: (1) lock down signing/notarization/Sparkle/CI in Phase 0 with a 0.0.1 dummy release; (2) build the subprocess core and `MoleClient` actor in Phase 1 with proper `AsyncStream` draining, process-group cleanup, environment hygiene, and a JSON-schema validator gate against upstream Mole; (3) build the FDA onboarding flow and live-stats hot path as the first end-to-end vertical slice; (4) layer cleaning features behind a single `Command → Confirm → Dry-Run → Execute → Log` state machine with `NSFileManager.trashItem` as the deletion primitive; (5) add the disk analyzer window (forces the UI/core split that v2 will rely on); (6) add scheduling via `SMAppService` with explicit miss-detection on launch; (7) ship.

---

## Key Findings

### Recommended Stack

A native Swift 6 + SwiftUI app targeting macOS 14, packaged as a thin Xcode app target over a SwiftPM package with three library modules (`MoleBarCore` UI-agnostic, `MoleBarStores` `@Observable @MainActor`, `MoleBarUI` SwiftUI). Sparkle 2.9.x for app self-update; a custom `MoleBinaryUpdater` for the bundled CLI (Sparkle is per-app, not per-resource); `SMAppService` LaunchAgent for scheduled cleanups; `os.Logger` for unified logging; `@AppStorage`/UserDefaults for settings (no SwiftData in v1).

**Core technologies (all HIGH confidence unless noted):**
- **Swift 6.x / Xcode 16.3+** — required for `@Observable`, modern strict concurrency, built-in swift-format
- **SwiftUI `MenuBarExtra` with `.menuBarExtraStyle(.window)`** — `.menu` style blocks the runloop while open (FB13683957) and is unusable for live data; `.window` is mandatory
- **AppKit interop where SwiftUI is insufficient** — `NSStatusItem` right-click handling, `NSWindow` styling for the disk-analyzer scene; thin shell so AppKit fallback is a swap, not a rewrite
- **`@Observable` / Observation framework** — pull-based fine-grained invalidation; macOS 14 floor unlocks it unconditionally
- **Swift Charts** — for CPU/RAM/net trend lines in the popover; **no built-in treemap**, render via `Canvas` + squarified-treemap layout (fallback: YMTreeMap if perf needed)
- **Subprocess orchestration: `Foundation.Process` for v1, planned migration to `swift-subprocess` post-1.0** — see Conflict Resolution #1 below
- **Sparkle 2.9.x with EdDSA + `SURequireSignedFeed`** — distributed via SwiftPM; EdDSA private key is single most-critical secret
- **`SMAppService` LaunchAgent (macOS 13+)** — for recurring cleanups; not `BackgroundTasks` (iOS-only on Apple's docs), not in-process `Timer` (dies with the app)
- **`os.Logger` (Unified Logging)** — one subsystem, multiple categories; never `print()`
- **`UserDefaults` / `@AppStorage` (versioned Codable JSON for composite settings)** — SwiftData deferred unless scan history needs queryable storage
- **Xcode native project (NOT Tuist) for v1** — MEDIUM confidence; revisit at v2 multi-target growth
- **GitHub Actions on macos-14/15 runner + plain `release.sh` (NOT Fastlane)** — Fastlane Match overkill for one Developer ID + one CI runner

**Distribution & signing:**
- Notarization via `xcrun notarytool` + `xcrun stapler`; sign **inside-out** (mole binary first, then `.app`); never `codesign --deep` (Apple-deprecated, "considered harmful")
- `.dmg` via the `create-dmg` shell script (signed + notarized after creation), not `.zip` (strips executable bit and drops drag-to-Applications hint)
- Homebrew Cask with `auto_updates true` so Brew defers to Sparkle post-install; versioned artifact URLs (never `download/latest/`)
- Bundled `mole` lives in `Contents/Helpers/mole` (Apple's cleanest convention for non-main executables); auto-updated copy lives in `~/Library/Application Support/MoleBar/bin/mole`; `MoleResolver` prefers user copy over bundled fallback

**Explicitly NOT in v1:** Combine for state, ObservableObject, ChartsOrg/Charts, SwiftLint, Tuist, Fastlane, SwiftData, App Sandbox, `BackgroundTasks`, `altool`, `codesign --deep`, `Process.launchPath`, `--deep` signing, in-bundle updates of the mole binary, telemetry/analytics of any kind.

See `STACK.md` for the full table.

### Expected Features

Source-of-truth Mole inventory was verified against `tw93/mole` README and `cmd/`+`lib/` listings on `main` (2026-04-27). PROJECT.md's "Full Mole feature parity in the menu bar" mission means every Mole subcommand except `uninstall` (deferred to v2) must be reachable from MoleBar v1.

**Must have (v1 / table stakes — 17 features):**
- Bundled `mole` binary + auto-updater (foundational; gates everything)
- FDA permissions onboarding (must precede any destructive action)
- Live menu-bar metrics from `mo status --json --watch` (CPU/GPU/memory/disk/net) with display-mode configurability
- One-click cleaning (`mo clean` modules: caches, browser data, logs, Trash, dev tools)
- System optimization (`mo optimize`: DB rebuilds, network reset, Finder/Dock refresh, Spotlight reindex)
- Project cruft purge (`mo purge`: `node_modules`, `target`, `.build`, `dist`, `venv`) with project-roots editor
- Installer leftovers cleanup (`mo installer`)
- Disk analyzer **window** (`mo analyze` with treemap/tree view, top-N large files, in-place delete) — requires `Window` scene, not popover
- Dry-run-first preview with 3+ uses → power-user toggle unlock
- Operation log viewer (tails `~/Library/Logs/mole/operations.log`)
- Settings window (General / Display / Cleaning / Notifications / Advanced)
- Login-item toggle (via `SMAppService.mainApp.register`)
- Notifications for action completion (UserNotifications)
- Sparkle 2 in-app auto-update for MoleBar itself
- Notarized signed `.dmg` + Homebrew Cask
- Scheduling / automation (cron-style or weekly/monthly) with notification on result — D1 differentiator
- Health score widget (`mo status` health metric) — D6 differentiator (cheap freebie)

**Should have (v1.x — competitive polish):**
- Live op-log streaming in popover during a run (D5)
- Process-watch alerts (sustained CPU > threshold, via `mo status --proc-cpu-*` flags) (D8)
- Bluetooth peripheral battery panel — AirPods, Magic Mouse (D9)
- Touch ID for sudo one-click setup (`mo touchid`) (D10)
- "Recently freed" running tally in popover (D11)
- Right-click menu enrichments (quick-clean shortcut, etc.)

**Defer (v2+):**
- **App uninstaller (smart uninstall with leftover review)** — A1 / explicit v2 deliverable per PROJECT.md; signature Mole feature, but heaviest UX surface
- Full GUI window app beyond the disk analyzer
- Localized strings beyond English (Mole supports ~40 languages)
- Statistics dashboard ("space reclaimed over time" with Charts)
- Backup integration (APFS local snapshots before clean)

**Anti-features (deliberately NOT built — see FEATURES.md A1–A15):**
- Reimplementing Mole logic in Swift (loses upstream lockstep)
- Mac App Store distribution (sandbox blocks deep clean)
- Real-time auto-clean / delete-on-detect (violates dry-run safety model)
- Custom scriptable cleaners (turns app into footgun)
- Closed-source / Pro tier (breaks Mole MIT ethos and trust signal)
- Telemetry / analytics, even opt-in for v1 (Pitfall #11)
- macOS < 14 support (no legacy users; modern API floor is the point)
- Native iOS / iPadOS / Linux ports
- Auto-running mole on first launch
- Live in-place updates of bundled binary mid-session
- Replicating iStat-style weather/world-clock widgets (out of mission)

See `FEATURES.md` for the verified Mole inventory, peer survey (Stats, iStat Menus, CleanMyMac, AlDente, Maccy), the dependency graph, and the full feature prioritization matrix.

### Architecture Approach

A **thin SwiftUI app target over a SwiftPM library package** with three modules in dependency order:

```
MoleBarUI (SwiftUI views, popover, disk window, settings, onboarding)
   └── imports
MoleBarStores (@Observable @MainActor view-models — StatsStore, ActionStore, ScanStore, SettingsStore)
   └── imports
MoleBarCore (UI-agnostic, no SwiftUI imports — MoleClient actor, ProcessRunner, MoleResolver, JobLog, PermissionsProbe, Scheduler, MoleBinaryUpdater, Models)
```

Five load-bearing patterns: (1) `MoleClient` is an **actor** exposing `AsyncStream`/`async throws` only — UI never sees `Process`; (2) Each domain has a `@Observable @MainActor` store with a single owner `Task` consuming the AsyncStream from `MoleClient`; (3) every destructive action follows the **Command → Confirm → Dry-Run → Execute → Log** state machine inside `ActionStore`, with the "skip preview after 3+ uses" toggle as a single guard at one transition; (4) **two completely separate update channels** — Sparkle for the app, custom `MoleBinaryUpdater` for the CLI binary, with `MoleResolver` preferring user copy over bundled fallback; (5) FDA detection is **probe-on-every-popover-open** ("attempt + handle error" against a known-protected file like `~/Library/Mail` or `/Library/Preferences/com.apple.TimeMachine.plist`), never cached as a `Bool`.

**Major components:**
1. **`MoleClient` (actor)** — public Core API: `streamStats()`, `runAction(_:dryRun:)`, `analyzeDisk(root:)`. Single seam for testability and orphan-process cleanup.
2. **`ProcessRunner`** — `Foundation.Process` + `Pipe` + drained-async-stream adapter; explicit curated environment; process-group launch for cancel-the-tree semantics.
3. **`*Store` (StatsStore, ActionStore, ScanStore, SettingsStore)** — `@Observable @MainActor` view-models; cancel their consumer `Task` on `deinit`/scene close.
4. **`MoleResolver` + `MoleBinaryUpdater`** — resolves bundled-vs-user-copy; downloads new mole binary to staged path, verifies SHA-256 from upstream release notes, atomic rename.
5. **`Scheduler` + LaunchAgent helper** — wraps `SMAppService.agent(plistName:).register()`; spawns a tiny separate `mole-scheduler-runner` helper executable that invokes mole + posts a notification, independent of main app lifecycle.
6. **`PermissionsProbe`** — FDA "attempt + catch" probe; opens `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles` on denial.
7. **`JobLog`** — append-only JSONL at `~/Library/Application Support/MoleBar/jobs.jsonl`; both main app and LaunchAgent helper write to it (atomic line-sized writes via `O_APPEND`).
8. **`AppUpdater`** — `SPUStandardUpdaterController` wrapper; quarantined inside `MoleBarUpdater` so Combine/KVO never leak elsewhere.

**v2 plug-in seams (already implied by this architecture, costing ~zero additional work):**
- New full-GUI app target — links the same SwiftPM modules; replaces popover with full window scene
- App uninstaller — adds `MoleAction.uninstallApp(...)` + drag-target view; reuses ActionStore state machine as-is
- New mole subcommands as upstream ships them — add cases to `MoleAction` enum + UI buttons
- iCloud sync of settings/schedules — replace `@AppStorage` with iCloud KVS in SettingsStore

**Build order (each step unlocks the next):** ProcessRunner+MoleResolver → Models → MoleClient → StatsStore → app shell + MenuBarExtra `.window` + popover skeleton (= first end-to-end demo) → PermissionsProbe + FDA flow → ActionStore + dry-run pipeline + clean features → JobLog → disk analyzer Window scene + ScanStore + treemap (= validates v2 plug-in point) → Scheduler + LaunchAgent helper → Sparkle integration → MoleBinaryUpdater (independent; can ship in 1.1 if 1.0 ships with bundled mole only).

See `ARCHITECTURE.md` for the full diagram, file layout, code examples, scaling considerations, and anti-patterns.

### Critical Pitfalls (Top 5 P0 + 1 P0-if-exploited)

1. **Bundled `mole` binary fails notarization or won't execute (P0)** — embed-binary apps must sign **inside-out** (`codesign -o runtime --timestamp` on `mole` BEFORE `.app`), with the same Developer ID Team prefix as the host. Re-sign upstream-downloaded binaries; never `codesign --deep`. Ship via `.dmg` with drag-to-Applications hint to defeat translocation. CI gate: `spctl --assess --type execute -vvv` + `codesign --verify --deep --strict --verbose=2` must pass before release.

2. **Subprocess pipe deadlock hangs the menu bar app (P0)** — the canonical `Foundation.Process` footgun: pipe buffer (16-64 KB) fills, mole blocks on write, app blocks on `waitUntilExit`, both deadlock. Always drain stdout AND stderr asynchronously via `readabilityHandler` (or migrate to `swift-subprocess` post-1.0). Curated environment with explicit `PATH` (don't inherit empty PATH; don't inherit user shell that may shadow with Homebrew/Nix). Launch each invocation in its own process group; on cancel, `kill(-pgid, SIGTERM)` to catch grandchildren spawned by Mole's shell wrappers. Hard wall-clock timeout per invocation.

3. **Sparkle EdDSA signature verification breaks updates silently (P0)** — never re-zip artifacts after `generate_appcast` ran; `SUPublicEDKey` must be in `Info.plist` of every shipped version (no rotation possible after first public release); enable `SURequireSignedFeed` from day one; CI gate: `generate_appcast --verify-update` on freshly-built artifact must pass; EdDSA private key is single most-critical secret (decode in CI to umask-077 tempfile, delete after use).

4. **Full Disk Access UX traps user in a permission loop (P0)** — re-detect FDA on every popover open and on `applicationWillBecomeActive`; never cache `hasFDA = true`; document the kill-and-relaunch quirk in onboarding (TCC entitlements evaluated on process spawn); detect via "attempt + catch" probe of a known-protected file, NOT by reading TCC.db; surface clear "FDA = Granted/Denied" diagnostic. Disable destructive actions with inline explanation when denied; gracefully degrade `stats` (some metrics still work).

5. **Destructive operations have no undo affordance (P0)** — **default delete strategy: `NSFileManager.trashItem`, NOT `rm`**, even though Mole itself uses `rm`. This means MoleBar runs deletions in Swift using paths discovered via `mole --dry-run`, rather than calling `mole clean -y` directly. Snapshot deletion plan at confirmation; abort if file modified in last 60s. Power-user toggle still logs every deletion to JSONL (second-best undo). Vary confirmation wording across categories to defeat muscle-memory click-through. Never auto-execute scheduled runs without explicit opt-in.

**P0-if-exploited:** **Signing keys / secrets leak through CI** — never use `pull_request_target` for signed builds; use GitHub Secrets + `add-mask`; store notarytool credentials in temp keychain via `notarytool store-credentials`; enable Push Protection on the repo; audit CI logs for first 5 releases. EdDSA key leak = project-restart event (recovery may be impossible since existing users can't accept new keys without manual reinstall).

**Other notable pitfalls** (full detail in `PITFALLS.md`): MenuBarExtra documented bugs and Sonoma 14.6.1 popover crash (P1, mitigated by `.window` style + thin-shell architecture); battery drain from 1Hz polling and App Nap throttling stale-data confusion (P1); launchd unreliability across sleep/reboot (P1, mitigated by `SMAppService` + miss-detection on launch + "test schedule now" button); bundled mole drift / JSON schema break on auto-update (P1, mitigated by versioned schema validator + nightly upstream-CI + SHA256 allowlist); Homebrew Cask hash mismatch on artifact replacement (P1, fix: never replace artifacts, cut new patch version); telemetry destroys trust (P1, fix: zero outbound network beyond Sparkle appcast + explicit upstream-mole-release check, lint rule against unauthorized `URLSession`).

---

## Conflict Resolution

Three direct disagreements surfaced across the four research files. Each is resolved with explicit rationale; downstream consumers should treat these resolutions as the canonical position.

### Conflict 1: Subprocess Library — `Foundation.Process` vs `swift-subprocess` (P0 decision)

**The disagreement:**
- **STACK.md** recommends `Foundation.Process` for v1: swift-subprocess is at 0.4.0 (March 2026), 1.0 review concludes April 2026, docs warn minor releases may break API. Migrate post-1.0 in v1.x.
- **PITFALLS.md** recommends `swift-subprocess` for v1: `Foundation.Process` pipe-deadlock + zombie-children + grandchild-signal-propagation are a P0 ship-blocker.
- **ARCHITECTURE.md** uses `actor MoleClient` wrapping `Foundation.Process` in code examples — closer to STACK.

**Resolution: `Foundation.Process` for v1, wrapped in an `actor MoleClient` with battle-tested async draining and process-group cleanup. Plan migration to `swift-subprocess` post-1.0 in a v1.x maintenance release.**

**Rationale:**
1. PITFALLS' concern is **valid**, but framing it as a library choice misses the actual risk. The deadlock is caused by **synchronous `waitUntilExit` + `readDataToEndOfFile` patterns**, not by `Foundation.Process` itself. Both libraries deadlock if you misuse them; both work correctly with proper async draining.
2. swift-subprocess at 0.4.0 with 1.0 still in review is too volatile a foundation to ship a notarized public app on. STACK is right that "minor releases may break API" rules it out for v1.0 stability.
3. Community consensus (Apple Forums "Right way to asynchronously wait for a Process to terminate", TrozWare's Process→Subprocess migration guide) confirms a properly-wrapped `Foundation.Process` is production-grade today and is what every shipped Mac CLI-wrapper uses in 2026.
4. ARCHITECTURE's `actor MoleClient` pattern is exactly the wrapping that prevents PITFALLS' failure modes — `actor` boundary + `AsyncThrowingStream<Data, Error>` consumer + concurrent stdout/stderr drain + explicit `terminationHandler` + process-group launch.

**Spike to validate (Phase 1, before any feature work):**
- Stress test: 10 concurrent `mole` invocations + cancel each via process-group SIGTERM. Acceptance: zero zombie PIDs in Activity Monitor afterward; no deadlocks; cancel-during-large-stdout completes within 1s.
- Equivalent test against `jamf/Subprocess` (third-party, predates Apple's effort, maintained, used in production). If `jamf/Subprocess` passes the same suite with materially less code, **adopt it instead of hand-rolling on `Foundation.Process`** — it gets us swift-subprocess-style ergonomics today without the pre-1.0 risk.
- Document the chosen wrapper's contract in `MoleBarCore/Process/README.md` so the future swift-subprocess migration is a swap of one file.

**Migration trigger:** swift-subprocess 1.0 ships, has shipped one stable point release, and `jamf/Subprocess`'s OR our hand-rolled wrapper requires a non-trivial fix that would already be solved upstream. Until then: stay put.

### Conflict 2: Phase Ordering — Features-First vs Distribution-First

**The disagreement:**
- **STACK.md** sketches Phase 1 = CLI core, Phase 2 = MenuBarExtra UI.
- **PITFALLS.md** insists Phase 0 = Distribution Foundations (signing/Sparkle/CI pipeline) BEFORE any features, then Phase 1 = CLI orchestration.

**Resolution: PITFALLS' Phase 0 ordering wins. Build the distribution and signing pipeline FIRST, ship a 0.0.1 dummy release end-to-end, THEN start CLI orchestration.**

**Rationale:**
1. Three of the five P0 pitfalls (notarization, Sparkle EdDSA, secret leaks) are distribution-layer issues. Discovering them after features exist means a feature-frozen scramble at the worst possible moment (right before launch).
2. PROJECT.md's framing — "trust is the differentiator", "destructive operations on the user's machine", "public release" — argues for distribution as foundational, not as polish.
3. The Sparkle key in particular is **unrotatable post-launch**. Locking it in before any user installs MoleBar is a one-way door; getting it wrong means project-restart.
4. The dummy 0.0.1 release also serves as an end-to-end smoke test of the entire pipeline (build → sign → notarize → staple → DMG → upload → release → Sparkle check) against a clean Mac, which is harder to do once feature code is generating noise.
5. STACK does not actively oppose this ordering — it just doesn't articulate Phase 0 because its frame is "what to use" rather than "when to use it". They are compatible.

### Conflict 3: MenuBarExtra Style and Reliability

**The disagreement:**
- **STACK.md** acknowledges MenuBarExtra limitations and recommends bridging to AppKit when needed.
- **ARCHITECTURE.md** asserts `.menuBarExtraStyle(.window)` is mandatory because `.menu` blocks the runloop (FB13683957 + FB13683950).
- **PITFALLS.md** lists multiple MenuBarExtra bugs (FB11984872 no-programmatic-close, body-not-rerendered, Sonoma 14.6.1 popover crash) and recommends planning AppKit fallback from day one.

**Resolution: Use `MenuBarExtra` with `.menuBarExtraStyle(.window)` for v1. Architect the popover content as a thin shell (`PopoverRootView` with all state in external `@Observable` stores). If MenuBarExtra blockers surface in testing, swap the menu-bar host to `NSStatusItem` + `NSPopover` (or `lfroms/fluid-menu-bar-extra`) without rewriting the content.**

**Rationale:**
1. All three sources agree that `.menu` style is unusable for live data — make `.window` mandatory.
2. STACK and PITFALLS agree that MenuBarExtra has documented limitations; PITFALLS' "thin-shell so swap is cheap" is the right insurance policy.
3. ARCHITECTURE's existing pattern (state held in `@Observable` stores injected via `.environment`, not inside the MenuBarExtra body closure) **already implements the thin-shell discipline**. No additional architectural work.
4. Pre-emptively starting on AppKit `NSStatusItem` would burn budget on a problem that may not materialize. Test on macOS 14.0, 14.6.1, 14.x latest, and 15.x latest during Phase 5 (UI Foundations) UAT; only swap if blockers actually appear.
5. The `orchetect/MenuBarExtraAccess` SwiftPM library is the recommended bridge for the sub-problem of "open popover from a hotkey or scheduled-job notification" — add only when that need surfaces, not pre-emptively.

---

## Mole-Specific Risks

Three risks are unique to this project's "wrap a third-party CLI" posture and don't fit the generic stack/pitfall framing:

| Risk | Status | Mitigation |
|------|--------|------------|
| **Mole license confirmation** | Confirmed MIT (verified in PITFALLS #9 and PROJECT.md). Compatible with MoleBar's MIT. | Include `LICENSE-MOLE.txt` in `.app` bundle's `Contents/Resources/` for attribution. |
| **Mole JSON schema stability** | Mole has no documented JSON schema versioning policy. Schema break on upstream release breaks MoleBar's parser. | (1) Versioned `Codable` model layer in `MoleBarCore/Models/`. (2) On schema mismatch: fall back to "Compatibility issue: please update MoleBar" banner, never crash or run wrong action. (3) Nightly CI job that downloads latest upstream mole + runs MoleBar's test suite against it; opens issue/PR on mismatch. (4) SHA256 allowlist of known-tested upstream versions inside MoleBar binary. |
| **Mole version drift** | The "auto-update CLI separately" model decouples MoleBar releases from Mole releases. A schema-incompatible CLI can land without a corresponding parser update. | (1) Auto-update CLI is **opt-in, default-OFF for v1**. Default behavior: ship with a known-tested CLI version; update only when MoleBar itself updates. (2) When auto-update is on: check version against allowlist before swap; refuse unknown versions with explicit notification. (3) Always-vendored fallback copy in `Contents/Helpers/mole`. (4) "Compatibility matrix" page in README + in-app: which MoleBar versions support which Mole CLI versions. |

**Validate during Phase 1 spike:** confirm `mole stats --json --watch` actually exists with that flag combination. ARCHITECTURE flagged this as MEDIUM confidence. If it doesn't, fall back to polling at 2-3s with a single long-lived `Task` (still no per-tick subprocess if mole has a `--interval` flag). Watchdog the stream — restart subprocess on stderr `"fatal"` or stream silence > 30s.

---

## Implications for Roadmap

Based on the four research files plus the conflict resolutions above, the recommended phase structure is **8 phases** (or 7 if MoleBinaryUpdater slips to v1.1, which is a defensible call):

### Phase 0: Distribution Foundations (the "0.0.1" Phase)
**Rationale:** Three of five P0 pitfalls (notarization, Sparkle EdDSA, secret leak) are distribution-layer. Sparkle key is unrotatable post-launch. Build and validate the entire signing/notarizing/release/update pipeline end-to-end with a dummy 0.0.1 release **before any feature exists**.
**Delivers:** Apple Developer ID + temp-keychain CI flow + GitHub Actions release workflow + signed/notarized/stapled `.dmg` + Sparkle 2 wired with `SURequireSignedFeed` + first published GitHub Release + working `Sparkle update prompt` for a 0.0.1 → 0.0.2 round-trip in CI.
**Addresses:** Pitfalls #1, #3, #12. Stack: Hardened Runtime, `xcrun notarytool`, `xcrun stapler`, `create-dmg`, Sparkle 2.9.x, GitHub Actions, EdDSA, `SURequireSignedFeed`.
**Avoids:** Discovering signing/notarization/Sparkle bugs after features exist, when fix-cost is highest.

### Phase 1: CLI Orchestration Core + Spike Resolutions
**Rationale:** Subprocess deadlock (Pitfall #2), CLI version drift (Pitfall #9), and the Conflict #1 spike (Foundation.Process vs swift-subprocess vs jamf/Subprocess) all converge here. Without a stable subprocess layer, no feature can be built reliably.
**Delivers:** `MoleBarCore` SwiftPM module skeleton; `ProcessRunner` (with chosen wrapper from spike); `MoleResolver`; versioned `Codable` Models for mole JSON; `MoleClient` actor exposing `streamStats()` and `runAction(_:dryRun:)`; integration test target with a mock mole binary; nightly upstream-mole CI job.
**Addresses:** Pitfalls #2, #9. Stack: chosen subprocess wrapper, `os.Logger`, `AsyncStream`/`AsyncThrowingStream`. Architecture: `MoleClient` actor + `ProcessRunner` + `MoleResolver`.
**Avoids:** Pipe deadlock; zombie subprocesses; grandchild signal-propagation bugs; environment-inheritance breakage; schema-break crashes.
**Spike outcomes:** Subprocess wrapper choice locked in. `mole stats --json --watch` flag-combination behavior verified.

### Phase 2: UI Foundations + First End-to-End Vertical Slice
**Rationale:** First end-to-end demonstration that the whole architecture works (subprocess → store → SwiftUI). Validates the UI/Core split that PROJECT.md requires from day one. Forces the MenuBarExtra style / reliability decision (Conflict #3) onto real hardware.
**Delivers:** App target shell; `MoleBarUI` + `MoleBarStores` modules; `MenuBarExtra(...) { PopoverRootView() }.menuBarExtraStyle(.window)`; `StatsStore` consuming `MoleClient.streamStats()`; live CPU/RAM/disk in the menu-bar icon and popover; `os.Logger` instrumentation.
**Addresses:** Features #1 (live menu-bar metrics), D6 (health score widget if cheap to land here). Stack: SwiftUI, `MenuBarExtra` `.window` style, `@Observable` `@MainActor`, Swift Charts. Architecture: Stores + Patterns 1+2+6.
**Avoids:** Pitfall #5 (MenuBarExtra bugs — tested on multiple macOS versions in this phase).

### Phase 3: Permissions Onboarding (FDA)
**Rationale:** Required before any destructive feature ships. PITFALLS #4 frames FDA UX as "highest-cost UX failure" if botched. Build before cleaning, so the cleaning phase can assume FDA is granted-or-explicitly-degraded.
**Delivers:** `PermissionsProbe` in Core; `FDAOnboardingFlow` sheet in UI; deep-link to `x-apple.systempreferences:`; re-probe on `applicationWillBecomeActive`; "Diagnostic: FDA = Granted/Denied" indicator; degraded-mode messaging for cleaning buttons.
**Addresses:** Feature #9 (FDA onboarding). Stack: `NSWorkspace.shared.open(_:)`, "attempt + catch" probe pattern. Architecture: Pattern 5.
**Avoids:** Pitfall #4 (FDA permission loop).

### Phase 4: Cleaning Features (the Bulk of Feature Work)
**Rationale:** Five of the must-have features (#2 clean, #3 optimize, #4 purge, #5 installer, #7 dry-run preview, #8 op-log viewer, plus #12 notifications) all share the `Command → Confirm → Dry-Run → Execute → Log` state machine. Build the machine once, slot each feature into it.
**Delivers:** `ActionStore` state machine; `JobLog` JSONL writer; dry-run preview UI (per-item checkboxes, tree view); execution UI (progress, current file, bytes); confirmation-dialog variation by category; **`NSFileManager.trashItem`-based deletion (not `rm`)**; per-action use-counter and "skip preview after 3+ uses" power-user toggle; UserNotifications integration; operation-log viewer. Each cleaning subcommand (clean, optimize, purge, installer) gets a typed `MoleAction` enum case.
**Addresses:** Features #2, #3, #4, #5, #7, #8, #12. Stack: `UNUserNotificationCenter`, `NSFileManager`. Architecture: Patterns 3 + Pattern 1's invocation.
**Avoids:** Pitfalls #4 (FDA already handled), #7 (no-undo via trashItem).

### Phase 5: Disk Analyzer Window (the v2 Plug-In Validation)
**Rationale:** Forces the "second SwiftUI scene that links the same SwiftPM modules" pattern that v2's full-GUI app will rely on. PROJECT.md flags this as needing a window, not popover. Treemap implementation has a perf ceiling (Pitfall: ~500k decoded entries) — measure before adopting YMTreeMap.
**Delivers:** `Window("Disk Analyzer", id: "disk")` scene in `MoleBarApp.body`; `ScanStore` per-window; `Canvas`-based squarified treemap; tree view + top-N list; in-place delete via trashItem; "show in Finder" action; activation-policy juggle for window-open vs accessory.
**Addresses:** Feature #6. Stack: SwiftUI `Window` scene, `Canvas`, `@Environment(\.openWindow)`, optional YMTreeMap fallback. Architecture: Build-Order step 9; v2 plug-in seam validation.
**Avoids:** Pitfall (perf trap: lazy-load tree, virtualize SwiftUI list, batched MainActor updates every 500ms not per-file).

### Phase 6: Settings + Login Item + Scheduling
**Rationale:** Settings window is required for v1 (project-roots editor + whitelist editor are required for `mo purge` and `mo clean` to be customizable). Login-item via `SMAppService.mainApp` is trivial. Scheduling (PITFALLS #8) needs `SMAppService.agent` + LaunchAgent helper executable + miss-detection.
**Delivers:** SwiftUI `Settings` scene with General/Display/Cleaning/Notifications/Advanced tabs; `SettingsStore` with versioned Codable JSON in UserDefaults + `@AppStorage` for primitives; project-roots editor; whitelist editor; login-item toggle; `Scheduler` actor; `mole-scheduler-runner` helper executable bundled in `Contents/MacOS/`; LaunchAgent plist with explicit `EnvironmentVariables`; "Test schedule now" button; missed-run detection on app launch; pre-run notification ("Cleanup running in 60 seconds, click to cancel").
**Addresses:** Features #10, #11, D1. Stack: `SMAppService`, `Settings` scene, `@AppStorage`, UserDefaults JSON. Architecture: SettingsStore, Scheduler, LaunchAgent helper.
**Avoids:** Pitfall #8 (scheduler unreliability).

### Phase 7: MoleBinaryUpdater + Polish + v1.0 Launch
**Rationale:** CLI auto-update is independent of app self-update. Ship 1.0 with bundled mole only if Phase 7 slips; ship MoleBinaryUpdater in 1.1 as a defensible alternative. All v1 polish (live op-log streaming, process-watch alerts, Bluetooth battery, "recently freed" tally, right-click menu) lives here.
**Delivers:** `MoleBinaryUpdater` polling `tw93/mole` releases; SHA-256 verification against allowlist; staged write + atomic rename to `~/Library/Application Support/MoleBar/bin/mole`; opt-in default-off CLI auto-update toggle; v1.x differentiator polish (D5, D8, D9, D10, D11). Final v1.0 release with Homebrew Cask submission via `brew audit --cask --new`.
**Addresses:** Feature #13's auto-update half (the bundle-and-ship half is in Phase 0 + 1); D5, D8, D9, D10, D11. Stack: `URLSession`, SHA-256 verification, atomic `rename(2)`, Homebrew Cask. Architecture: MoleBinaryUpdater, dual update channels (Pattern 4).
**Avoids:** Pitfalls #9 (drift via allowlist), #10 (Cask hash mismatch via versioned URLs + brew audit), #11 (telemetry — none).

### Phase Ordering Rationale

- **Distribution before features** (Phase 0) because Sparkle EdDSA is unrotatable and three P0 pitfalls live here. PITFALLS' framing wins over STACK's implicit feature-first sketch.
- **Subprocess core before UI** (Phase 1 → 2) because the entire app is "stream subprocess output to SwiftUI"; no UI can ship without a non-deadlocking core.
- **FDA before cleaning** (Phase 3 → 4) because cleaning without FDA appears broken; building cleaning that gracefully degrades is materially harder than gating it on a working onboarding flow.
- **Cleaning before disk analyzer** (Phase 4 → 5) because cleaning validates the destructive-action pipeline; disk analyzer reuses it for in-place delete.
- **Disk analyzer before scheduling** (Phase 5 → 6) because the analyzer forces the multi-scene/UI-agnostic-core split that v2 will rely on; scheduling can be built on top of a stable architecture but does not itself drive architectural decisions.
- **Settings/login/scheduling together** (Phase 6) because they share SettingsStore, the launchd helper executable, and the SMAppService API surface; building them in isolation duplicates work.
- **MoleBinaryUpdater last** (Phase 7) because it's optional for v1.0 — bundling a known-good mole and shipping the auto-updater in v1.1 is fully defensible if Phase 7 slips.

### Research Flags

**Phases likely needing deeper research during planning** (recommend `/gsd-research-phase`):
- **Phase 1 (CLI Orchestration Core):** Subprocess wrapper choice spike (Conflict #1) — benchmarks of `Foundation.Process` actor wrap vs `jamf/Subprocess` vs hand-rolled async-drain. Mole JSON schema stability validation. `mole stats --json --watch` flag combination verification.
- **Phase 5 (Disk Analyzer Window):** Treemap rendering performance ceiling — `Canvas`-based squarified vs YMTreeMap at realistic file counts (500k–1M entries). Activation-policy juggle for window-open + popover-open simultaneity. Single-source flagged this as LOW confidence.
- **Phase 6 (Scheduling):** `SMAppService.agent` registration UX flow on macOS 14 + 15 (single user-visible System Settings prompt; verify dedup on re-register). LaunchAgent environment-variable behavior with bundled-vs-system mole.
- **Phase 7 (MoleBinaryUpdater):** Whether ad-hoc-signed binaries downloaded by the CLI auto-updater pass Gatekeeper's quarantine layer when invoked as subprocesses by an already-notarized parent. STACK flagged this as LOW confidence (community evidence says yes, deliberate end-to-end test warranted).

**Phases with standard / well-documented patterns** (skip dedicated research):
- **Phase 0 (Distribution Foundations):** Sparkle, notarytool, GitHub Actions Mac signing — well-documented, multiple reference implementations.
- **Phase 2 (UI Foundations):** SwiftUI `MenuBarExtra .window` + `@Observable` stores — Apple-documented, multiple reference apps (FontSwitch, etc.).
- **Phase 3 (FDA Onboarding):** "Attempt + catch" probe is the only sanctioned method; well-documented in Apple Forums.
- **Phase 4 (Cleaning Features):** `NSFileManager.trashItem` + state-machine pipeline — straightforward; the state machine itself is the bulk of the work.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Apple-official sources for Hardened Runtime, Observation, MenuBarExtra, SMAppService, BackgroundTasks (confirming iOS-only), Notarization. Sparkle official docs + recent (March 2026) release verified. swift-subprocess pre-1.0 status verified at Swift Forums. MEDIUM only on soft calls (project gen, DMG tool, SwiftLint). |
| Features | HIGH | Verified against `tw93/mole` README + repo `cmd/`+`lib/` listings on `main` (2026-04-27). Peer features verified against official sites/repos. Mission ("full Mole feature parity") cleanly maps to the inventory. |
| Architecture | HIGH on Apple frameworks (Process, MenuBarExtra, Sparkle, SMAppService); MEDIUM on `mole stats --json --watch` exact behavior (depends on what the upstream actually emits — Phase 1 spike). |
| Pitfalls | HIGH on signing/notarization, Sparkle, FDA, launchd (well-documented industry pitfalls); MEDIUM on MenuBarExtra bug specifics across macOS versions, Cask automation race conditions, and Mole-specific behavior at edge cases. |

**Overall confidence: HIGH** — the canonical-Mac-CLI-wrapper pattern is well-trodden and all four research files converge on the same architectural shape. The remaining MEDIUM-confidence items are localized and have explicit Phase 1/5/6/7 spikes attached.

### Gaps to Address

- **Subprocess wrapper choice (Conflict #1):** Resolved direction is `Foundation.Process` actor wrap, but Phase 1 spike must benchmark against `jamf/Subprocess` to confirm. Acceptance test in PITFALLS #2's "stress test 10 concurrent invocations + cancel".
- **Mole JSON schema stability:** No upstream guarantee. Mitigated by versioned `Codable` model layer + nightly upstream CI + SHA256 allowlist. Validate parser against current mole release in Phase 1; add CI gate.
- **`mole stats --json --watch` flag combination:** ARCHITECTURE assumed it exists. Verify in Phase 1 spike. Fallback: poll at 2-3s with single long-lived Task using `--interval` if available.
- **MenuBarExtra macOS-version-specific bugs:** Test on macOS 14.0, 14.6.1, 14.x latest, 15.x latest in Phase 2 UAT. If blockers appear, swap host to `NSStatusItem` + `NSPopover` (or `lfroms/fluid-menu-bar-extra`) — the thin-shell architecture means content code is unchanged.
- **Treemap perf ceiling:** Validate during Phase 5. `Canvas`-based squarified treemap is the v1 target; YMTreeMap is the documented fallback.
- **Ad-hoc-signed CLI binary + Gatekeeper:** End-to-end test in Phase 7. If Gatekeeper rejects, fall back to opt-in default-off CLI auto-update (which is the v1 default anyway).
- **Mole behaviour for `osascript … with administrator privileges`:** Spotlight reindex, network reset operations require sudo. Verify per-operation in Phase 4 — Mole's docs imply yes, concrete behavior should be confirmed before each subcommand ships in UI.
- **Entitlement set for the launched embedded `mole` binary:** STACK flagged as LOW confidence (single-source). Phase 1 should produce a notarization smoke-test that confirms the minimal entitlement set; start without `cs.disable-library-validation`, add only on demonstrated failure.

---

## Sources

### Primary (HIGH confidence — Apple / vendor-official)

**Apple platform docs:**
- [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime); [Configuring the hardened runtime](https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime)
- [Observation framework](https://developer.apple.com/documentation/Observation); [Migrating to @Observable](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro)
- [BGAppRefreshTask (confirms iOS/iPadOS/tvOS/Catalyst-only)](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask)
- [Swift Charts](https://developer.apple.com/documentation/charts) (confirms no built-in treemap)
- [Scheduling Timed Jobs (launchd)](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/ScheduledJobs.html)
- [TN2206 — macOS Code Signing in Depth](https://developer.apple.com/library/archive/technotes/tn2206/_index.html)
- [Apple Developer Forums — `--deep` Considered Harmful](https://forums.developer.apple.com/forums/thread/129980)
- [Apple Developer Forums — Right way to async wait for Process](https://forums.swift.org/t/right-way-to-asynchronously-wait-for-a-process-to-terminate/64036)
- [Apple Developer Forums — Reliable test for Full Disk Access](https://developer.apple.com/forums/thread/114452)
- [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra), [MenuBarExtraStyle](https://developer.apple.com/documentation/swiftui/menubarextrastyle)
- [SMAppService — Manage login items and background tasks](https://support.apple.com/guide/deployment/manage-login-items-background-tasks-mac-depdca572563/web)
- [UNUserNotificationCenter](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple Energy Efficiency Guide / App Nap](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html)

**Apple-confirmed bug reports:**
- [FB13683957 — MenuBarExtra .menu does not rerender body](https://github.com/feedback-assistant/reports/issues/477)
- [FB13683950 — MenuBarExtra (.menu) needs an open event](https://github.com/feedback-assistant/reports/issues/475)
- [FB11984872 — no programmatic close](https://github.com/feedback-assistant/reports/issues/383)

**Sparkle:**
- [Sparkle Documentation](https://sparkle-project.org/documentation/) (programmatic SwiftUI setup, EdDSA, signed feed)
- [Sparkle EdDSA migration / publishing](https://sparkle-project.org/documentation/eddsa-migration/); [Publishing an update](https://sparkle-project.org/documentation/publishing/)
- [Sparkle 2.x CHANGELOG](https://github.com/sparkle-project/Sparkle/blob/2.x/CHANGELOG)

**Swift Concurrency:**
- [SE-0406: AsyncStream backpressure (still pending)](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0406-async-stream-backpressure.md)
- [Swift 6.2 Subprocess introduction](https://www.swift.org/blog/swift-6.2-released/)
- [SF-0037: Subprocess 1.0 review](https://forums.swift.org/t/review-sf-0037-subprocess-1-0/86004)

**Tooling:**
- [Homebrew Cask Cookbook](https://docs.brew.sh/Cask-Cookbook); [`brew livecheck`](https://docs.brew.sh/Brew-Livecheck)
- [pointfreeco/swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing)
- [tw93/mole on GitHub](https://github.com/tw93/Mole) — verified MIT license; CLI is Shell+Go; full feature inventory verified 2026-04-27
- [tw93/mole `cmd/status/` metric files](https://github.com/tw93/Mole/tree/main/cmd/status)
- [tw93/mole `lib/clean/` modules](https://github.com/tw93/Mole/tree/main/lib/clean)

### Secondary (MEDIUM confidence — community / blog / synthesised)

- [Steipete — Showing Settings from macOS Menu Bar Items (2025)](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items)
- [Multi.app blog — Pushing the limits of NSStatusItem](https://multi.app/blog/pushing-the-limits-nsstatusitem)
- [TrozWare — Moving from Process to Subprocess (2025)](https://troz.net/post/2025/process-subprocess/)
- [Federico Terzi — Code-signing macOS apps with GitHub Actions](https://federicoterzi.com/blog/automatic-code-signing-and-notarization-for-macos-apps-using-github-actions/)
- [SwiftLee — OSLog and unified logging](https://www.avanderlee.com/debugging/oslog-unified-logging/)
- [Donny Wals — Modern logging with OSLog](https://www.donnywals.com/modern-logging-with-the-oslog-framework/)
- [BleepingSwift — @AppStorage vs UserDefaults vs SwiftData](https://bleepingswift.com/blog/appstorage-vs-userdefaults-vs-swiftdata)
- [Tuist — Why generate Xcode projects in 2025](https://tuist.dev/blog/2025/02/25/project-generation)
- [Jesse Squires — A simple fastlane setup for solo indie developers](https://www.jessesquires.com/blog/2024/01/22/fastlane-for-indies/)
- [Building a Modern Launch Agent on macOS (SMAppService)](https://gist.github.com/Matejkob/f8b1f6a7606f30777552372bab36c338)
- [orchetect/MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess); [lfroms/fluid-menu-bar-extra](https://github.com/lfroms/fluid-menu-bar-extra)
- [LanikSJ/homebrew-bump-cask](https://github.com/LanikSJ/homebrew-bump-cask)
- [exelban/Stats](https://github.com/exelban/stats); [iStat Menus](https://bjango.com/mac/istatmenus/); [CleanMyMac X Menu](https://macpaw.com/cleanmymac-x/cleanmymac-menu); [AlDente](https://github.com/AppHouseKitchen/AlDente-Charge-Limiter); [Maccy](https://github.com/p0deje/Maccy)
- [phalladar/MacDirStat](https://github.com/phalladar/MacDirStat) (reference SwiftUI disk analyzer with treemap)
- [yahoo/YMTreeMap](https://github.com/yahoo/YMTreeMap)
- [Eclectic Light Co. — Notarization: hardened runtime](https://eclecticlight.co/2021/01/07/notarization-the-hardened-runtime/)
- [rsms — macOS distribution code signing & notarization](https://gist.github.com/rsms/929c9c2fec231f0cf843a1a746a416f5)
- [Rainforest QA — Deep dive into TCC.db](https://www.rainforestqa.com/blog/macos-tcc-db-deep-dive)
- [launchd.info Tutorial](https://launchd.info/); [Joseph Spurrier — When Cron Jobs Disappear: macOS Sleep](https://www.josephspurrier.com/macos-sleep-cron); [Apple Dev Forums — launchd jobs at midnight](https://developer.apple.com/forums/thread/52369)
- [Sparkle Discussion #2174 — EdDSA verification failing](https://github.com/sparkle-project/Sparkle/discussions/2174); [Sparkle Discussion #2401 — improperly signed updates](https://github.com/sparkle-project/Sparkle/discussions/2401); [Sparkle Issue #1364 — keychain key storage](https://github.com/sparkle-project/Sparkle/issues/1364)
- [Homebrew Cask Issue #142136 — SHA256 mismatch](https://github.com/Homebrew/homebrew-cask/issues/142136); [Homebrew Discussion #6365 — autobump SHA mismatch](https://github.com/orgs/Homebrew/discussions/6365)
- [BetterDisplay — Sonoma 14.6.1 popover crash issue #3282](https://github.com/waydabber/BetterDisplay/issues/3282)
- [Fredric Cliver — Safe File Deletion on macOS](https://fredriccliver.medium.com/safe-file-deletion-on-macos-protect-yourself-from-rm-rf-mistakes-d6d3d8b3d540)
- [jamf/Subprocess](https://github.com/jamf/Subprocess); [swiftlang/swift-subprocess](https://github.com/swiftlang/swift-subprocess)
- [Swift Forums — frozen Process discussion](https://forums.swift.org/t/the-problem-with-a-frozen-process-in-swift-process-class/39579)

### Tertiary (LOW confidence — single-source / training-only — flagged for Phase-N validation)

- Exact entitlement set for launching the bundled `mole` binary — validate in **Phase 1** notarization smoke test
- Whether `osascript ... with administrator privileges` is sufficient for *every* destructive op (Spotlight reindex, network reset) — validate per-operation in **Phase 4**
- Whether ad-hoc-signed CLI binaries pass Gatekeeper when invoked by a notarized parent — validate end-to-end in **Phase 7**
- `Canvas`-based squarified treemap performance ceiling vs YMTreeMap at 100k+ entries — benchmark in **Phase 5**
- HackerNews — macOS telemetry privacy thread (informs the no-telemetry invariant; specific reactions are anecdotal but the pattern is consistent)

---

*Research synthesis for: MoleBar — public, MIT-licensed, notarized macOS 14+ menu-bar app wrapping `tw93/mole` CLI*
*Synthesized: 2026-04-27*
*Ready for roadmap: yes*
