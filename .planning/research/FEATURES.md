# Feature Research

**Domain:** macOS menu-bar system utility wrapping a CLI (system cleaning, monitoring, disk analysis, maintenance)
**Researched:** 2026-04-27
**Confidence:** HIGH (Mole inventory verified against current `tw93/mole` README + repo source on `main`; peer features verified against official sites)

---

## Authoritative `tw93/mole` Feature Inventory

Source: `tw93/mole` README on `main` (verified) + repo `cmd/`, `lib/` directory listings (verified via GitHub API on 2026-04-27). Every Mole capability listed below MUST be reachable from MoleBar UI per `PROJECT.md` Core Value: "Full Mole feature parity in the menu bar."

### Top-Level Subcommands (`mo <verb>`)

| Mole Command | What It Does | JSON Output? | MoleBar Surface |
|--------------|--------------|--------------|-----------------|
| `mo` (no args) | Interactive arrow-key/vim menu — main entry point | n/a (TUI) | Replaced by menu bar popover |
| `mo clean` | Deep clean: caches, logs, browser leftovers, orphaned app data | Implicit via op-log | "Clean" section in popover |
| `mo uninstall` | Smart-uninstall installed app + all leftovers (Application Support, Caches, Preferences, Logs, WebKit storage, Cookies, Extensions, Plugins, Launch daemons) | Implicit | **Deferred to v2 per PROJECT.md** |
| `mo optimize` | Refresh caches & services (DB rebuild, network reset, Finder/Dock refresh, swap purge, launch-services rebuild, Spotlight reindex) | Implicit | "Optimize" section |
| `mo analyze` (alias `analyse`) | Visual disk explorer — directory tree, large files | **Yes**, `--json` flag | Disk analyzer **window** (per PROJECT.md, requires window not popover) |
| `mo status` | Live system health dashboard (CPU/GPU/memory/disk/network/battery/sensors/processes/health-score) | **Yes**, `--json` flag, auto-detects pipe | Live menu-bar metrics + popover detail |
| `mo purge` | Clean project build artifacts (`node_modules`, `target`, `.build`, `build`, `dist`, `venv`) across configured roots | Implicit | "Project Cruft" section |
| `mo installer` | Find and remove installer files (`.pkg`, `.dmg`) from Downloads, Desktop, Homebrew caches, iCloud, Mail | Implicit | "Installer Leftovers" section |
| `mo touchid` | Configure Touch ID for sudo (writes pam config) | n/a | Settings → "Sudo with Touch ID" toggle |
| `mo completion` | Set up shell tab completion (bash/zsh/fish) | n/a | Power-user submenu |
| `mo update` | Update Mole binary (`--nightly` for unreleased main) | n/a | Handled by MoleBar's binary-update subsystem (NOT user-invoked) |
| `mo remove` | Uninstall Mole from system | n/a | NOT exposed (MoleBar manages binary lifecycle) |
| `mo --help` / `mo --version` | Help / version output | n/a | Settings → About |

### Cross-Cutting Flags (apply across most subcommands)

Source: README "Flags & Options" section.

| Flag | Purpose | MoleBar Mapping |
|------|---------|-----------------|
| `--dry-run` | Preview without executing | **Default for v1** per PROJECT.md safety model |
| `--debug` | Detailed logs alongside previews | Settings → "Debug logs" toggle; show in result drawer |
| `--whitelist` | Manage protected paths/checks (interactive multi-select) | Settings → "Protected items" UI |
| `--paths` | Configure project scan directories | Settings → "Project roots" editor |
| `--json` | Machine-readable JSON output | **Always-on for orchestration** (MoleBar parses JSON, never TUI) |
| `--proc-cpu-threshold` | Tune CPU alert threshold (status) | Settings → "Process alert threshold" |
| `--proc-cpu-window` | Sustained-CPU monitoring window (status) | Settings → "Sustained-CPU window" |
| `--proc-cpu-alerts=false` | Disable process alerts | Settings → toggle |

### Environment Variables

| Variable | Effect | MoleBar Handling |
|----------|--------|------------------|
| `MO_NO_OPLOG=1` | Disable operation logging | Pass through if user opts out of telemetry |
| `MO_LAUNCHER_APP=<name>` | Override terminal-app detection | Irrelevant (MoleBar IS the launcher) |

