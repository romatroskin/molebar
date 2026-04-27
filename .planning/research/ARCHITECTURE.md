# Architecture Research

**Domain:** Native macOS menu bar utility wrapping a third-party CLI (`tw93/mole`)
**Researched:** 2026-04-27
**Confidence:** HIGH (Apple frameworks, Sparkle, Process API), MEDIUM (mole-binary update mechanics; depends on what `mole stats --json --watch` actually emits — verify in Phase 1 spike)

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                       Presentation Layer (UI)                        │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │ MenuBarExtra     │  │ DiskAnalyzer     │  │ Settings Scene   │  │
│  │  (.window style) │  │  Window scene    │  │  (Window)        │  │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘  │
│           │                     │                     │             │
│           │   reads @Observable view-models / stores  │             │
│           ▼                     ▼                     ▼             │
├─────────────────────────────────────────────────────────────────────┤
│                       Application Layer (Stores)                     │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌──────────────────┐ │
│  │StatsStore  │ │ActionStore │ │ScanStore   │ │ SettingsStore    │ │
│  │@Observable │ │@Observable │ │@Observable │ │ @Observable      │ │
│  │@MainActor  │ │@MainActor  │ │@MainActor  │ │ @MainActor       │ │
│  └─────┬──────┘ └─────┬──────┘ └─────┬──────┘ └─────────┬────────┘ │
│        │              │              │                  │          │
├────────┼──────────────┼──────────────┼──────────────────┼──────────┤
│        │              │              │                  │          │
│        ▼              ▼              ▼                  ▼          │
│                       Domain / Core (UI-agnostic)                   │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    MoleBarCore (SwiftPM library)             │  │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────────────────┐ │  │
│  │  │ MoleClient │  │ Scheduler  │  │ Models (Codable structs)│ │  │
│  │  │  (actor)   │  │  (actor)   │  │  Stats, Action, Result  │ │  │
│  │  └─────┬──────┘  └─────┬──────┘  └────────────────────────┘ │  │
│  │        │               │                                      │ │
│  │  ┌─────▼──────┐  ┌─────▼──────┐  ┌─────────────────────────┐ │  │
│  │  │ProcessRunner│ │ JobLog     │  │ PermissionsProbe        │ │  │
│  │  │ AsyncStream │  │ (JSONL)   │  │ (FDA + Notifications)   │ │  │
│  │  └─────┬──────┘  └────────────┘  └─────────────────────────┘ │  │
│  └────────┼──────────────────────────────────────────────────────┘ │
├───────────┼─────────────────────────────────────────────────────────┤
│           ▼                                                         │
│                       System / External Boundary                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ ┌─────────────┐ │
│  │ mole binary │  │ launchd     │  │ TCC / FDA   │ │ UNNotifs    │ │
│  │ (subprocess)│  │ (SMAppSvc)  │  │ (System)    │ │ (System)    │ │
│  └─────────────┘  └─────────────┘  └─────────────┘ └─────────────┘ │
│  ┌─────────────┐  ┌─────────────┐                                   │
│  │ GitHub Rel. │  │ Sparkle 2   │                                   │
│  │(mole binary)│  │ (app self)  │                                   │
│  └─────────────┘  └─────────────┘                                   │
└─────────────────────────────────────────────────────────────────────┘

Direction of dependency: UI ──► Stores ──► Core ──► System
                                         (never reverse)
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| `MenuBarExtra` scene | Hosts the popover; owns root view; **uses `.window` style only** | `MenuBarExtra { PopoverRootView() }.menuBarExtraStyle(.window)` |
| `Window("Disk Analyzer", id: "disk")` | Single-instance disk-analyzer window opened via `openWindow(id:)` | SwiftUI `Window` scene (not `WindowGroup` — only one ever open) |
| `Settings { … }` scene | Standard preferences window | SwiftUI `Settings` scene (free `cmd+,` integration) |
| `*Store` (StatsStore, ActionStore, ScanStore, SettingsStore) | View-model layer; `@Observable @MainActor`; subscribes to Core streams; exposes UI-shaped state | `@Observable final class … { … }` |
| `MoleClient` (actor) | High-level API: `streamStats() -> AsyncStream<Stats>`, `runAction(_:dryRun:) -> AsyncStream<ActionEvent>`, `analyzeDisk(root:)` | `actor` wrapping `ProcessRunner` |
| `ProcessRunner` | Low-level: launches `mole` with args, returns `AsyncStream<Data>` of stdout lines + final exit code | `Foundation.Process` + `Pipe` + `FileHandle.readabilityHandler` → `AsyncStream<String>` |
| `MoleResolver` | Resolves the path to the bundled `mole` binary; handles updated copy in Application Support | Reads `Bundle.main.url(forAuxiliaryExecutable:)` first, prefers user copy if newer |
| `Scheduler` (actor) | Manages recurring cleanup runs; abstracts launchd vs in-app timer choice | Wraps `SMAppService.agent(plistName:)` |
| `Models` | `Codable` structs: `Stats`, `MoleAction`, `ActionEvent`, `ScanNode`, `JobLogEntry` | Plain Swift structs in `MoleBarCore` |
| `JobLog` | Append-only JSONL of every action (dry-run + real) for transparency UI | File at `~/Library/Application Support/MoleBar/jobs.jsonl` |
| `PermissionsProbe` | Checks Full Disk Access by attempting a known-protected read; opens `x-apple.systempreferences:` URL | Foundation `try Data(contentsOf: …TimeMachine.plist)` probe |
| `Updater` (Sparkle controller) | Wraps `SPUStandardUpdaterController` for the *app itself* | Sparkle 2 |
| `MoleBinaryUpdater` | Independently checks `tw93/mole` GitHub releases; downloads, verifies signature, atomically swaps the binary in `~/Library/Application Support/MoleBar/bin/mole` | Custom: `URLSession` + checksum + SHA verification |

