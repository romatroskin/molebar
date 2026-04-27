# Pitfalls Research

**Domain:** macOS menu bar app wrapping a third-party Shell+Go CLI that performs destructive filesystem operations
**Researched:** 2026-04-27
**Confidence:** HIGH (signing/notarization, Sparkle, FDA, launchd) / MEDIUM (MenuBarExtra bugs, Cask automation, Mole-specific behavior)

> Severity legend: **P0** = ship-blocker (app won't launch / loses user data / fails notarization), **P1** = bad reviews / lost trust (users uninstall, write angry blog posts), **P2** = papercut (annoying, can be fixed in a point release).

---

## Critical Pitfalls

### Pitfall 1: Bundled `mole` binary fails notarization or won't execute on user machines (P0)

**What goes wrong:**
The `.app` ships, the user double-clicks, and macOS shows "mole is damaged and can't be opened" — or the app launches but every CLI invocation fails with `Operation not permitted` / `kill 9` from the kernel. Worst case: notarization itself fails because the embedded binary isn't signed with hardened runtime, has the wrong team prefix, or has an extended attribute Apple's stapler rejects.

**Why it happens:**
Apps that bundle a third-party CLI (especially a Go binary, which is a single mach-O the developer didn't compile) hit four overlapping requirements:

1. **Hardened runtime must be enabled on the embedded binary**, not just the host app. Without `codesign -o runtime` on `Contents/Resources/mole` (or wherever it's nested), notarization rejects the bundle.
2. **The embedded binary must be signed with the same Developer ID Team** as the host app. If you download an upstream-signed `mole` binary (signed by tw93's Apple ID, if at all) and embed it as-is, the team prefix mismatch fails notarization. You must re-sign it yourself.
3. **`codesign --deep` is deprecated and unreliable** — it only signs mach-O files, ignores some resources, and order matters. Apple's current guidance is "sign bottom-up": embedded binaries first, then frameworks, then the outer `.app`.
4. **Quarantine / translocation gotcha**: even when notarization passes, if the user runs the `.app` from `~/Downloads`, Gatekeeper translocates it to a randomized read-only path. Any attempt by `mole` to read sibling files (its own resources, JSON schemas, scripts) breaks. The fix is for the *user* to drag-to-Applications — most users don't.

**How to avoid:**
- Build a Makefile / shell-script signing pipeline that runs in this order: `codesign mole` (hardened, your team ID, with timestamp) → `codesign any frameworks` → `codesign MoleBar.app` (hardened, with parent entitlements) → `xcrun notarytool submit` → `xcrun stapler staple`.
- Add `com.apple.security.cs.allow-jit` and `com.apple.security.cs.allow-unsigned-executable-memory` *only if* Mole's Go binary needs them — start without and only add on demonstrated failure.
- Use a separate `embedded.entitlements` for `mole` that is more restrictive than the host app — e.g., no `inherit` flag.
- Before each release, run `spctl --assess --type execute -vvv MoleBar.app` and `codesign --verify --deep --strict --verbose=2 MoleBar.app` in CI as a release gate.
- Ship the `.dmg` (which carries the quarantine attribute correctly) rather than a `.zip` (which strips the executable bit on extraction). Use a DMG with a "drag to Applications" background image as the standard out-of-translocation hint.

**Warning signs:**
- `codesign --verify` exits 0 locally but `spctl --assess` says "rejected".
- The notarization log mentions `"The signature of the binary is invalid"` for the embedded binary path.
- TestFlight-style testers report "permission denied" on first launch but it works for you (you ran it from Xcode, they ran it from `~/Downloads`).

**Phase to address:** Distribution / signing phase, *before* the first public TestFlight-equivalent release. Set up signing CI before the first feature is even shipped — every commit should produce a signed, notarized, stapled artifact.

---

### Pitfall 2: Subprocess pipe deadlock hangs the menu bar app (P0)

**What goes wrong:**
The user clicks "Clean caches", `mole` runs, produces a few hundred KB of progress JSON on stdout, fills the OS pipe buffer (typically 16-64KB), blocks on `write()`, and never exits. The Swift app, meanwhile, is waiting for `mole` to finish before reading stdout. Both are blocked. The menu bar icon is now spinning forever and the user force-quits.

**Why it happens:**
This is the canonical Swift `Foundation.Process` footgun. The naive pattern is:

```swift
let process = Process()
process.standardOutput = Pipe()
try process.run()
process.waitUntilExit()                       // BAD — blocks main thread / blocks pipe drain
let data = pipe.fileHandleForReading.readDataToEndOfFile()  // BAD — never reached if buffer full
```

The OS pipe buffer is small. A long-running CLI that emits structured JSON for every file it inspects will saturate it within seconds. `Process` does not auto-drain; it's the caller's responsibility. Apple's own docs note the legacy `Process` API is "surprisingly tricky" and recommend the new `swift-subprocess` package.

There are three other related failure modes:

- **Zombie children**: if you don't `waitpid` / consume the termination handler, `mole` leaves a zombie entry in the process table. Cumulative over a long-running menu bar session, this exhausts file descriptors.
- **SIGTERM doesn't propagate to grandchildren**: Mole is 81% Shell. The CLI is a wrapper script that execs subcommands. If the user clicks "Cancel" and you send SIGTERM to the Shell PID, the Go subprocess it spawned keeps running. You need `setpgid` and `kill(-pgid, SIGTERM)` to kill the whole process group.
- **Environment inheritance**: if you launch via `Process` without setting `environment`, it inherits an *empty* `PATH`. Mole's Shell wrappers call `find`, `awk`, `du`, etc., which fail with "command not found". Conversely, if you inherit the user's full environment, you may inherit `HOMEBREW_PREFIX`, `NIX_PATH`, etc., which can shadow system tools and break Mole.

**How to avoid:**
- **Use `swift-subprocess` (the official Apple package), not `Foundation.Process`.** It handles pipe draining, async streams, and process group cleanup correctly.
- If you must use `Process`: read stdout/stderr asynchronously via `pipe.fileHandleForReading.readabilityHandler`, never `readDataToEndOfFile`. Always set `terminationHandler` to clean up.
- Set explicit `environment` with a curated PATH: `["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory(), "LANG": "en_US.UTF-8"]`. Add `HOMEBREW_PREFIX` only if Mole documents it as required.
- Launch each Mole invocation in its own process group: in `Process` use `qualityOfService` and a custom `posix_spawn`-based launcher, or use `swift-subprocess`'s built-in PG handling. On cancel, kill the whole group.
- Set a hard wall-clock timeout on every invocation (e.g., 5 min for cleaning, 30 min for full disk scan). On timeout, kill the group and report "operation took too long" to the user — better a clear failure than a zombie menu bar.
- Add a "force quit all mole processes" diagnostic action accessible from a debug submenu.

**Warning signs:**
- Activity Monitor shows multiple `mole` PIDs after a single cleanup operation finishes.
- The popover spinner runs for >30 seconds with no progress text updating.
- On dev machine, everything is fine; on a tester's machine with a non-trivial shell init (oh-my-zsh, asdf), things mysteriously hang.

**Phase to address:** Foundation phase — before *any* feature that calls `mole`. Build the subprocess orchestration layer with proper async draining + timeouts as the first piece of code. Treat it as critical-path infrastructure.

**Sources:** [Swift Subprocess proposal](https://github.com/swiftlang/swift-foundation/blob/main/Proposals/0007-swift-subprocess.md), [Swift Forums discussion of Process freezes](https://forums.swift.org/t/the-problem-with-a-frozen-process-in-swift-process-class/39579), [Apple Developer Forums: Running a Child Process with Standard I/O](https://developer.apple.com/forums/thread/690310)

---

### Pitfall 3: Sparkle EdDSA signature verification breaks updates silently (P0)

**What goes wrong:**
Version 1.0 ships fine. Version 1.1 builds fine, the appcast is published, users see the update prompt — but every user is stuck because Sparkle reports "the update is improperly signed and could not be validated", with no clear path forward. Users who want the new feature uninstall and reinstall manually, losing trust. Worst case: you used the wrong signing key, replaced the public key in `Info.plist`, and now no Sparkle key rotation is possible (Sparkle does not support key removal).

**Why it happens:**
- The build artifact (`.dmg` or `.zip`) is rebuilt or re-zipped after `generate_appcast` ran, so the recorded `sparkle:edSignature` no longer matches the file bytes.
- The `SUPublicEDKey` is missing from the `Info.plist` of the *new* version (only the old one had it). Sparkle 2 requires the public key in every shipped version.
- `generate_appcast` was run with the wrong `--ed-key-file` (e.g., a key from a previous environment).
- The user is on an old version of MoleBar that has a *different* old public key embedded — so even a correctly-signed new bundle fails verification on their machine.
- The CI environment leaks the EdDSA private key into build logs (e.g., via `set -x` in a release script).

**How to avoid:**
- Always use Sparkle's `generate_appcast` rather than signing each artifact by hand. It produces deltas, signs both artifact and (optionally) the appcast itself, and is much harder to misuse.
- Treat the EdDSA private key as the single most-critical secret. Store as a GitHub Actions secret, never echo, write to a temp file with `umask 077`, delete after use, never commit.
- Lock in `SUPublicEDKey` in `Info.plist` *before the first public release*. Once a single user installs v1.0 with a given key, you cannot rotate it without manual action by every user.
- Add a CI gate that runs `generate_appcast --verify-update` on a freshly-built artifact and fails the release if the signature doesn't validate.
- Enable `SURequireSignedFeed` from day one — otherwise an attacker who compromises your appcast hosting can serve a malicious update binary signed by themselves.
- Test the update flow in CI: stand up version N, simulate update to N+1, confirm Sparkle accepts.

**Warning signs:**
- Multiple users report "update failed, please download manually."
- The Sparkle log (Console.app, filter by `sparkle`) shows `EdDSA signature verification failed`.
- Your release script has the line `cp Build.zip dist/MoleBar.zip` *after* `generate_appcast`.

**Phase to address:** Distribution phase, in parallel with Pitfall 1's signing pipeline. Ship version 0.0.1 with Sparkle wired up correctly even if there are no features yet — bake the upgrade path before users exist.

**Sources:** [Sparkle Documentation](https://sparkle-project.org/documentation/), [Sparkle Discussion #2174 — EdDSA verification failing](https://github.com/sparkle-project/Sparkle/discussions/2174), [Sparkle Discussion #2401 — improperly signed updates](https://github.com/sparkle-project/Sparkle/discussions/2401), [Sparkle Issue #1364 — keychain storage](https://github.com/sparkle-project/Sparkle/issues/1364)

---

### Pitfall 4: Full Disk Access UX traps the user in a permission loop (P0)

**What goes wrong:**
First launch: app prompts user "Please grant Full Disk Access". User goes to Settings, drags the app in, toggles it on. Returns to MoleBar. App still says "Full Disk Access not granted". User toggles off and on again. Quits and relaunches. Still denied. User gives up, leaves a one-star review titled "Doesn't work".

**Why it happens:**
- macOS requires the app to be *fully restarted* (not just relaunched, but actually killed) after FDA is granted, because TCC entitlements are evaluated on process spawn. SwiftUI apps with `LSUIElement = YES` (menu bar agents) are not always killed cleanly when the user clicks the app icon in System Settings.
- The detection technique you used (try to open `~/Library/Mail`, catch error) gives a false negative on systems where Mail.app isn't installed or where the user has an unusual home directory layout.
- Reading `~/Library/Application Support/com.apple.TCC/TCC.db` directly is itself a TCC-protected operation — but it does *not* trigger a prompt, which is the standard detection trick. It can return false negatives when the per-user DB exists but is empty, or when the system DB has the entry instead.
- Users grant FDA to the wrong target. If MoleBar invokes `mole` as a child process, FDA must be granted to MoleBar.app (the parent) — not to the `mole` binary. But TCC sometimes shows the child's path in the prompt, confusing users.

**How to avoid:**
- Use the documented detection idiom: attempt to read a known-protected file like `~/Library/Safari/Bookmarks.plist` or `~/Library/Mail`, and check the error code. Cache the result, but re-check after every "open Settings" action.
- Build a multi-step onboarding flow: (1) explain *why* FDA is needed, (2) open `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles` directly, (3) display a "I've granted it" button that calls `NSRunningApplication.terminate(self)` after a short delay so the app respawns.
- Re-detect FDA on `applicationWillBecomeActive` (when the user comes back from Settings), not just on launch.
- In the popover, surface a clear "Diagnostic: FDA = Granted/Denied" indicator. Click → opens Settings.
- Do NOT silently retry destructive operations after FDA is denied. Make the failure mode explicit: "Cleanup failed: Full Disk Access required for /Library/Caches".
- When invoking `mole`, set its working directory and environment such that it inherits MoleBar's TCC context. Do NOT prompt the child to acquire its own FDA — it can't.
- Document the kill-and-relaunch quirk in the onboarding flow: "macOS requires MoleBar to fully restart after granting permission. Click here when ready." Then `exit(0)` and rely on a launchd label to respawn (or just instruct the user to relaunch from `~/Applications`).

**Warning signs:**
- Support emails containing "I've granted Full Disk Access multiple times but it still doesn't work."
- Crash reports / logs showing `EPERM` on `~/Library/Mail` reads after the user reports having granted FDA.

**Phase to address:** First-launch / onboarding phase. This is the user's first impression and the highest-cost UX failure. Build a polished FDA flow before shipping any cleaning feature.

**Sources:** [Apple Dev Forums — Reliable test for Full Disk Access](https://developer.apple.com/forums/thread/114452), [A deep dive into macOS TCC.db (Rainforest QA)](https://www.rainforestqa.com/blog/macos-tcc-db-deep-dive), [sing-box FDA permission loop issue](https://github.com/SagerNet/sing-box/issues/3742)

---

### Pitfall 5: SwiftUI `MenuBarExtra` ships with documented bugs (P1)

**What goes wrong:**
You build the entire UI with `MenuBarExtra(...) { ContentView() }` and `.menuBarExtraStyle(.window)`. In testing, three things break that aren't on macOS 14.0 but appear on real users' machines:

1. The popover doesn't dismiss when the user clicks elsewhere; or it dismisses, then re-opens spuriously.
2. The popover content shows stale data from the last time it opened — body view is not re-rendered when the user reopens.
3. There's no programmatic way to dismiss the popover from within a SwiftUI button (e.g., "Run cleanup" should close the popover and show a banner).
4. On macOS 14.6.1 specifically, popover-style `MenuBarExtra` has a documented crash.
5. The popover doesn't resize smoothly when content changes — animations stutter, or the window snaps awkwardly.

**Why it happens:**
`MenuBarExtra` was introduced in macOS 13 and is still missing fundamental APIs. Apple's feedback assistant has multiple open reports:
- FB11984872 — no programmatic close
- FB13683957 — body not re-rendered on reopen
- Sonoma 14.6.1 popover crash (fixed in later versions but you cannot enforce a minimum patch level)

**How to avoid:**
- Plan from day one that you may have to fall back to a hybrid approach: SwiftUI for the popover *content* but `NSStatusItem` + `NSPopover` (or a third-party library like [`fluid-menu-bar-extra`](https://github.com/lfroms/fluid-menu-bar-extra)) for the menu bar integration itself.
- Architect the UI so the menu bar integration is a thin shell. The "real" UI is a `ContentView` that can be hosted in any window/popover/sheet. This keeps you future-proof and lets you swap the host.
- Never store mutable state inside the `MenuBarExtra`'s body; store it in an `@Observable` ViewModel held outside, so reopening shows fresh data regardless of whether SwiftUI re-renders.
- For "dismiss after action" use a `dismiss` environment value workaround OR keep the popover open and show a transient toast. Don't fight the framework.
- Test on at least three macOS versions: 14.0 (oldest supported), 14.x latest, and 15.x latest. Bugs differ across them.

**Warning signs:**
- TestFlight users report "the menu doesn't go away" or "I see the old data".
- Crash reports from `SwiftUI` framework on Sonoma.

**Phase to address:** UI foundation phase. Decide the SwiftUI-vs-AppKit split early. If you commit to `MenuBarExtra` and hit blockers in week 4, the rewrite cost is significant.

**Sources:** [feedback-assistant/reports #383](https://github.com/feedback-assistant/reports/issues/383), [feedback-assistant/reports #477](https://github.com/feedback-assistant/reports/issues/477), [fluid-menu-bar-extra (workaround library)](https://github.com/lfroms/fluid-menu-bar-extra), [BetterDisplay popover crash issue #3282](https://github.com/waydabber/BetterDisplay/issues/3282)

---

### Pitfall 6: Live monitoring kills battery and triggers App Nap edge cases (P1)

**What goes wrong:**
The menu bar shows "CPU: 47% / RAM: 12 GB" and updates every second. On battery, the user notices their MacBook drains 8% per hour with MoleBar running. They quit it. Word spreads: "this app is a battery hog". Even worse: when the user is on AC and the lid is closed (clamshell mode), App Nap kicks in and the displayed numbers are stale by 30+ seconds because timers are throttled, but the user assumes they're real.

**Why it happens:**
- A 1Hz `Timer` that polls system stats wakes the CPU 86,400 times per day. On Apple Silicon, the kernel coalesces timers across processes for power efficiency, but a high-priority repeating timer in the foreground app defeats this.
- Drawing the menu bar icon every second triggers a full menu bar repaint, which has cascading effects.
- App Nap throttles background apps' timers (down to 1/min). Menu bar agents (`LSUIElement`) are sometimes treated as background by App Nap heuristics, especially when the popover is closed. So your "1Hz updates" silently become "very slow updates" without the UI knowing.
- The display sleeps but timers keep firing — wasted work.

**How to avoid:**
- Default refresh rate: 5 seconds when popover is closed, 1 second when popover is open. Most users don't need 1Hz monitoring at all times; ship it as opt-in for the icon-only mode.
- Use `DispatchSourceTimer` with leeway, not `Timer`. `leeway: .milliseconds(500)` lets the kernel coalesce.
- Listen for `NSWorkspace.willSleepNotification` / `didWakeNotification` — pause polling when the system sleeps. Listen for `screensDidSleep` similarly.
- Listen for `NSProcessInfo.thermalStateDidChangeNotification` and back off polling when the system is under thermal pressure.
- Disable polling entirely when on battery if the user toggles "Power saver" — at minimum, drop to 30s.
- Measure energy impact every release: open Activity Monitor → Energy tab → ensure MoleBar's "12hr Power" stays ≤0.1.
- For the icon itself: only redraw when the displayed value *actually changes*. If CPU was 4% last tick and 4% this tick, no `setImage` call.
- Document the App Nap behavior. If the user sets "Show CPU in menu bar" and the lid is closed for an hour, the displayed value being stale on wake is OK — but show a brief "updating..." indicator on first display.

**Warning signs:**
- Activity Monitor shows MoleBar in the top-10 energy users.
- Console.app shows `App Nap` events for MoleBar's PID with a high "throttle level".
- User reports: "the numbers froze" (App Nap throttling) or "battery drains fast" (no throttling at all).

**Phase to address:** Live monitoring feature phase. Build the energy budget *into* the monitoring abstraction; don't bolt it on later.

**Sources:** [Apple Energy Efficiency Guide — App Nap](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html)

---

### Pitfall 7: Destructive operations have no undo affordance (P0)

**What goes wrong:**
User clicks "Clean caches", confirms the dialog, MoleBar runs `mole clean -y`, deletes 12 GB. Among the deleted files is a Photoshop scratch disk that was 9 GB and the user *was actively using*. Adobe crashes. There is no Trash to restore from — `mole` (and its `rm -rf` heritage) deletes immediately, not via Finder Trash. The user files an angry GitHub issue: "MoleBar destroyed my work."

**Why it happens:**
- `rm` does not move files to Trash. Cleanup CLIs almost universally use `rm -rf` because moving to Trash is slow, OS-version-dependent, requires NSWorkspace which CLIs can't easily access, and can fail if Trash is on a different volume.
- The dry-run preview is generated separately from the actual deletion. By the time the user confirms, file state may have changed (a process may have created a new cache file, etc.).
- The "are you sure?" dialog is shown so often it becomes muscle memory. Users click through it.
- Mole's JSON output may not exhaustively enumerate every path it will touch, especially for "smart" subcommands that decide based on heuristics at runtime.

**How to avoid:**
- **Default delete strategy: Move to Trash via `NSFileManager.trashItem`, not `rm`.** This means MoleBar runs the deletion itself in Swift, using paths discovered by `mole --dry-run`, rather than calling `mole clean`. Tradeoff: re-implementing some deletion logic; benefit: a real undo via Cmd+Shift+Delete in Finder.
- For files >1 GB, present them individually and let the user uncheck.
- Snapshot the deletion plan at confirmation time. If the on-disk state differs at execution (file size changed >10%, file modified in last 60s), abort and re-prompt. "This file is in use by another app — skip?"
- The "power user toggle" (skip preview after 3+ uses) should still log every deletion to a JSON file in `~/Library/Logs/MoleBar/`, so a sufficiently-determined user can audit "what did MoleBar delete yesterday?" The log is the second-best undo.
- Never auto-execute on a schedule without an opt-in flag named something like "Skip preview for scheduled runs" — and require a separate confirmation step to enable it, with explicit warning text.
- For Mole subcommands where Mole's own `--dry-run` is unreliable or non-existent: don't ship those subcommands in v1. Wait until Mole's JSON schema is stable enough to trust.
- Confirmation dialogs: vary the wording across categories (caches, projects, installers) to defeat muscle-memory click-through. Show estimated reclaimed size prominently.

**Warning signs:**
- User testing reveals the dry-run preview missed a file the actual cleanup deleted.
- A bug report titled "Cleanup deleted my project" — investigate immediately, this is a trust-defining moment.

**Phase to address:** Cleaning feature phase. Establish the "Trash, not delete" invariant before *any* cleaning subcommand is exposed in UI. Code review checklist item: any feature that modifies the filesystem must use `trashItem` or be documented as opt-in irreversible.

**Sources:** [Safe File Deletion on macOS (Medium)](https://fredriccliver.medium.com/safe-file-deletion-on-macos-protect-yourself-from-rm-rf-mistakes-d6d3d8b3d540), Mole upstream source (review `tw93/Mole/mole` script for actual deletion semantics)

---

### Pitfall 8: launchd-based scheduler fires unpredictably across sleep / reboot (P1)

**What goes wrong:**
User configures "Clean caches every Sunday at 3 AM". Sunday at 3 AM the Mac is asleep. On wake Monday morning, the cleanup either (a) doesn't run at all, (b) runs immediately and dumps a notification while the user is in a Zoom meeting, or (c) runs *twice* because of a launchd quirk where missed StartCalendarInterval invocations accumulate. Worst case: the user opens a Photoshop file at 9:01 AM Monday, MoleBar fires the missed 3 AM cleanup at 9:02 AM, deletes scratch disk.

**Why it happens:**
- `launchd` and `Timer` have fundamentally different semantics for sleep:
  - `Timer` running in-process: doesn't fire while asleep; on wake, the next fire is recomputed from current time.
  - `launchd` `StartInterval`: there's a long-standing bug (rdar://4058640, rdar://6630231) where intervals miss across sleep cycles.
  - `launchd` `StartCalendarInterval`: missed times do fire on wake — but timing is non-deterministic and can double-fire across reboots.
- `launchd` jobs that fail silently: if your `RunAtLoad` plist has a typo, or the binary path is wrong, or the `StandardOutPath` directory doesn't exist, launchd logs to `system.log` and gives up. The user sees nothing.
- Plist permissions: `~/Library/LaunchAgents/com.molebar.scheduler.plist` must be `chmod 644` and owned by the user. If MoleBar writes it with the wrong perms, launchd refuses to load.
- LaunchAgents do not get the user's full environment (especially PATH). Even if `mole` is in `/usr/local/bin`, the agent invocation can fail because PATH is `/usr/bin:/bin`.

**How to avoid:**
- **Don't use launchd directly. Use `SMAppService` (macOS 13+) for scheduled jobs.** It's the modern, supported API and handles plist installation correctly.
- For sub-daily cadence, use an in-process `Timer` and require MoleBar to be running. Combined with "Open at Login" (also via `SMAppService.loginItem`), this gives reliable scheduling without launchd's sleep quirks.
- Catch missed invocations explicitly: at app launch, check "last run" timestamp in `UserDefaults`. If `now - lastRun > intervalThreshold`, prompt user "It's been 8 days since the last cleanup. Run now?" — never auto-execute a missed run without consent.
- Display next-run time in the popover so the user can verify their schedule is alive.
- Provide a "Test schedule now" button — fires the configured action immediately. Catches plist / env bugs in seconds.
- Always show a notification before destructive scheduled runs ("Cleanup running in 60 seconds, click to cancel").
- For LaunchAgents specifically (if SMAppService isn't enough): set explicit `EnvironmentVariables` in the plist with PATH including `/usr/local/bin` and `/opt/homebrew/bin`.

**Warning signs:**
- "My scheduled cleanup didn't run last weekend" reports.
- Console.app shows `launchd: bug: 21345` errors mentioning `com.molebar`.
- Activity Monitor shows MoleBar consuming CPU at unexpected times.

**Phase to address:** Scheduling feature phase, *after* the basic CLI orchestration and cleanup primitives are stable. Don't build scheduling on top of unreliable foundations.

**Sources:** [Apple Dev Forums — launchd jobs at midnight](https://developer.apple.com/forums/thread/52369), [launchd.info Tutorial](https://launchd.info/), [When Cron Jobs Disappear: MacOS Sleep](https://www.josephspurrier.com/macos-sleep-cron), [launchd-dev mailing list — StartInterval and sleep](https://launchd-dev.macosforge.narkive.com/ZF2IQriC/launchd-startinterval-and-sleep)

---

### Pitfall 9: Bundled `mole` binary drifts out of sync with upstream / breaks on schema change (P1)

**What goes wrong:**
MoleBar v1.2 ships with bundled `mole` v1.36.1. Two weeks later, `tw93/mole` releases v1.37.0 with new features. MoleBar users want them. You trigger an in-app "Update CLI only" — but v1.37.0 changed the JSON output schema for `mole clean --dry-run` (renamed `paths` to `targets`). MoleBar's parser breaks. Users now have a half-working app: monitoring works, cleaning doesn't.

**Why it happens:**
- Mole is open source, MIT-licensed, and the maintainer has no obligation to maintain JSON schema stability across versions. Shell+Go projects rarely document schema versions.
- The "auto-update CLI separately" model means MoleBar releases and CLI releases are decoupled — a schema-incompatible CLI can land without a corresponding parser update.
- The CLI is a single binary you download from GitHub Releases; if the upstream maintainer signs it differently (or not at all), or changes the binary name or location in the release zip, your auto-update logic breaks silently.
- Upstream may release a binary built for arm64 only (or x86_64 only) and you fail to detect that on the wrong architecture.

**How to avoid:**
- **Pin CLI versions explicitly in MoleBar.** The "auto-update" toggle should be opt-in, default-off for v1. Default behavior: ship with a known-tested CLI version, update it only when MoleBar itself updates.
- Maintain a JSON schema validator in MoleBar. Every `mole` JSON response is parsed via a versioned model. On schema mismatch, fall back to a "Compatibility issue: please update MoleBar" banner instead of crashing or executing wrong action.
- On CLI auto-update: download to a staging path, verify SHA256 against an *expected* hash you ship in MoleBar (i.e., MoleBar v1.2 only allows mole v1.36.x with hashes you've verified). Refuse anything else.
- Add a "Compatibility matrix" page in your README and in MoleBar itself: which MoleBar versions support which Mole CLI versions.
- Subscribe to upstream releases (RSS or GitHub Actions watching the upstream repo). Run a CI job nightly that downloads the latest upstream Mole, runs your test suite against it, and opens a PR if it passes (or an issue if it fails). This makes upstream drift visible in days, not after a user complaint.
- Vendor a fallback copy of the CLI inside the `.app`. If user-side auto-update fetches a broken binary, MoleBar always has a known-good fallback.
- Verify Mole's license is MIT (CONFIRMED — MIT, compatible with MoleBar's MIT) and include `LICENSE-MOLE.txt` in the `.app` bundle's `Contents/Resources/` to satisfy attribution.

**Warning signs:**
- A user reports "cleanup broke after auto-update".
- The CI nightly upstream-test job goes red.
- `git diff` of the upstream `mole` script touches files in `cmd/` or `subcmd/` (subcommand structure changed).

**Phase to address:** CLI orchestration foundation phase + ongoing maintenance. Set up upstream monitoring before the first Mole-feature ships.

**Sources:** [tw93/Mole on GitHub](https://github.com/tw93/Mole), [mole on Homebrew Formulae](https://formulae.brew.sh/formula/mole)

---

### Pitfall 10: Homebrew Cask hash mismatches break installs / updates (P1)

**What goes wrong:**
You publish MoleBar v1.1 to GitHub Releases. The Homebrew Cask formula has SHA256 from v1.0. `brew install --cask molebar` fails for everyone. You scramble to bump the hash. While you're scrambling, users blame you for "Homebrew breaking my install". Or the inverse: an automated Homebrew bot updates your Cask, but you re-uploaded the artifact (because of a typo in release notes), bytes are different, hash mismatch, install fails for everyone again.

**Why it happens:**
- Homebrew Cask is hash-locked: the Cask formula contains the SHA256 of the artifact at the URL. Any byte difference fails.
- Replacing a release artifact ("just a tiny fix to the release notes") changes the SHA but not the URL — Homebrew users get hash mismatches.
- The `livecheck` automation may detect a new version on your GitHub Releases and submit a PR with the new hash — but if you push a new tag and *then* push a new artifact 30 seconds later, the autobot may fetch the in-progress artifact and lock the wrong hash.
- For your initial Cask submission, the formula must pass `brew audit --strict` and `brew style`. First-timers get rejected for missing fields, wrong version syntax, etc.

**How to avoid:**
- **Never replace a release artifact.** If you need to fix something, cut a new patch version (v1.1.1). This is the single most-violated rule that causes Cask breakage in this domain.
- Use GitHub Actions to publish: tag → build → upload `.dmg` → wait for upload to complete → only *then* publish the release. Don't have multi-step manual release flow that races with autobump bots.
- Use a unique artifact filename per version (`MoleBar-1.1.0.dmg` not `MoleBar-latest.dmg`). Latest-named artifacts are the #1 source of livecheck pain.
- For your own Cask: include a `livecheck` block that points to your GitHub Releases atom feed. Prefer `auto_updates true` if you ship Sparkle (because Cask shouldn't try to update what Sparkle is updating).
- Run `brew audit --cask --new molebar` before submitting. Run `brew style` and `brew install --cask ./Casks/molebar.rb` locally with the official tap checked out.
- Decide cleanly: does Homebrew or Sparkle "own" updates for the Cask? Best practice: Sparkle for in-app users, Homebrew Cask only for *initial install*, marked with `auto_updates true` so Brew leaves it alone after.

**Warning signs:**
- `brew install --cask molebar` fails with "SHA256 mismatch" — check immediately.
- A flood of GitHub issues right after a release titled "Homebrew install broken".

**Phase to address:** Distribution phase, after Sparkle is stable. Don't attempt Homebrew submission until you have a clean release pipeline.

**Sources:** [Homebrew Cask issue #142136 — SHA256 mismatch](https://github.com/Homebrew/homebrew-cask/issues/142136), [Homebrew Discussion #6365 — autobump SHA mismatch](https://github.com/orgs/Homebrew/discussions/6365), [Homebrew Discussion #5469 — version up-to-date but SHA mismatch](https://github.com/orgs/Homebrew/discussions/5469)

---

### Pitfall 11: Telemetry / phone-home destroys trust (P1)

**What goes wrong:**
You add anonymous usage analytics to track which features are used most. A privacy-aware user runs Little Snitch, sees MoleBar pinging your analytics endpoint after every cleanup, posts to Hacker News: "Open-source Mac cleaner is sending data on your deleted files." Even though the data is just a feature usage counter, the optics are devastating for a tool that touches user files. You lose months of community goodwill in 24 hours.

**Why it happens:**
- Mac users — especially the kind who install cleanup tools — are unusually privacy-aware. The cleanup app category has a long history of bait-and-switch (free tools that turn out to upload file lists, sell to data brokers, etc.).
- Even legitimate, anonymous, opt-out telemetry is read as "this app is spying" by a non-trivial fraction of the audience.
- "Crash reporting" frameworks (Sentry, Bugsnag, Crashlytics) often default-collect PII (file paths, hostname, OS version) that, in a cleanup context, looks like file-list exfiltration even when it isn't.
- A tool that requires Full Disk Access making *any* outbound network call is presumed guilty.

**How to avoid:**
- **Default position: zero outbound network calls except (a) Sparkle update check to your appcast URL, (b) explicit user-initiated "Check for upstream Mole release" call.**
- No analytics. No crash reporting that ships off-device. If you want telemetry, opt-in only, and clearly state on first launch what is sent, with a sample payload visible in-app.
- Crash logs: write to `~/Library/Logs/MoleBar/`, never upload. Provide an "Export logs to share with developer" button that puts the log on the clipboard / opens Mail with attachment — user-controlled.
- Document the network behavior in the README's first paragraph: "MoleBar does not collect, transmit, or sell any data. Network is used only for app update checks (Sparkle) and to query GitHub for upstream Mole releases."
- Ship the appcast over HTTPS; pin certificates if you're paranoid (you should be).
- Do NOT add "send anonymized cleanup statistics" even as opt-in for v1. The signal "we don't even build telemetry infra" is more valuable than the data.
- Never log file *contents* — only counts and sizes — in any user-visible log. Even local logs.

**Warning signs:**
- A user posts a Little Snitch screenshot showing MoleBar making any unexpected network request.
- A reviewer mentions "tracking" or "telemetry" in a review.

**Phase to address:** Architecture phase. Establish the no-telemetry invariant in `ARCHITECTURE.md` and enforce it via a lint rule (e.g., grep for `URLSession`, every match must be in a known-allowed file).

**Sources:** [CleanMyMac X privacy stance (MacPaw)](https://macpaw.com/support/cleanmymac-x/knowledgebase/cleanmymac-safety), [HackerNews — macOS telemetry privacy thread](https://news.ycombinator.com/item?id=25204909)

---

### Pitfall 12: Signing keys / secrets leak through CI (P0 if exploited)

**What goes wrong:**
Your GitHub Actions workflow does `set -x` for debugging, then later runs `echo $APPLE_ID_PASSWORD | xcrun notarytool ...`. The password ends up in a public CI log. Or the Sparkle EdDSA private key is committed accidentally because someone added it to a `.local` file that wasn't gitignored. An attacker with the EdDSA key can ship malicious updates to every existing MoleBar user. An attacker with the Apple Developer cert can sign malware as "MoleBar".

**Why it happens:**
- Code signing requires base64-encoded `.p12` files. Pasting them into GitHub Secrets is fine; saving them locally is fine; but accidentally `git add`-ing the unzipped temp file is shockingly common.
- Notarization requires an Apple ID app-specific password. Many CI examples use plain env vars; a single `set -x` or `echo "Debug: $APPLE_PASSWORD"` leaks it.
- PRs from forks: GitHub Actions does NOT pass secrets to forked-PR workflows by default. But many maintainers loosen this with `pull_request_target` to enable bot-built signed builds — which exposes the secrets to malicious PR diffs.
- The Sparkle EdDSA private key is usually stored in `~/.ssh/` or `~/Library/Application Support/Sparkle/` on the dev machine. It is not git-aware; one `cp` into the repo and it's leaked.

**How to avoid:**
- Use GitHub Secrets only for credentials. Never `echo` them. Use `add-mask` syntax: `echo "::add-mask::$SECRET"` so even accidental prints are redacted.
- Encrypted CI environment: `xcrun notarytool` accepts a stored credential profile in keychain; create a temporary keychain in the runner, store credentials there, delete keychain at workflow end.
- Use Apple's `notarytool store-credentials` with `--keychain-profile`. Reference profile name in CI, not raw password.
- For Sparkle: store the EdDSA private key in a GitHub Secret, decode in CI to a tempfile with `umask 077`, use it, `shred` and remove. Never check in. Add a CODEOWNERS rule on `.gitignore` to prevent accidental removal.
- For PRs from forks: do NOT use `pull_request_target` for signed builds. Use the standard `pull_request` event (no secrets), and have signed releases fire only on `push` to `main` or on tag.
- Audit CI logs after every release for the first 5 releases — search for known secret prefixes.
- Set up secret scanning on the GitHub repo (free for public repos): GitHub Push Protection auto-blocks pushes containing detected secret formats.
- Consider hardware MFA on the Apple ID. If the EdDSA key leaks, Sparkle key rotation is impossible (existing users can't accept a new key without a manual upgrade), so the only recovery is publishing a "stop using MoleBar" advisory and starting over with a new bundle ID.

**Warning signs:**
- A CI log shows base64-encoded data even partially.
- `git log --all -p | grep -i "private"` finds anything.
- An update appears that you didn't publish.

**Phase to address:** Distribution / CI setup phase. Lock this down before the first signed artifact is published.

**Sources:** [Federico Terzi — Automatic Code-signing GitHub Actions](https://federicoterzi.com/blog/automatic-code-signing-and-notarization-for-macos-apps-using-github-actions/), [Sparkle Issue #1364 — keychain key storage](https://github.com/sparkle-project/Sparkle/issues/1364), [GitHub — sign-and-notarize-gha](https://github.com/GuillaumeFalourd/sign-and-notarize-gha)

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Use `Foundation.Process` instead of `swift-subprocess` | One less SPM dependency, familiar API | Pipe deadlocks under real load, zombie children, custom plumbing for every signal/timeout case | Never for a CLI-orchestration app; the rewrite cost compounds |
| `codesign --deep` instead of bottom-up signing | One command, "just works" in dev | Notarization rejections, opaque failures, deprecated by Apple | Only for personal dev builds, never for releases |
| Detect Full Disk Access by trying to `cat ~/Library/Mail` | 5-line implementation | False negatives on stripped-down user systems, breaks if Mail.app removed | Acceptable as a *secondary* check alongside attempting the actual operation |
| Skip Sparkle, ship "download new version" link | No infra setup, faster v1 | Users never update; old vulnerable versions stay deployed forever | Never — install-friction means stale install base, which means support cost |
| Default `rm` instead of `trashItem` for cleanup | Matches Mole's behavior exactly, no Swift-side path management | Single bug = irrecoverable user data loss; one bad review = trust gone | Never for v1; reconsider only after months of clean deletion record + opt-in flag |
| Bundle a `mole` binary that's not re-signed by your team | Faster initial setup, one less signing step | Notarization fails, or works locally but breaks on user machines with strict Gatekeeper | Never — always re-sign embedded binaries |
| Polling 1Hz timer for monitoring | Trivial implementation | Battery drain → bad reviews; App Nap throttling → stale data | Only when popover is actively open; close-state must back off |
| Ship without `SURequireSignedFeed` | Faster Sparkle setup | Anyone who compromises your appcast hosting (S3, GitHub Pages, etc.) can ship malware | Never — feed signing is single-flag toggle |
| Manual SHA256 update for Homebrew Cask | Faster than setting up automation | Race condition between artifact upload and autobump bot | Acceptable for first 1-2 releases while learning the flow |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `mole` CLI invocation | Inheriting full user shell environment | Curated `["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory(), "LANG": "en_US.UTF-8"]` |
| `mole` JSON parsing | Decode directly into final domain model | Decode into a versioned schema model first, validate, then map to domain |
| Sparkle appcast | Self-host on GitHub Pages without HTTPS check | HTTPS-only, signed feed, pinned certificate considered for paranoid users |
| Homebrew Cask URL | Use `download/latest/MoleBar.dmg` style URL | Use versioned URL `download/v1.0.0/MoleBar-1.0.0.dmg` to avoid livecheck races |
| Apple notarytool | Pass credentials on each call | Store in temp keychain profile with `notarytool store-credentials` |
| LaunchAgent plist | Hard-code `/usr/local/bin/mole` (Intel Homebrew path) | Use the bundled `mole` from inside the `.app`; do not rely on user-installed CLI |
| TCC / FDA detection | Trigger a real read attempt that pops a dialog | Use a known-safe TCC-protected path read; check error code without prompting |
| GitHub Releases auto-update for `mole` | Trust whatever binary is at the latest release URL | Whitelist of known-good upstream version+hash pairs shipped in MoleBar; reject unknowns |
| `MenuBarExtra` content updates | State held inside `MenuBarExtra` body closure | State in external `@Observable` ViewModel injected via `.environment` |
| Subprocess cancel on user click "Stop" | `process.terminate()` on the immediate child only | Track process group, kill `-pgid` to catch grandchildren spawned by Mole's shell wrappers |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| 1Hz polling regardless of UI state | Battery drain, App Nap throttling weirdness | Adaptive: 5s closed, 1s open, pause on sleep, pause on thermal | Always — even at 1 user; first reviewer to test on battery flags it |
| Re-rendering icon every poll | Menu bar repaint storms | Diff displayed string; only `setImage` if value changed | Visible at 1Hz with multiple metrics |
| Synchronous `mole` call on main thread | UI freeze for 2-30s | All CLI work on a serial queue; popover shows skeleton/spinner | Visible on first cleanup operation |
| Decoding entire `mole` JSON output into memory | High RAM during disk analyzer scans of 1M+ files | Streaming JSON parse (e.g., line-delimited) | At ~500k file count |
| Sparkle update check on every launch | Spurious network traffic, slow cold start | Sparkle's default daily check is fine; don't override to "on every launch" | Power users with frequent quit/relaunch |
| No download throttle on `mole` binary auto-update | Background fetch saturates connection, surprise behavior | Throttle, only on Wi-Fi, prompt user before download | At any scale on metered connections |
| Disk analyzer holds full file tree in memory | OOM on large home directories | Lazy-load tree, virtualize the SwiftUI list | At ~1M files / ~500k directories |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Embedded `mole` binary not re-signed by your team | Notarization fails / kernel kills binary on launch | `codesign -s "Developer ID Application: <Team>" -o runtime --timestamp Resources/mole` before signing the outer `.app` |
| Sparkle EdDSA private key in repo or CI logs | Attacker pushes signed malicious update to every user; recovery is impossible | Key stored only in GitHub Secrets, decoded to umask-077 tempfile in CI, deleted after use; Sparkle Push Protection enabled |
| Allowing arbitrary `mole clean <user-input>` | Path traversal / command injection via user-provided arguments | All paths validated against allowlist; never pass `/bin/sh -c` style strings; use `Process.arguments` array |
| Trusting downloaded upstream `mole` binary blindly | Compromised GitHub release ships malware to all users | Pin SHA256 of known-tested upstream releases inside MoleBar; reject any binary not in the allowlist |
| Logging file paths in crash reports / telemetry | "MoleBar uploads file lists" headlines, even if technically false | No remote crash reporting; local-only logs in `~/Library/Logs/MoleBar/` |
| Shipping helper tool with wide entitlements | Privilege escalation surface | Don't ship a privileged helper for v1 — design around it. If unavoidable, use SMAppService with narrowest possible scope |
| `xattr -d com.apple.quarantine` shipped in install instructions | Trains users to disable Gatekeeper, malware vector for the future | Never instruct users to bypass Gatekeeper; ensure proper signing/notarization makes it unnecessary |
| `pull_request_target` with code-signing secrets | Attacker submits PR that exfiltrates signing cert | Only run signed builds on `push` to main or on tag, never on PR from fork |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| FDA prompt on first launch with no explanation | User denies, app is now useless, user uninstalls | Pre-prompt onboarding panel: "Why MoleBar needs Full Disk Access, what we'll do with it, what happens if denied" — *then* open Settings |
| "Are you sure?" dialog on every cleanup | Click-through fatigue; user reflexively confirms a destructive action | Vary wording, show estimated reclaimed bytes prominently; reserve confirmation for >1GB or when uncommon paths are touched |
| Power-user toggle (skip preview) hidden too early | New users skip preview after 3 cleanups, lose data | Threshold higher (10+); separate per-action; require an explicit "I understand" toggle in Settings, not just usage count |
| Live monitoring numbers updating constantly in menu bar | Distracting, draws eye away from work | Default to popover-only. Icon-only mode is opt-in, with explicit "this uses ~0.05W" label |
| Cleanup runs in background with no progress feedback | "Is it stuck? Did I break something?" | Always show progress (% / current file / size remaining). On long ops, persistent banner in menu bar |
| Failed cleanup silently shows "Done" | User trusts state, problem accumulates | Distinguish success / partial-success / failure with different colors and counts ("freed 2.1 GB; 3 files skipped due to permissions") |
| Disk analyzer in popover (cramped) | Unusable for actual disk analysis | Disk analyzer always opens a real window, not a popover (already in `PROJECT.md` plan — preserve this) |
| Scheduling UI buried | User doesn't discover it, runs ad-hoc forever | Promote scheduling in onboarding flow as step 3 ("Want this to run automatically?") |
| No way to see what was deleted last time | User can't audit or recover | Persistent log viewer in Settings showing last 30 days of operations with reclaimed sizes and paths |
| Update prompt blocks the menu bar | User has to deal with it before doing what they came for | Use Sparkle's "background install on quit" for non-critical updates; only blocking for security |

## "Looks Done But Isn't" Checklist

- [ ] **Notarization**: Verify on a clean Mac that has never run a dev build of MoleBar (no cached trust). `xattr -p com.apple.quarantine MoleBar.app` should show the quarantine bit, and double-clicking should produce the standard Gatekeeper prompt, then succeed.
- [ ] **FDA flow**: Test by *revoking* FDA in Settings while MoleBar is running. Detection should update without restart, or prompt the user appropriately.
- [ ] **Subprocess cancel**: Run a long cleanup, click cancel, immediately check Activity Monitor. Zero `mole` PIDs should remain.
- [ ] **Sparkle update**: Stand up version N, simulate update to N+1 from N, confirm install completes, confirm N+1 launches and reports correct version. Don't skip — Sparkle bugs hide here.
- [ ] **Sparkle EdDSA on a fresh install**: Install MoleBar fresh from your DMG (don't carry over old prefs), trigger an update — public key match must work without manual intervention.
- [ ] **Signed appcast**: With `SURequireSignedFeed` enabled, manually corrupt the appcast file by 1 byte. Confirm Sparkle refuses the update.
- [ ] **Cleanup actually moves to Trash**: After cleanup, open Trash, verify deleted files are restorable. If not, the cleanup is using `rm` and undo is broken.
- [ ] **Schedule across sleep**: Set a schedule for 5 minutes from now. Sleep the Mac for 10 minutes. Wake. Confirm the missed run is handled per spec (run / prompt / skip — whatever you decided).
- [ ] **Battery test**: Run MoleBar for 1 hour on battery with monitoring on. Battery drain should be <2% above baseline.
- [ ] **Architecture**: Test on Apple Silicon AND Intel (if you support it). Especially the bundled `mole` binary needs to work on both, or you ship a Universal2 binary.
- [ ] **Re-launch after FDA grant**: After granting FDA, the app *must* be killed and respawned to pick up the new entitlement. Verify your onboarding does this automatically.
- [ ] **Homebrew Cask install on a fresh user**: `brew install --cask molebar` end-to-end on a Mac with no previous install.
- [ ] **`mole` CLI version mismatch**: Manually replace the bundled `mole` with an older / newer version, confirm MoleBar detects schema mismatch and refuses gracefully.
- [ ] **No outbound network**: Run with Little Snitch in "deny all" mode. Only Sparkle's appcast URL should appear in connection requests.
- [ ] **Logs don't leak**: Check `~/Library/Logs/MoleBar/` after a session. No file *contents*, no usernames, no PII.
- [ ] **Clean uninstall**: Drag MoleBar from Applications to Trash. Confirm any LaunchAgents, login items, and (if any) helper tools are removed too. Provide an in-app "Uninstall MoleBar" button as a courtesy.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Sparkle EdDSA key leaked | VERY HIGH (recovery may be impossible) | (1) Generate new key. (2) Publish a final update on the old key with code that displays "Critical: download new version manually" and disables auto-update. (3) Publish new bundle (possibly new bundle ID) with new key. (4) Existing users must reinstall manually. (5) Consider this a project-restart event. |
| Notarization fails for a release | LOW | (1) Read `notarytool log <id>` — it's specific. (2) Common fixes: re-sign embedded binary with hardened runtime, add timestamp, fix entitlements file. (3) Resubmit. |
| Bundled `mole` schema break in production | MEDIUM | (1) Rollback to last-known-good MoleBar via Sparkle. (2) Update parser, re-test, ship hotfix. (3) Add upstream-monitoring CI to prevent recurrence. |
| Cleanup deleted user data | HIGH (trust impact) | (1) Acknowledge publicly within hours, not days. (2) Document the exact bug, what versions are affected, what to do. (3) Hotfix release with the bug fixed AND with stricter dry-run preview. (4) Add safeguard: never delete files modified in last 24h without explicit confirmation. (5) Take the L on user trust; rebuild over months. |
| Homebrew Cask SHA mismatch | LOW | (1) Open PR to homebrew-cask repo updating the SHA. (2) Or, cut a new patch version with a fresh artifact (preferred — never replace artifacts). |
| FDA detection broken on some macOS version | LOW-MEDIUM | (1) Add fallback: try-the-real-operation detection. (2) Show clearer error UI on FDA-related failures with direct link to settings. (3) Patch release. |
| `mole` subprocess leaked / zombies on user machine | LOW | (1) Add startup cleanup: at MoleBar launch, look for orphan `mole` PIDs from MoleBar's PPID lineage and kill them. (2) Ship subprocess fix. |
| Battery drain reports | LOW-MEDIUM | (1) Drop to 30s minimum poll. (2) Pause on battery by default. (3) Document in release notes. (4) Re-measure energy in next release. |
| User can't grant FDA, app stuck | LOW | (1) Provide a "Diagnostic mode" that prints exactly what permissions are detected. (2) Provide a fallback "Run with reduced functionality" mode (monitoring works without FDA; cleaning doesn't). |

## Pitfall-to-Phase Mapping

Suggested phase ordering aligned with `PROJECT.md`. Phase names are illustrative — they map to whatever phase structure `/gsd-roadmap` produces.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| #1 Bundled binary notarization | **Phase 0: Distribution Foundations** (set up *before* feature work) | CI release pipeline produces signed/notarized/stapled `.dmg`; smoke-test install on clean Mac |
| #2 Subprocess deadlock / zombies | **Phase 1: CLI Orchestration Core** (foundational, before any feature) | Stress test: 10 concurrent `mole` invocations + cancel; confirm zero zombie PIDs |
| #3 Sparkle EdDSA verification | **Phase 0: Distribution Foundations** | Stand up dummy v0.0.1 → v0.0.2 update flow in CI; gate on signature verification |
| #4 FDA permission loop | **Phase 2: Onboarding & Permissions** | UX test on macOS 14, 15 with fresh user; tester unfamiliar with the app |
| #5 MenuBarExtra bugs | **Phase 1: UI Foundations** | Decide AppKit fallback strategy upfront; test on 14.0, 14.x, 15.x |
| #6 Battery / App Nap | **Phase 3: Live Monitoring Feature** | Activity Monitor energy impact <0.1; manual 1-hour battery test |
| #7 No undo on destructive ops | **Phase 4: Cleaning Features (cross-cutting)** | Code review checklist: every delete uses `trashItem`; logs preserve audit trail |
| #8 launchd scheduler unreliability | **Phase 5: Scheduling Feature** | Sleep / wake / reboot test matrix |
| #9 Bundled CLI drift / schema break | **Phase 1: CLI Orchestration Core** + **ongoing nightly CI** | Schema validator in code; nightly CI test against latest upstream Mole |
| #10 Homebrew Cask hash mismatch | **Phase 6: Distribution Channels** (after Sparkle is solid) | First Cask submission goes through `brew audit --new`; uses versioned artifact URL |
| #11 Telemetry destroys trust | **Phase 0/1: Architecture invariants** | Lint rule: no `URLSession` outside allowlisted files; Little Snitch test in QA checklist |
| #12 Signing key / secret leak | **Phase 0: Distribution Foundations** + **CI hardening** | GitHub Push Protection enabled; secrets stored in temp keychain; never echoed |

## Sources

- [Apple — Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [The Eclectic Light Company — Notarization: the hardened runtime](https://eclecticlight.co/2021/01/07/notarization-the-hardened-runtime/)
- [rsms — macOS distribution: code signing, notarization, quarantine](https://gist.github.com/rsms/929c9c2fec231f0cf843a1a746a416f5)
- [Sparkle Documentation](https://sparkle-project.org/documentation/)
- [Sparkle — EdDSA migration / publishing](https://sparkle-project.org/documentation/eddsa-migration/)
- [Sparkle Discussion #2174 — Update not working due to EdDSA failing](https://github.com/sparkle-project/Sparkle/discussions/2174)
- [Swift Subprocess proposal SF-0007](https://github.com/swiftlang/swift-foundation/blob/main/Proposals/0007-swift-subprocess.md)
- [Swift Forums — frozen Process discussion](https://forums.swift.org/t/the-problem-with-a-frozen-process-in-swift-process-class/39579)
- [Apple Dev Forums — Reliable test for FDA](https://developer.apple.com/forums/thread/114452)
- [Rainforest QA — Deep dive into TCC.db](https://www.rainforestqa.com/blog/macos-tcc-db-deep-dive)
- [feedback-assistant/reports — MenuBarExtra bugs (#383, #477)](https://github.com/feedback-assistant/reports/issues/383)
- [BetterDisplay — popover crash on Sonoma issue #3282](https://github.com/waydabber/BetterDisplay/issues/3282)
- [fluid-menu-bar-extra (community workaround library)](https://github.com/lfroms/fluid-menu-bar-extra)
- [Apple — Energy Efficiency Guide / App Nap](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html)
- [launchd.info Tutorial](https://launchd.info/)
- [Joseph Spurrier — When Cron Jobs Disappear: macOS Sleep](https://www.josephspurrier.com/macos-sleep-cron)
- [Apple Dev Forums — launchd jobs at midnight](https://developer.apple.com/forums/thread/52369)
- [Homebrew Cask Issue #142136 — SHA256 mismatch](https://github.com/Homebrew/homebrew-cask/issues/142136)
- [Homebrew Discussion #6365 — autobump SHA mismatch](https://github.com/orgs/Homebrew/discussions/6365)
- [Federico Terzi — Code-signing macOS apps with GitHub Actions](https://federicoterzi.com/blog/automatic-code-signing-and-notarization-for-macos-apps-using-github-actions/)
- [tw93/Mole on GitHub](https://github.com/tw93/Mole) — confirmed MIT license; CLI is Shell+Go
- [Fredric Cliver — Safe File Deletion on macOS](https://fredriccliver.medium.com/safe-file-deletion-on-macos-protect-yourself-from-rm-rf-mistakes-d6d3d8b3d540)
- [HackerNews — macOS telemetry privacy thread](https://news.ycombinator.com/item?id=25204909)
- [Apple — SMAppService / Privileged Helper migration](https://developer.apple.com/forums/thread/739940)

---
*Pitfalls research for: macOS menu bar app wrapping a third-party Shell+Go CLI with destructive filesystem operations*
*Researched: 2026-04-27*