### `mo clean` Submodules (verified from `lib/clean/` directory)

Mole's clean is composed, not monolithic. Mapped to `.sh` modules in `lib/clean/`:

| Module | Cleans | UI Grouping |
|--------|--------|-------------|
| `app_caches.sh` | Per-app caches (Spotify, Dropbox, Slack, Docker, etc.) | "App Data" |
| `apps.sh` | Orphaned data from already-uninstalled apps | "Orphaned App Data" |
| `brew.sh` | Homebrew caches, old versions | "Homebrew" |
| `caches.sh` | User & system caches | "System Caches" |
| `dev.sh` | Xcode (DerivedData, Archives, unused CoreSimulator volumes), Node.js, npm | "Developer Tools" |
| `maven.sh` | `~/.m2/repository` cleanup | "Developer Tools" |
| `project.sh` | Build-artifact cleanup hook (shared with `purge`) | "Project Cruft" |
| `system.sh` | System logs, temp files, Trash, swap, diagnostic reports | "System Cleanup" |
| `user.sh` | User-level junk (downloads detritus, etc.) | "User Cleanup" |

### `mo optimize` Submodules (`lib/optimize/`)

| Module | Purpose |
|--------|---------|
| `maintenance.sh` | DB rebuilds, launchd refresh, Spotlight reindex, network reset, Finder/Dock restart |
| `tasks.sh` | Discrete optimize tasks (composable, can be selectively run) |

### `mo manage` Submodules (`lib/manage/`)

| Module | What It Manages | Config File |
|--------|-----------------|-------------|
| `whitelist.sh` | Protected cache paths + skipped optimize health-checks (interactive multi-select, paginated) | `~/.config/mole/whitelist`, `~/.config/mole/whitelist_optimize` |
| `purge_paths.sh` | Project-scan roots (one path per line, `~` supported, `#` comments) | `~/.config/mole/purge_paths` |
| `update.sh` | Update Mole itself | n/a |
| `autofix.sh` | Self-healing for broken Mole installs | n/a |

### `mo status` Metrics (`cmd/status/metrics_*.go`)

The most granular set; MoleBar's live menu-bar display draws from these:

| Metric File | Surface |
|-------------|---------|
| `metrics_cpu.go` | Per-core %, load avg, uptime, frequency |
| `metrics_gpu.go` | GPU utilization, frequency, memory (Apple Silicon + dGPU) |
| `metrics_memory.go` | Used/free, pressure, compressed, swap, top apps |
| `metrics_disk.go` | Per-volume used/free, activity (read/write rate) |
| `metrics_network.go` | TX/RX rate, top apps, IPs, connectivity |
| `metrics_battery.go` | Level, charging state, cycles, health, time-remaining |
| `metrics_bluetooth.go` | Bluetooth peripheral battery (AirPods, Magic Mouse, etc.) |
| `metrics_hardware.go` | Hardware identifiers, model, chip |
| `metrics_health.go` | Composite health score (0-100) |
| `metrics_process.go` | Top processes by CPU/RAM |
| `process_watch.go` | Sustained-CPU process alerting (configurable thresholds) |

### `mo analyze` Capabilities (`cmd/analyze/`)

| Source File | Capability |
|-------------|------------|
| `scanner.go` | Filesystem walk with concurrency |
| `heap.go` | Top-N largest files heap |
| `cleanable.go` | Mark "safely deletable" candidates (caches, build artifacts) |
| `delete.go` | In-place deletion from analyzer |
| `insights.go` | Surface insights ("you have 12 GB of npm cache") |
| `view.go` | TUI tree view |
| `json.go` | `--json` output: `{path, overview, entries[], large_files[], total_size, total_files}` |

Keyboard shortcuts (TUI; MoleBar reimplements as buttons): `O` Open, `F` Show in Finder, `⌫` Delete, `L` Large-files view, `Q` Quit.

### Quick-Launcher Integration (`scripts/setup-quick-launchers.sh`)