## Recommended Project Structure

A **SwiftPM package + Xcode app target** is the recommended layout. The app target is thin — almost everything lives in SwiftPM modules so that a v2 full-GUI app target can link the same packages without duplication.

```
MoleBar/
├── Package.swift                    # Defines library targets below
├── App/                             # Xcode project (thin shell)
│   ├── MoleBar.xcodeproj
│   ├── MoleBarApp.swift             # @main App; wires scenes + DI
│   ├── Info.plist                   # LSUIElement=YES (no Dock icon)
│   ├── MoleBar.entitlements         # NOT sandboxed; hardened runtime
│   ├── Resources/
│   │   └── Mole/mole                # Bundled mole binary (signed at build time)
│   └── LaunchAgent/
│       └── com.molebar.scheduler.plist   # Template for SMAppService
│
├── Sources/
│   ├── MoleBarCore/                 # UI-AGNOSTIC. No SwiftUI imports.
│   │   ├── Models/                  # Stats, MoleAction, ActionEvent, ScanNode
│   │   ├── Process/                 # ProcessRunner, MoleResolver
│   │   ├── Client/                  # MoleClient (actor) — public API
│   │   ├── Scheduler/               # Scheduler (actor), LaunchAgentInstaller
│   │   ├── Permissions/             # PermissionsProbe, FDAStatus
│   │   ├── Logging/                 # JobLog, OSLog wrappers
│   │   └── Updates/                 # MoleBinaryUpdater (NOT app updater)
│   │
│   ├── MoleBarStores/               # @Observable view-models. Imports Core only.
│   │   ├── StatsStore.swift
│   │   ├── ActionStore.swift
│   │   ├── ScanStore.swift
│   │   └── SettingsStore.swift
│   │
│   ├── MoleBarUI/                   # SwiftUI views. Imports Stores + Core.
│   │   ├── MenuBar/                 # PopoverRootView, StatsRow, ActionMenu
│   │   ├── DiskAnalyzer/            # DiskAnalyzerWindow, TreemapView
│   │   ├── Settings/                # SettingsView, ScheduleEditor
│   │   ├── Permissions/             # FDAOnboardingFlow
│   │   └── Components/              # Shared views (DryRunDialog, Toast)
│   │
│   └── MoleBarUpdater/              # Sparkle wrapper (separated for testability)
│       └── AppUpdater.swift
│
├── Tests/
│   ├── MoleBarCoreTests/            # Most tests live here — no UI dependency
│   ├── MoleBarStoresTests/
│   └── MoleBarUITests/              # Snapshot tests if any
│
├── Tools/
│   ├── sign-mole.sh                 # Re-sign bundled mole during build
│   └── notarize.sh
│
└── Scripts/
    └── generate-appcast.sh          # Sparkle release helper
```

### Structure Rationale

- **`MoleBarCore` first / no SwiftUI**: Forces the UI/core split that PROJECT.md requires. v2's full-GUI app simply links this package and writes new SwiftUI surfaces. If SwiftUI types leak into Core, that contract breaks silently — keep import discipline enforced by *not even importing SwiftUI* in Core's targets.
- **`MoleBarStores` separate from `MoleBarUI`**: Stores are testable without launching SwiftUI. They are also the natural place to keep `@Observable` types so multiple UI surfaces (popover, disk window, future GUI) can share state — instantiate stores once in `MoleBarApp` and inject via `.environment(_:)`.
- **App target is thin**: Just `@main App`, scene wiring, entitlements, Info.plist, and the bundled `mole` binary. Most code reviews touch only the SwiftPM modules.
- **Bundled `mole` lives in `Resources/Mole/mole`** but is loaded via `Bundle.main.url(forAuxiliaryExecutable:)`. (See "Where the bundled mole binary lives" below — `Contents/MacOS/` is also valid; `Helpers/` is the cleanest convention.)
- **`Tools/` & `Scripts/`**: Build-phase helpers. `sign-mole.sh` runs after copy in the Xcode build phase to ensure the bundled binary inherits hardened-runtime + timestamp signing for notarization.

## Architectural Patterns

### Pattern 1: Process Orchestration as an Actor + AsyncStream

**What:** All subprocess interaction lives in one `actor MoleClient` that exposes only `AsyncStream`/`async throws` APIs. UI never touches `Process` directly.

**When to use:** Always. This is the load-bearing boundary of the whole app.