Mole ships a Raycast/Alfred integration that installs five script-commands: `Mole Clean`, `Mole Uninstall`, `Mole Optimize`, `Mole Analyze`, `Mole Status`. **MoleBar should NOT install these on user behalf** (territorial conflict with Raycast/Alfred owners), but should NOT fight them either if the user installed them via Mole directly.

### Operation Log

Path: `~/Library/Logs/mole/operations.log`. Append-only audit trail of every destructive op. **MoleBar should display this log in the popover/window** as the trust signal.

---

## Peer Menu-Bar Utility Survey

What polished macOS menu-bar utilities offer (informs table-stakes baseline). Sources verified on official sites/repos.

| Peer | Category | Standout Feature |
|------|----------|------------------|
| **Stats** (exelban/stats) | System monitor | 11 modules (CPU/GPU/RAM/disk/net/battery/sensors/BT/clock/RAM-pressure/fans), per-module enable, MIT/free |
| **iStat Menus 7** (Bjango) | System monitor | Most metric depth (S.M.A.R.T., per-app CPU/RAM, weather, world clock); rules-based notifications |
| **iStatistica** (imagetasks) | System monitor | Notification Center widgets; menu-bar + dock |
| **CleanMyMac Menu** (MacPaw) | Cleaner + monitor | "Smart Care" one-click; malware Protection monitor; Battery Health; live RAM-pressure with "free up" button |
| **AlDente** (AppHouseKitchen) | Battery health | Slider-driven control directly in menu bar (live status icons paid only) |
| **Maccy** (p0deje) | Clipboard | Hotkey-first, search-in-popover, pin items, OPTION-modifier secondary actions |

### Common Patterns (table-stakes for v1)

1. **Live menu-bar text/icon display** with on/off per metric.
2. **Click → popover** with detail; popover dismisses on outside click or Escape.
3. **Right-click → quick context menu** (Quit, Settings, About).
4. **Login-item launch on startup** (managed via `SMAppService` on macOS 13+).
5. **Notifications** for thresholds (CPU > X%, disk < Y%, malware found, etc.) via UserNotifications framework.
6. **Per-feature enable/disable** to control resource cost (Stats explicitly markets disabling sensors/BT for 50% energy savings).
7. **Menu-bar icon ordering** (user repositions via ⌘-drag; macOS-native, free).
8. **Keyboard hotkey** to summon popover (Maccy: ⇧⌘C; AlDente, Stats also configurable).
9. **First-run permissions onboarding** (Full Disk Access in particular).
10. **Sparkle 2 in-app updates** (industry standard for non-MAS Mac apps).

---

## Feature Landscape

### Table Stakes (Users Expect These)

Missing any of these = the app feels broken or half-finished. All confirmed against PROJECT.md "Active" requirements unless noted.

| # | Feature | Why Expected | Complexity | Notes |
|---|---------|--------------|------------|-------|
| 1 | **Live menu-bar metrics** (CPU/GPU/memory/disk/net) with configurable display: icon-only / single-metric inline / popover-only | Every peer menu-bar monitor offers this; the menu-bar text is the product's only persistent UI | MEDIUM | PROJECT.md Active req. Powered by `mo status --json` polled every 1-2s. Each metric independently toggleable. |
| 2 | **One-click cleaning** for `mo clean` modules (caches, browser data, logs, app data, dev tools, Trash) | Maps directly to Mole's flagship subcommand | MEDIUM | Default to dry-run; show preview; confirm. PROJECT.md Active req. |
| 3 | **System optimization actions** (`mo optimize`: DB rebuilds, network reset, Finder/Dock refresh, Spotlight reindex, swap purge) | Mole's optimize subcommand; CleanMyMac Smart Care equivalent | MEDIUM | One toggle per task or "run all"; note network reset / Spotlight reindex are disruptive — surface that. PROJECT.md Active req. |
| 4 | **Project cruft purge** (`mo purge`: `node_modules`, `target`, `.build`, `build`, `dist`, `venv`) across user-configured roots | Killer feature for developers; Mole's `purge` subcommand | MEDIUM | Roots editor (UI for `~/.config/mole/purge_paths`); 7-day-old auto-deselection from upstream. PROJECT.md Active req. |
| 5 | **Installer leftovers** (`mo installer`: `.pkg`/`.dmg` from Downloads, Desktop, Brew caches, iCloud, Mail) | Mole's `installer` subcommand; common Mac housekeeping | LOW | Straightforward list-and-confirm. PROJECT.md Active req. |
| 6 | **Disk analyzer** (`mo analyze` with tree view, top-N large files, in-place delete, "show in Finder") | DaisyDisk/CleanMyMac equivalent; Mole's `analyze` subcommand | HIGH | **Requires a separate window**, not a popover (acknowledged in PROJECT.md). Reuses `--json` from Mole; visualization is the heavy lift. |
| 7 | **Dry-run-first preview** with explicit confirm step on every destructive op | Trust requirement for an app that touches user data; matches Mole's safety model | MEDIUM | Power-user toggle unlocks one-click after 3+ uses per action (PROJECT.md Active req). |
| 8 | **Operation log** viewer (Mole writes to `~/Library/Logs/mole/operations.log`) | Trust signal: "show me what you did" | LOW | Tail log into a popover/window panel; offer "open in Console" link. |
| 9 | **First-run permissions onboarding** (Full Disk Access guidance with deep-link to System Settings) | Most Mole ops require FDA; without onboarding, app appears broken | MEDIUM | Required before any clean/optimize action runs. Re-check on every launch (FDA can be revoked). |
| 10 | **Settings / Preferences** window (display modes, polling rate, notifications, protected items, project roots, hotkey, login-item) | Every peer ships one | MEDIUM | SwiftUI `Settings` scene; tabs for General, Display, Cleaning, Notifications, Advanced. |
| 11 | **Login-item launch on startup** (`SMAppService.mainApp.register`) | Menu-bar apps universally support this | LOW | macOS 13+ API; one toggle. |
| 12 | **Notifications** for completed actions (success/failure summary with bytes-freed) | Background/scheduled work needs feedback | LOW | UserNotifications framework; PROJECT.md Active req. |
| 13 | **Bundled Mole binary, auto-updated separately from app** | Zero-install friction is a PROJECT.md constraint | HIGH | Hash-pinned binary in `Contents/Resources/`; checksum-verified updater pulling from `tw93/mole` GitHub Releases. PROJECT.md Active req. |
| 14 | **Sparkle 2 in-app auto-update** for MoleBar itself | Industry standard for non-MAS Mac apps | MEDIUM | Separate update channel from the bundled binary. PROJECT.md Active req. |
| 15 | **Quit / Restart / About / Check for Updates** in right-click menu | Standard menu-bar app affordances | LOW | Trivial. |
| 16 | **Notarized signed `.dmg` distribution** + Homebrew Cask | PROJECT.md Constraint; required for Gatekeeper trust | MEDIUM | One-time CI/CD setup. |

### Differentiators (Competitive Advantage)

These are where MoleBar wins over CleanMyMac, iStat Menus, and Stats individually.