**Trade-offs:**
- (+) Single place to enforce: kill orphan processes on app quit, serialize destructive operations, mock for tests.
- (+) `actor` makes thread-safety free — no shared mutable state between concurrent action runs.
- (−) `Foundation.Process` predates Swift Concurrency. You must adapt `FileHandle.readabilityHandler` callbacks into `AsyncStream` manually (or adopt `swift-subprocess` once it's released; jamf/Subprocess works today). See PITFALLS.

**Example:**
```swift
public actor MoleClient {
    private let runner: ProcessRunner
    private let resolver: MoleResolver

    public func streamStats() -> AsyncThrowingStream<Stats, Error> {
        runner.lines(executable: resolver.binaryURL,
                     args: ["stats", "--json", "--watch"])
            .compactMap { line in try? JSONDecoder().decode(Stats.self, from: Data(line.utf8)) }
    }

    public func runAction(_ action: MoleAction, dryRun: Bool)
        -> AsyncThrowingStream<ActionEvent, Error>
    {
        var args = action.cliArgs
        if dryRun { args.append("--dry-run") }
        args.append("--json")
        return runner.lines(executable: resolver.binaryURL, args: args)
            .compactMap { try? JSONDecoder().decode(ActionEvent.self, from: $0.data(using: .utf8)!) }
    }
}
```

### Pattern 2: `@Observable` Stores Bridging AsyncStream → SwiftUI

**What:** Each domain has a `@Observable @MainActor` store. The store owns one `Task` that consumes the AsyncStream from `MoleClient` and writes to its observable properties. Views read those properties directly.

**When to use:** Always for any data that updates over time (stats, action progress, scan results).

**Trade-offs:**
- (+) macOS 14+ `@Observable` + `@MainActor` gives free fine-grained invalidation — only views reading the changed property re-render.
- (+) Single source of truth per domain; no `@Published` boilerplate.
- (−) The store must explicitly cancel its consumer `Task` on `deinit` / popover close to avoid leaking subprocess handles.

**Example:**
```swift
@MainActor @Observable
public final class StatsStore {
    public private(set) var current: Stats?
    public private(set) var error: String?
    private var task: Task<Void, Never>?
    private let client: MoleClient

    public init(client: MoleClient) { self.client = client }

    public func start() {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await stats in await client.streamStats() {
                    self.current = stats   // MainActor — view re-renders
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    public func stop() { task?.cancel(); task = nil }
}
```

### Pattern 3: Command → Confirm → Dry-Run → Execute → Log Pipeline

**What:** Every destructive action passes through a fixed state machine in `ActionStore`:
`.idle → .confirming → .dryRunning → .previewReady → .executing → .completed/.failed → log`.
The UI binds to the state; transitions are driven by user input *and* AsyncStream events.

**When to use:** All `clean`, `purge`, `optimize`, `installer-leftovers` commands.

**Trade-offs:**
- (+) Trivially testable — feed mock events, assert state.
- (+) The "skip preview after 3 uses" power-user toggle becomes a single guard at the `.confirming → .dryRunning` transition.
- (+) Every state change appends a `JobLogEntry` to JSONL — automatic audit log.
- (−) State machines look like overkill for a button. They aren't. Destructive UI without one always grows bugs.

**Example:**
```swift
@MainActor @Observable
public final class ActionStore {
    public enum Phase {
        case idle, confirming(MoleAction)
        case dryRunning(MoleAction, progress: Double)
        case previewReady(MoleAction, plan: ActionPlan)
        case executing(MoleAction, progress: Double)
        case completed(ActionResult), failed(ActionError)
    }
    public private(set) var phase: Phase = .idle
    // …transitions consume events from MoleClient.runAction(_:)
}
```

### Pattern 4: Dual Update Channels (App via Sparkle, mole via Custom Updater)

**What:** Two completely separate update mechanisms:
1. **App self-update** — Sparkle 2 with `SPUStandardUpdaterController`, signed appcast on GitHub Pages or Releases.
2. **mole-binary update** — `MoleBinaryUpdater` polls `https://api.github.com/repos/tw93/mole/releases/latest` once per launch + once per day. Downloads to `~/Library/Application Support/MoleBar/bin/mole.staged`, verifies SHA-256 from release notes, atomically renames to `mole` (or quarantines bundled copy if checksum fails).

**When to use:** Required by PROJECT.md ("Bundle mole binary, auto-update separately").

**Trade-offs:**
- (+) Sparkle alone can't do file-level updates inside the bundle (verified — Sparkle 2 updates whole bundles only; "external bundle updates" is for *other* Sparkle-enabled apps, not arbitrary helper binaries).
- (+) `MoleResolver` always prefers the user-mutable copy in Application Support over the bundled fallback — fresh-install and updated-binary cases both work.
- (−) Two update paths = two trust roots. The mole binary updater MUST verify checksums; Apple's notarization doesn't cover binaries you fetched at runtime. Bundle a known-good fallback.

**Example:**
```swift
struct MoleResolver {
    var binaryURL: URL {
        let userCopy = appSupport.appendingPathComponent("bin/mole")
        if FileManager.default.isExecutableFile(atPath: userCopy.path) { return userCopy }
        return Bundle.main.url(forAuxiliaryExecutable: "mole")!  // bundled fallback
    }
}
```

### Pattern 5: Permissions Probe + Onboarding Sheet

**What:** On first launch and on every menu open, `PermissionsProbe.fullDiskAccess` attempts a no-op read of a known FDA-protected file (`/Library/Preferences/com.apple.TimeMachine.plist`). Result: `.granted | .denied | .undetermined`. If denied, a sheet presents a Continue button that opens
`x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles` and a copy-pastable explanation.

**When to use:** Before any `clean`, `purge`, `optimize` action; gracefully degrade `stats` (some metrics work without FDA).

**Trade-offs:**
- (+) No private API needed. Apple recommends "attempt and handle the error" exactly.
- (+) Each menu open re-probes — no stale "denied" state.
- (−) The probe itself can be slow on first call (~50ms). Cache result for 60s.

**Example:**
```swift
enum FDAStatus { case granted, denied, undetermined }
struct PermissionsProbe {
    static func fullDiskAccess() -> FDAStatus {
        let url = URL(fileURLWithPath: "/Library/Preferences/com.apple.TimeMachine.plist")
        do { _ = try Data(contentsOf: url); return .granted }
        catch { return .denied }
    }
    static func openSystemSettings() {
        let url = URL(string:
          "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }
}
```

## Data Flow

### Live Stats Flow (the hot path)

```
mole stats --json --watch  (subprocess, stdout)
    │
    ▼  newline-delimited JSON, ~1Hz
ProcessRunner.lines(...)  →  AsyncStream<String>
    │
    ▼  decode each line
MoleClient.streamStats()  →  AsyncThrowingStream<Stats>
    │
    ▼  consumed by Task in store
StatsStore.current  (@Observable property, @MainActor)
    │
    ▼  observed by views
PopoverRootView / StatusItemBadge  →  draws icon, popover charts
```

**Decision: stream `--watch`, do NOT poll-and-decode each second.**
- One subprocess per app session vs ~3,600 subprocess spawns/hour. Spawning `mole` and re-reading its config per second is wasteful and noisy in logs.
- Verify in Phase 1 spike that `mole stats --json --watch` actually exists. If it doesn't, fall back to polling at 2-3s with a single long-lived `Task` (still no per-tick subprocess if there's a `--interval` flag).
- **MEDIUM confidence** until the spike confirms upstream behavior.