| # | Feature | Value Proposition | Complexity | Notes |
|---|---------|-------------------|------------|-------|
| D1 | **Scheduling / automation** for cleanup tasks (cron-style or weekly/monthly) with notification on result | **Not in Mole itself** (per PROJECT.md). CleanMyMac doesn't auto-clean; iStat doesn't clean at all; Stats doesn't clean. Killer feature. | MEDIUM | Use `BGAppRefreshTask` or launchd agent; respect "on AC power" / "screen locked" preconditions. PROJECT.md Active req. |
| D2 | **All-in-one** (cleaner + monitor + analyzer + optimizer in one menu bar) | Replaces buying CleanMyMac + iStat Menus + DaisyDisk separately. Mole already pitches this — MoleBar makes it visible. | n/a | Inherent in wrapping Mole. Marketing point, not a build item. |
| D3 | **Free + open source** while peers are paid (CleanMyMac $40/yr, iStat Menus $12 one-time, AlDente Pro $20) | Trust + price advantage. Stats is the only free peer with comparable monitoring. | n/a | PROJECT.md Constraint (MIT). Marketing point. |
| D4 | **Transparent dry-run preview** showing exact files/bytes that will be deleted, with per-item opt-out | CleanMyMac shows summary only; users can't pre-audit. | MEDIUM | Already implied by PROJECT.md safety model. The differentiation is making the preview UI rich (tree view, per-item checkboxes), not just an alert. |
| D5 | **Live op-log streaming** in popover (tail of `operations.log` while a clean runs) | Competing tools show a spinner; MoleBar shows what's actually happening. | LOW | Tail file into a SwiftUI scrollable text view. |
| D6 | **Health score widget** (`mo status` health metric) prominent in menu bar | Mole emits a 0-100 score; surfacing it as the primary glanceable metric is unique. | LOW | Single line in popover header + optional menu-bar inline. |
| D7 | **JSON-first orchestration** internally — no TUI parsing — gives stable behavior across Mole upgrades | Reduces breakage risk when Mole's TUI changes. | n/a | Architecture choice, not a user-facing feature. Affects Pitfalls research. |
| D8 | **Process-watch alerts** (sustained CPU > threshold over window) using `mo status` `--proc-cpu-*` flags | Native to Mole; surfaces as a notification that says "Slack has used 90% CPU for 2 minutes." | LOW | Configure thresholds in Settings; route alert to UserNotifications. |
| D9 | **Bluetooth peripheral battery** in popover (AirPods, Magic Mouse) | Mole reports it via `metrics_bluetooth.go`; iStat Menus charges for it; nice freebie. | LOW | Just render the data Mole already returns. |
| D10 | **Touch ID for sudo** one-click setup via `mo touchid` | Mole has it; surfacing it as a Settings toggle is a delighter. | LOW | Run `mo touchid`; present completion alert. |
| D11 | **"Recently freed" running tally** in popover ("MoleBar reclaimed 42.7 GB this month") | Stickiness signal; satisfying. | LOW | Sum bytes-freed from operation log. |

### Anti-Features (Deliberately NOT Built)

Each row explains WHY we won't build it. This list exists to prevent scope creep and to honor PROJECT.md "Out of Scope."

| # | Feature | Why Tempting | Why We Don't Build It | Alternative |
|---|---------|--------------|----------------------|-------------|
| A1 | **App uninstaller (smart uninstall with leftover review)** | Signature Mole feature; users will ask | **Deferred to v2 per PROJECT.md.** Heaviest UX surface (drag-target, leftover diff, multi-step confirm). v1 ships sooner without it. | Surface "Use `mo uninstall` in Terminal" link until v2; or open Mole's TUI in user's terminal. |
| A2 | **Reimplementing Mole logic in Swift** | Faster execution, no binary bundling | **PROJECT.md Out of Scope.** Loses upstream lockstep; re-derives the safety model. | Wrap the CLI; bundle binary; auto-update binary separately. |
| A3 | **Mac App Store distribution** | Wider audience, easy install | **PROJECT.md Out of Scope.** Sandbox forbids Full Disk Access writes that Mole requires. | GitHub Releases + Homebrew Cask + Sparkle. |
| A4 | **Real-time auto-clean** (delete-on-detect, no preview) | Feels magical, "it just works" | Violates the dry-run-first safety model that is the trust differentiator. One bad delete = lost user. | Scheduled cleanups WITH notification + ability to review before/after. |
| A5 | **Custom cleaning rules / scriptable cleaners** | Power-user flexibility | Encourages users to write logic that diverges from Mole's audited safety model; turns MoleBar into a footgun. | Use Mole's `--whitelist` and `--paths` configuration; expose those in Settings. Anything beyond → file an issue with `tw93/mole`. |
| A6 | **macOS < 14 support** | Slightly larger TAM | **PROJECT.md Out of Scope.** Forces compat shims for `MenuBarExtra`, `Observation`, Charts. New app, no legacy users. | Document the requirement; revisit if user demand surfaces. |
| A7 | **Closed-source commercial fork / Pro tier with paywalled features** | Revenue | **PROJECT.md Out of Scope.** Breaks Mole MIT ethos; trust signal for a destructive tool requires open source. | Donation / GitHub Sponsors only. |
| A8 | **Reimplementing the Mole TUI inside the app** | Show users "the Mole experience" | Pure UI duplication; the menu bar IS the new UI. | The popover replaces the TUI; offer a "Run in Terminal" escape hatch for power users. |
| A9 | **Live update/patching of the bundled `mo` binary mid-session** | "Always latest" | Breaks running operations; binary signature changes mid-flight = scary. | Update at app launch, gated behind user consent ("Mole 1.4.2 → 1.4.3 available — update now? Restart Mole."). |
| A10 | **Native iOS / iPadOS / Linux ports** | Cross-platform reach | **PROJECT.md Out of Scope.** Mole is macOS-specific; the wrapper inherits that. | None — these are different products. |
| A11 | **Background telemetry / usage analytics** | Improve product | Trust violation for a destructive tool with Full Disk Access. | Opt-in crash reporting only (Sparkle has built-in support). No analytics by default. |
| A12 | **Auto-running `mo` on first launch** | "Just works" | Destructive ops without user confirmation = nuclear. Even dry-run consumes disk I/O. | Show empty state with a "Run a scan" button. User initiates. |
| A13 | **Replicating iStat Menus' weather/world-clock widgets** | Feature parity with monitoring tools | Not in Mole; out of MoleBar's mission ("Mole feature parity"). Scope creep. | Tell users to install iStat Menus alongside if they want weather. |
| A14 | **Custom themes / icon packs / appearance customization** | Personalization | High UI cost, low value, distracts from the safety/cleaning mission. | Light/dark-mode follow-system only. SF Symbols for icons. |
| A15 | **In-app sale of "premium clean profiles"** | Revenue | Same as A7 — breaks open-source ethos. | None. |