**Back-pressure & icon redraw:**
- `AsyncStream` does not natively support back-pressure (verified: SE-0406 still pending). The mole CLI is the producer at ~1Hz, which is well under any reasonable consumer rate, so back-pressure is not a real concern here.
- For the **menu-bar status item icon**, throttle redraws to `max 2 Hz` using a small debouncer in `StatusItemBadge` — even if mole bursts data, NSStatusItem image swaps cause visible flicker if updated faster.
- Use `Task.yield()` in the consumer loop to keep the MainActor responsive.
- If `MenuBarExtra` is configured with `.menu` style, **the runloop blocks while the menu is open and Observation does not fire** — confirmed Apple bug FB13683957/FB13683950. **Always use `.menuBarExtraStyle(.window)`** for live content.

### Action Flow (destructive command)

```
User taps "Clean Caches" in popover
    │
    ▼  ActionStore.confirm(action)
@Observable phase: .confirming(action)
    │
    ▼  ConfirmDialog displayed (or skipped if power-user threshold met)
    ▼  user confirms
ActionStore.runDryRun(action)
    │
    ▼  MoleClient.runAction(action, dryRun: true)
    ▼  subprocess: mole clean caches --dry-run --json
    ▼  AsyncStream<ActionEvent> → progress, planned-deletions
@Observable phase: .dryRunning → .previewReady(plan)
    │
    ▼  PreviewSheet shows "Will free 2.4 GB / 1,231 files"
    ▼  user taps Execute
ActionStore.execute(action)
    │
    ▼  MoleClient.runAction(action, dryRun: false)
    ▼  subprocess: mole clean caches --json
    ▼  AsyncStream<ActionEvent> → progress events
@Observable phase: .executing(progress: 0.4) → .completed(result)
    │
    ▼  fan-out
    ├──► JobLog.append(JobLogEntry)        (JSONL on disk)
    ├──► UNUserNotificationCenter.add(...)  (toast + system notif)
    └──► Toast banner inside popover (in-app feedback)
```