---

## Feature Dependencies

```
[Bundled mo binary + auto-updater (#13)]                        <-- foundational, blocks ~everything
   |
   +--> [Permissions onboarding (#9)]                           <-- must run before any destructive op
   |       |
   |       +--> [Live menu-bar metrics (#1)]
   |       |        |
   |       |        +--> [Process-watch alerts (D8)]
   |       |        +--> [Health score widget (D6)]
   |       |        +--> [Bluetooth peripheral battery (D9)]
   |       |
   |       +--> [One-click cleaning (#2)]
   |       |        |
   |       |        +--> [Dry-run preview (#7)]                  <-- gates the clean action
   |       |                |
   |       |                +--> [Live op-log streaming (D5)]
   |       |                +--> [Notifications (#12)]
   |       |                +--> [Recently-freed tally (D11)]
   |       |
   |       +--> [System optimization (#3)]
   |       +--> [Project cruft purge (#4)]
   |       +--> [Installer leftovers (#5)]
   |       +--> [Disk analyzer window (#6)]
   |
   +--> [Settings window (#10)]
   |       |
   |       +--> [Login-item toggle (#11)]
   |       +--> [Whitelist editor]                               <-- wraps `mo --whitelist` config
   |       +--> [Project roots editor]                           <-- wraps ~/.config/mole/purge_paths
   |       +--> [Touch ID for sudo (D10)]
   |
   +--> [Operation log viewer (#8)]
   |
   +--> [Scheduling / automation (D1)]                           <-- depends on #2, #3, #4, #5 for actions
            |
            +--> [Notifications (#12)]                           <-- consumed by D1

[Sparkle 2 app updater (#14)]                                    <-- independent of mo binary updater
[Notarized .dmg + Homebrew Cask (#16)]                           <-- distribution layer, independent
```

### Dependency Notes

- **Bundled binary + permissions + dry-run gate everything.** No clean/optimize/purge feature can be built before these three are in place. They must be the first phase.
- **Settings window is not optional**, even for v1: project-roots editor and whitelist editor are required for `mo purge` and `mo clean` to be customizable; without them users can only run defaults.
- **Notifications are a shared dependency** of background work (D1 scheduling) and foreground work (#12 action completion). Build the notification subsystem once; reuse.
- **Disk analyzer window (#6) blocks no other features**, but introduces the UI/core split that PROJECT.md says v1 must already enforce. Treat as a forcing function for clean architecture, not a late-phase add-on.
- **Scheduling (D1) depends on #2/#3/#4/#5** all being orchestratable headlessly via JSON. Cannot be built before those are stable.
- **App uninstaller (A1) is the v2 forcing function.** Architecture must allow adding it without rewrites — i.e., destructive-action UI must be a reusable component, not bespoke per feature.

---

## MVP Definition

### Launch With (v1) — aligned with PROJECT.md "Active"

The minimum surface that delivers "full Mole feature parity (minus uninstall) in the menu bar":

- [ ] #13 Bundled `mo` binary + separate auto-updater for the binary
- [ ] #9 Permissions onboarding (Full Disk Access)
- [ ] #1 Live menu-bar metrics from `mo status --json` (CPU/GPU/memory/disk/network) with display-mode configurability
- [ ] #2 One-click cleaning (`mo clean` modules) with dry-run preview
- [ ] #3 System optimization (`mo optimize`)
- [ ] #4 Project cruft purge (`mo purge`) with project-roots editor
- [ ] #5 Installer leftovers (`mo installer`)
- [ ] #6 Disk analyzer window (`mo analyze`) — needs a window per PROJECT.md
- [ ] #7 Dry-run-first preview with 3+ uses → power-user toggle unlock
- [ ] #8 Operation log viewer
- [ ] #10 Settings window (General / Display / Cleaning / Notifications / Advanced tabs)
- [ ] #11 Login-item toggle
- [ ] #12 Notifications for action completion
- [ ] #14 Sparkle 2 app auto-update
- [ ] #16 Notarized signed `.dmg` + Homebrew Cask
- [ ] D1 Scheduling / automation
- [ ] D6 Health score widget (cheap freebie from `mo status`)

### Add After Validation (v1.x)

Once core works and users are using it:

- [ ] D5 Live op-log streaming in popover (polish)
- [ ] D8 Process-watch alerts (configurable thresholds)
- [ ] D9 Bluetooth peripheral battery panel
- [ ] D10 Touch ID for sudo one-click
- [ ] D11 "Recently freed" running tally
- [ ] Right-click menu enrichments (quick-clean shortcut, etc.)

### Future Consideration (v2+)

- [ ] A1 → **App uninstaller (smart uninstall)** — the explicit v2 deliverable per PROJECT.md
- [ ] Full GUI window app (beyond disk analyzer) — PROJECT.md Out of Scope for v1
- [ ] Localized strings beyond English (Mole supports ~40 languages via README; MoleBar can follow once core is stable)
- [ ] Statistics dashboard ("space reclaimed over time" with Charts)
- [ ] Backup integration ("snapshot before clean" via APFS local snapshots)

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| #13 Bundled binary + updater | HIGH | HIGH | P1 |
| #9 Permissions onboarding | HIGH | MEDIUM | P1 |
| #1 Live menu-bar metrics | HIGH | MEDIUM | P1 |
| #2 One-click clean | HIGH | MEDIUM | P1 |
| #7 Dry-run preview | HIGH | MEDIUM | P1 |
| #3 Optimize | HIGH | MEDIUM | P1 |
| #4 Project purge | HIGH | MEDIUM | P1 |
| #5 Installer cleanup | MEDIUM | LOW | P1 |
| #6 Disk analyzer | HIGH | HIGH | P1 |
| #10 Settings window | HIGH | MEDIUM | P1 |
| #11 Login-item toggle | MEDIUM | LOW | P1 |
| #12 Notifications | MEDIUM | LOW | P1 |
| #8 Op-log viewer | MEDIUM | LOW | P1 |
| #14 Sparkle updater | HIGH | MEDIUM | P1 |
| #16 Signed `.dmg` + Cask | HIGH | MEDIUM | P1 |
| D1 Scheduling | HIGH | MEDIUM | P1 |
| D6 Health score widget | MEDIUM | LOW | P1 |
| D5 Live op-log stream | MEDIUM | LOW | P2 |
| D8 Process-watch alerts | MEDIUM | LOW | P2 |
| D9 Bluetooth battery | LOW | LOW | P2 |
| D10 Touch ID for sudo | LOW | LOW | P2 |
| D11 "Recently freed" tally | LOW | LOW | P2 |
| A1 App uninstaller | HIGH | HIGH | P3 (v2) |

**Priority key:**
- P1: v1 launch blocker
- P2: v1.x — add once core validated
- P3: v2 / future

---

## Competitor Feature Analysis

How MoleBar compares to peers across the dimensions that matter:

| Feature | CleanMyMac Menu | iStat Menus | Stats | AlDente | Mole CLI | **MoleBar v1** |
|---------|-----------------|-------------|-------|---------|----------|----------------|
| Live system stats in menu bar | Partial | Yes (deepest) | Yes | No | Yes (TUI) | **Yes (from `mo status`)** |
| Deep clean (caches/logs/dev) | Yes | No | No | No | Yes | **Yes (wraps `mo clean`)** |
| Smart app uninstall | Yes | No | No | No | Yes | **Deferred to v2** |
| System optimize / DB rebuild | Yes (Smart Care) | No | No | No | Yes | **Yes (wraps `mo optimize`)** |
| Disk visualizer | Yes | Partial (S.M.A.R.T.) | No | No | Yes | **Yes (window from `mo analyze`)** |
| Project artifact purge (`node_modules`, etc.) | No | No | No | No | Yes | **Yes (wraps `mo purge`)** |
| Installer leftover cleanup | Partial | No | No | No | Yes | **Yes (wraps `mo installer`)** |
| Scheduled cleanups | No | n/a | n/a | No (Pro: Sailing Mode) | No | **Yes (D1 — differentiator)** |
| Dry-run preview | No (summary only) | n/a | n/a | n/a | Yes (`--dry-run`) | **Yes, default-on (D4)** |
| Operation log | No (hidden) | n/a | n/a | n/a | Yes (visible file) | **Yes, surfaced in UI** |
| Open source / free | No ($40/yr) | No ($12) | Yes (MIT) | Free + Pro $20 | Yes (MIT) | **Yes, MIT (D3)** |
| Mac App Store | Yes | Yes | No | No | n/a | **No — sandbox blocks deep clean (Out of Scope)** |
| In-app updater (Sparkle) | Yes | Yes | Yes | Yes | n/a (CLI self-update) | **Yes (Sparkle 2)** |

**MoleBar's unique positioning:** the only free, open-source, menu-bar app that combines deep cleaning + project purge + monitoring + scheduling, with Mole's audited safety model.

---

## Sources

- [tw93/mole README on `main`](https://github.com/tw93/mole) — verified 2026-04-27
- [tw93/mole repo source — `cmd/`, `lib/`](https://github.com/tw93/Mole/tree/main) — directory listings via GitHub API
- [tw93/mole `lib/clean/` modules](https://github.com/tw93/Mole/tree/main/lib/clean) — `app_caches.sh`, `apps.sh`, `brew.sh`, `caches.sh`, `dev.sh`, `maven.sh`, `project.sh`, `purge_shared.sh`, `system.sh`, `user.sh`, `hints.sh`
- [tw93/mole `cmd/status/` metric files](https://github.com/tw93/Mole/tree/main/cmd/status) — verified per-metric Go sources
- [tw93/mole `lib/manage/whitelist.sh`](https://raw.githubusercontent.com/tw93/mole/main/lib/manage/whitelist.sh) — protected paths + skipped checks
- [tw93/mole `lib/manage/purge_paths.sh`](https://raw.githubusercontent.com/tw93/mole/main/lib/manage/purge_paths.sh) — project roots config format
- [exelban/Stats — macOS menu bar system monitor](https://github.com/exelban/stats)
- [iStat Menus by Bjango](https://bjango.com/mac/istatmenus/)
- [iStatistica](https://www.imagetasks.com/istatistica/)
- [CleanMyMac X Menu — official MacPaw page](https://macpaw.com/cleanmymac-x/cleanmymac-menu)
- [CleanMyMac X Menu support article](https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-menu)
- [AlDente Charge Limiter](https://github.com/AppHouseKitchen/AlDente-Charge-Limiter)
- [Maccy clipboard manager](https://github.com/p0deje/Maccy)
- [PROJECT.md (this repo)](/Users/romatroskin/Developer/Projects/mole_menu/.planning/PROJECT.md) — Active, Out of Scope, Constraints

---
*Feature research for: macOS menu-bar app wrapping `tw93/mole` CLI*
*Researched: 2026-04-27*