**Exit-code propagation:** `ProcessRunner` always emits a final `ActionEvent.exit(code: Int32, stderr: String)` at stream completion. `ActionStore` maps non-zero exits to `.failed(.exitNonZero(code, stderr))`. The UI surfaces stderr verbatim (it's user-facing — mole writes useful messages there).

### State Management Topology

```
                     ┌────────────────┐
                     │  MoleBarApp    │   (composition root)
                     │  @main App     │
                     └────────┬───────┘
                              │  injects ONE shared instance of each store
                              ▼
              ┌───────────┬───────────┬───────────┬─────────────┐
              ▼           ▼           ▼           ▼             ▼
        StatsStore  ActionStore  ScanStore  SettingsStore  AppUpdater
            │           │           │           │             │
            └─────────┬─┴───────────┴───────────┴─────────────┘
                      │  via .environment(_:) on each scene
                      ▼
        ┌─────────────┼─────────────┐
        ▼             ▼             ▼
  MenuBarExtra  Window("disk")   Settings
   popover      analyzer         scene
```

- **Scope:** `StatsStore`, `ActionStore`, `SettingsStore` are **app-singleton**. `ScanStore` is **per-window** (each disk-analyzer window has its own scan).
- **Combine:** **Don't.** Use AsyncStream + `for try await` everywhere. macOS 14+ has no Combine-only APIs Swift Concurrency can't replace, and mixing the two is a known footgun (Apple Forums). The only place Combine sneaks in is `Sparkle`'s legacy KVO bridging, which is internal to `MoleBarUpdater`.

### Settings Storage & Migration

```
SettingsStore (@Observable)
    │
    ▼ writes / reads via property wrappers
@AppStorage("settings.statsDisplay")  (raw types only)
@AppStorage("settings.powerUserThreshold")
    │
    ▼ for complex types (schedule list, FDA-onboarding state)
UserDefaults.standard / Codable JSON in a single key
"settings.v1.payload"  →  encoded { schedules: […], … }
    │
    ▼ migration on launch
SettingsMigrator.migrateIfNeeded(from: .v0, to: .v1)
```

- **Use `@AppStorage` only for primitives that drive views directly** — toggles, raw-int thresholds, enum rawValues.
- **Composite settings** (schedule list, per-action use-counts for the "skip preview after 3 uses" toggle) live in a single `Settings` Codable struct stored as JSON under one UserDefaults key with a version field.
- **Don't reach for SwiftData.** It's overkill for settings and adds a SQLite dependency that complicates uninstall semantics. SwiftData would be appropriate only if scan results need long-term persistence (they don't — re-scan is cheap).

### Scheduling: launchd LaunchAgent (via `SMAppService`), not in-app `Timer`

```
User configures: "Run cleanup every Sunday 3am"
    │
    ▼
Scheduler.install(schedule)
    │
    ▼  writes Contents/Library/LaunchAgents/com.molebar.scheduler.plist
    ▼  with StartCalendarInterval { Weekday=0 Hour=3 }
    ▼
SMAppService.agent(plistName: "com.molebar.scheduler.plist").register()
    │
    ▼  user is shown System Settings → Login Items toggle
    │
    ▼  launchd fires at scheduled time, even if MoleBar is quit
    ▼  invokes a small helper: mole-scheduler-runner
    ▼  which → exec mole clean […] --json → posts UNUserNotification
```

**Why launchd over in-app `Timer`:**
- (+) Survives app quit, login/logout, sleep/wake — `Timer` cannot.
- (+) `StartCalendarInterval` handles missed runs after sleep more gracefully than ad-hoc reconciliation in app code.
- (+) Modern API: `SMAppService` (macOS 13+) handles registration + the user's Login Items toggle without legacy `SMJobBless` complexity.
- (−) Requires a separate tiny helper executable (`mole-scheduler-runner`) bundled in `Contents/MacOS/` that just shells out to `mole` and posts a notification. Trade-off worth taking.
- (−) Scheduling user gets one System Settings prompt the first time they enable a schedule. Onboard for it.

**App-quit / sleep / restart semantics:**
- Stats / actions / scans are **in-process Tasks**. Cancelled on app quit. No persistence needed mid-flight.
- Schedules are **out-of-process via launchd**. Persist as long as the LaunchAgent is registered, regardless of app lifecycle.
- Use `SwiftUI Scene` `@Environment(\.scenePhase)` to detect background/quit and tear down `streamStats()` to release the subprocess.

### Notifications

- **`UNUserNotificationCenter`** for cleanup-finished alerts. Works for unsandboxed menu-bar apps with `LSUIElement = YES` — verified that it requires no special entitlement when not sandboxed; the app must request authorization on first use.
- Set `NSUserNotificationsUsageDescription` (informally, since Apple doesn't strictly require it for unsandboxed apps but DT requires plain English in the prompt).
- The launchd-spawned helper also calls `UNUserNotificationCenter` directly — it has its own bundle identity and posts notifications without needing the main app to be running.

### Where the bundled `mole` binary lives

**Recommendation: `Contents/Helpers/mole`** in the .app bundle.

- `Contents/MacOS/` is technically valid but conventionally for the main executable + small helpers (e.g., the scheduler-runner). Putting a third-party binary there muddies the bundle's identity.
- `Contents/Resources/` is **wrong** for executables — Apple's bundle guidelines explicitly call this out, and `--deep` signing has known issues with executables outside expected locations.
- `Contents/Helpers/mole` is the cleanest convention. Access via `Bundle.main.url(forAuxiliaryExecutable: "mole")`.

**Build phase pipeline (Xcode "Run Script" after Copy Bundle Resources):**
1. Copy `Resources/Mole/mole` → `$BUILT_PRODUCTS_DIR/MoleBar.app/Contents/Helpers/mole`
2. `codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$DST/Contents/Helpers/mole"`
3. Main app signing happens last (bottom-up signing rule).

**Updater swap mechanics:**
- `MoleBinaryUpdater` writes new binary to `~/Library/Application Support/MoleBar/bin/mole.staged`.
- Verifies SHA-256 from `tw93/mole` GitHub release notes (mole's release process publishes checksums).
- `chmod 755`, then atomic `rename(2)` to `~/Library/Application Support/MoleBar/bin/mole`.
- `MoleResolver` prefers user-copy when present and executable; falls back to bundled.
- On the **next** subprocess spawn, the new binary is used. Long-running streams (`stats --watch`) keep using the old PID until the user closes the popover and reopens it. Acceptable.

### Permissions: Full Disk Access UX

```
App launch
    │
    ▼  PermissionsProbe.fullDiskAccess()  →  .denied
    ▼
FDAOnboardingFlow sheet:
  "MoleBar needs Full Disk Access to clean caches and find leftovers."
  [Open System Settings] [Skip for now]
    │
    ▼  PermissionsProbe.openSystemSettings()
    ▼  user grants in Privacy & Security → Full Disk Access
    ▼
On every popover open, re-probe FDA. When it flips to .granted, dismiss banner.

Fallback when denied:
  - stats: degraded (some metrics unavailable; show banner)
  - clean / purge / optimize: disabled buttons with inline explanation
  - disk analyzer: works on user's home dir without FDA; degraded for /Library
```

**Don't:**
- Don't try to detect FDA by reading `TCC.db` — that path is undocumented and Apple-recommends-against. The "attempt + handle error" probe is the only sanctioned method.
- Don't quit-and-relaunch after FDA is granted. Modern macOS revokes-and-reinstates FDA at the OS level without an app restart.

## Build Order

This is the dependency graph. Build modules in this order; each unlocks the next.

| Order | Module | Why first | Unlocks |
|-------|--------|-----------|---------|
| 1 | `MoleBarCore: ProcessRunner` + `MoleResolver` | Everything depends on being able to run `mole` and parse output | All other Core; integration test target |
| 2 | `MoleBarCore: Models` (`Stats`, `MoleAction`, `ActionEvent`) | Can't write the client without target types | `MoleClient` |
| 3 | `MoleBarCore: MoleClient` (actor) | Public Core API | All stores |
| 4 | `MoleBarStores: StatsStore` | Smallest, demonstrates AsyncStream → @Observable bridge | UI proof-of-life |
| 5 | App target shell + `MenuBarExtra` (`.window` style) + popover skeleton | First end-to-end demo: real stats in the menu bar | Validates the entire UI/Core split |
| 6 | `MoleBarCore: PermissionsProbe` + `MoleBarUI: FDAOnboardingFlow` | Required before any destructive action ships | Action work |
| 7 | `MoleBarStores: ActionStore` + `MoleBarUI: dry-run/confirm/execute UI` | The bulk of feature work | All cleaning features |
| 8 | `MoleBarCore: JobLog` | Audit log + transparency view | Trust signal |
| 9 | `Window("disk", id:)` scene + `MoleBarStores: ScanStore` + treemap | First non-popover surface — validates plug-in point for v2 | Future v2 full GUI |
| 10 | `MoleBarCore: Scheduler` + LaunchAgent helper executable | Recurring cleanups | Schedule UX |
| 11 | `MoleBarUpdater` (Sparkle integration) | Last — only matters near release | Distribution |
| 12 | `MoleBarCore: MoleBinaryUpdater` | Independent of app updater; can ship in 1.1 if 1.0 ships with bundled mole only | Self-updating mole |

**Key milestones from this order:**
- After step 5: end-to-end "live stats in menu bar" — validates architecture.
- After step 9: validates the multi-scene plug-in point that v2 depends on.
- After step 12: release-ready.

### Where Disk Analyzer Slots In (and v2 plug-in points)

- **Same app target.** Add a second `Scene` (`Window`, not `WindowGroup`) to `MoleBarApp`'s `body`.
- The scene injects `ScanStore` (one per window) but reads the same `MoleClient` and `SettingsStore` from the environment.
- Trigger: `Button("Open Disk Analyzer")` in the popover calls `@Environment(\.openWindow)` with id `"disk"`.
- This proves the **v2 plug-in seam**: a future full-GUI app target re-uses `MoleBarCore` + `MoleBarStores` and replaces the popover with a full window scene. No core rewrites.

**v2 plug-in points (already implied by this architecture):**

| v2 feature | Where it slots in | Cost |
|-----------|------------------|------|
| Full GUI app target (separate `WindowGroup`) | New scene in `MoleBarApp`, or new app target linking same SwiftPM modules | LOW — modules are already UI-agnostic |
| App uninstaller | New `MoleAction.uninstallApp(...)` + a drag-target view in `MoleBarUI`. ActionStore state machine is reused as-is. | MEDIUM — bulk of cost is the leftover-diff UI |
| New mole subcommands as they ship upstream | Add new cases to `MoleAction` enum + corresponding UI buttons | LOW — pipeline is generic |
| Cross-device sync of settings/schedules | Replace `@AppStorage` with iCloud KVS in `SettingsStore` | LOW |

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| Single user (default) | Current architecture is correct. No changes needed. |
| Power user with 10+ schedules | LaunchAgent supports this fine; ensure `Scheduler.install` is idempotent and dedupes plist entries by ID. |
| Long-running scans on slow disks (millions of files) | Move tree-build off MainActor: use a background `Task` in `ScanStore` that emits batched updates (every 500ms) to MainActor, not per-file. |
| Continuous-stream (`stats --watch`) leaves running for days | Verify mole's stream stays healthy — add a watchdog that restarts the subprocess on stderr "fatal" or stream silence > 30s. |

### Scaling Priorities

1. **First bottleneck (most likely): MainActor flooding from per-file scan updates.** Fix: batch + throttle in `ScanStore`. Cost: trivial.
2. **Second bottleneck: zombie subprocesses on app crash.** Fix: app's `applicationWillTerminate` + a sentinel file that a background sweep checks on launch (kill any orphan `mole` PIDs in `~/Library/Application Support/MoleBar/pids/`). Sparkle's relaunch flow specifically needs this — it spawns the new app, which would otherwise leave the old `mole` running.
3. **Third bottleneck: notification spam during recurring schedules.** Fix: notification grouping + summary mode in `SettingsStore`.

## Anti-Patterns

### Anti-Pattern 1: Putting `Process` in the View Layer

**What people do:** Spawn `Process()` directly inside a SwiftUI view's `.task { … }` modifier because "it's quick."
**Why it's wrong:** Subprocess lifetime now tied to view lifetime; cancellation, error propagation, and testability all break. Multiple popover opens spawn duplicate `mole` subprocesses.
**Do this instead:** Always go View → Store → MoleClient (actor). The view holds no subprocess handle.

### Anti-Pattern 2: Using `MenuBarExtraStyle.menu` for Live Content

**What people do:** Use the default `.menu` style because it's the SwiftUI default and looks cleaner for simple lists.
**Why it's wrong:** Confirmed Apple bug (FB13683957/FB13683950): `.menu` style **blocks the runloop while the menu is open**. Timers don't fire, `@Observable` invalidations don't trigger view updates, `onReceive` never delivers. The menu is essentially a snapshot, not a live view.
**Do this instead:** Always use `.menuBarExtraStyle(.window)` for any popover that contains live data. Trade-off: slightly more visual customization needed (window has no menu chrome). Worth it.

### Anti-Pattern 3: Mixing AsyncStream and Combine

**What people do:** Some places use `Publisher`, others use `AsyncStream`, glued together with `.values` or `.eraseToAnyPublisher()`.
**Why it's wrong:** Cancellation semantics differ subtly. Memory leaks via captured Combine subscriptions. Doubles the test-mock surface area.
**Do this instead:** Pick AsyncStream + `for try await` everywhere outside Sparkle. Sparkle's KVO is encapsulated inside `MoleBarUpdater` and never leaks Combine to the rest of the codebase.

### Anti-Pattern 4: Updating the Bundled mole Binary in Place

**What people do:** Try to overwrite `MoleBar.app/Contents/Helpers/mole` from a running instance.
**Why it's wrong:** Mutates the .app bundle → invalidates the code signature → Gatekeeper rejects on next launch. Also fails on read-only filesystems / when app lives in `/Applications`.
**Do this instead:** Write updated binary to `~/Library/Application Support/MoleBar/bin/mole`. `MoleResolver` prefers it. Bundle stays signed.

### Anti-Pattern 5: Polling FDA Status from a Cached Bool

**What people do:** Cache `hasFDA = true` in `SettingsStore` once granted, never re-check.
**Why it's wrong:** User can revoke FDA in System Settings without restarting the app. Cached `true` causes confusing "Operation not permitted" errors.
**Do this instead:** Re-probe on every popover open (the cost is one file read; ~50ms first, fast cache thereafter); cache for 60s only.

### Anti-Pattern 6: Synchronous Decoding of Stats on the Main Thread

**What people do:** `JSONDecoder().decode(Stats.self, from: line)` inside the MainActor consumer.
**Why it's wrong:** At 1Hz it's fine; at higher rates (a chatty mole subcommand) it can stutter the popover.
**Do this instead:** Decode in `ProcessRunner` / `MoleClient` (actor) and hand the typed value to the MainActor store. Cost is trivial; future-proofs against firehose subcommands.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| `mole` CLI subprocess | `Foundation.Process` + `Pipe` + `AsyncStream` adapter | Always go through `MoleClient` actor |
| `tw93/mole` GitHub Releases API | `URLSession` + `Codable` decoding | Verify SHA-256 from release notes; rate-limit to once-per-day |
| Sparkle 2 update server (your server) | `SPUStandardUpdaterController` auto-handles it | Generated appcast on GitHub Pages; signed with EdDSA |
| TCC / Full Disk Access | "Attempt + handle error" probe of protected file | No private API; no sanctioned status query |
| `UNUserNotificationCenter` | Standard request-auth + post pattern | No special entitlement when unsandboxed |
| `SMAppService` (LaunchAgent) | `agent(plistName:).register()` | macOS 13+ API; user sees a Login Items entry |
| `x-apple.systempreferences:` URL scheme | `NSWorkspace.shared.open(_:)` | Opens System Settings to specific pane |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `MoleBarUI ↔ MoleBarStores` | Direct property reads (`@Observable`); method calls for actions | UI does not own state; Stores do |
| `MoleBarStores ↔ MoleBarCore` | Async/await + AsyncStream | Stores never hold `Process` handles |
| `MoleBarCore ↔ subprocess` | `ProcessRunner` only | The single seam for testability |
| `LaunchAgent helper ↔ main app` | None at runtime; both invoke same Core helpers | Helper is a separate executable bundling minimal Core |
| `MoleBarUpdater (Sparkle) ↔ main app` | Standard delegate pattern | Quarantined to its own SwiftPM target |

### Module / Process Model

- **Single process** for the running app. The mole CLI is a child process. **No XPC service.**
- An XPC sandboxed service was considered and rejected: the app is **not sandboxed by design** (PROJECT.md: "App Store sandbox blocks deep-clean operations"). XPC's main argument is privilege isolation in sandboxed apps. Without sandboxing, XPC adds complexity (separate target, IPC marshalling) for no security gain — the app already has FDA and runs `mole` directly with the user's privileges.
- **Two sibling processes** when scheduling is in use: main app + `mole-scheduler-runner` helper invoked by launchd. They don't communicate; both write to the same `JobLog` (use `O_APPEND` so writes are atomic for line-sized records — JSONL is naturally append-safe).

## Sources

### Apple Documentation (HIGH confidence)
- [MenuBarExtra | Apple Developer Documentation](https://developer.apple.com/documentation/swiftui/menubarextra)
- [MenuBarExtraStyle | Apple Developer Documentation](https://developer.apple.com/documentation/swiftui/menubarextrastyle)
- [WindowGroup vs Window | Apple Developer Documentation](https://developer.apple.com/documentation/SwiftUI/WindowGroup)
- [UNUserNotificationCenter | Apple Developer Documentation](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter)
- [Manage login items and background tasks on Mac - Apple Support (SMAppService)](https://support.apple.com/guide/deployment/manage-login-items-background-tasks-mac-depdca572563/web)
- [Bring multiple windows to your SwiftUI app - WWDC22](https://developer.apple.com/videos/play/wwdc2022/10061/)
- [Reliable test for Full Disk Access? — Apple Developer Forums (Apple's recommendation: attempt + handle error)](https://developer.apple.com/forums/thread/114452)
- [Observation and MainActor — Apple Developer Forums](https://developer.apple.com/forums/thread/731822)
- [SwiftUI Timer not working inside Menu bar extra — Apple Developer Forums (.menu runloop block)](https://developer.apple.com/forums/thread/726369)

### Confirmed Bugs / Issues (HIGH confidence)
- [FB13683957: SwiftUI MenuBarExtra .menu style does not rerender body](https://github.com/feedback-assistant/reports/issues/477)
- [FB13683950: SwiftUI MenuBarExtra (.menu) needs an open event](https://github.com/feedback-assistant/reports/issues/475)

### Sparkle (HIGH confidence)
- [Sparkle Documentation](https://sparkle-project.org/documentation/)
- [Sparkle Delta Updates](https://sparkle-project.github.io/documentation/delta-updates/)
- [Sparkle 2.x CHANGELOG (external bundle update support)](https://github.com/sparkle-project/Sparkle/blob/2.x/CHANGELOG)

### Swift Concurrency (HIGH confidence)
- [SE-0406: Backpressure support for AsyncStream (status: still pending)](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0406-async-stream-backpressure.md)
- [swift-async-algorithms: Throttle / Debounce](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncAlgorithms.docc/Guides/Throttle.md)
- [Swift Subprocess (jamf) — modern Process wrapper](https://github.com/jamf/Subprocess)
- [Swift 6.2 Subprocess (Michael Tsai) — upcoming official API](https://mjtsai.com/blog/2025/10/30/swift-6-2-subprocess/)

### Patterns / Tutorials (MEDIUM confidence — verified against Apple docs above)
- [Build a macOS menu bar utility in SwiftUI - nilcoalescing](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/)
- [Scenes types in a SwiftUI Mac app - nilcoalescing](https://nilcoalescing.com/blog/ScenesTypesInASwiftUIMacApp/)
- [Window management in SwiftUI - Swift with Majid](https://swiftwithmajid.com/2022/11/02/window-management-in-swiftui/)
- [MenuBarExtraAccess (workarounds for .menu limitations)](https://github.com/orchetect/MenuBarExtraAccess)
- [Showing Settings from macOS Menu Bar Items - Peter Steinberger](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items)
- [Building a Modern Launch Agent on macOS (SMAppService)](https://gist.github.com/Matejkob/f8b1f6a7606f30777552372bab36c338)
- [FullDiskAccess Swift package (reference; not a dependency)](https://github.com/inket/FullDiskAccess)
- [macOS distribution — code signing & notarization (rsms)](https://gist.github.com/rsms/929c9c2fec231f0cf843a1a746a416f5)

### Persistence Choices (HIGH confidence)
- [AppStorage vs UserDefaults vs SwiftData: Choosing the Right One](https://bleepingswift.com/blog/appstorage-vs-userdefaults-vs-swiftdata)
- [UserDefaults | Apple Developer Documentation](https://developer.apple.com/documentation/foundation/userdefaults)

---
*Architecture research for: macOS menu-bar app wrapping a third-party CLI*
*Researched: 2026-04-27*
