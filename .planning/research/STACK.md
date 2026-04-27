# Stack Research

**Domain:** Public, open-source, notarized native macOS 14+ menu bar app that wraps a third-party CLI (Mole). Single-developer indie posture, GitHub Releases + Homebrew Cask + Sparkle 2 distribution. Performs destructive filesystem operations.

**Researched:** 2026-04-27

**Overall confidence:** HIGH for the core stack (Swift / SwiftUI / Sparkle / launchd / GitHub Actions), MEDIUM for a few choices that hinge on the developer's tolerance for pre-1.0 dependencies (swift-subprocess) or trade-offs without one obviously correct answer (Tuist vs raw Xcode project, swift-format vs SwiftLint).

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Swift | 6.x (Xcode 16.3+ toolchain) | Primary language | Required for `@Observable`, modern strict concurrency, and the swift-format toolchain that ships with Xcode 16+. macOS 14 deployment target unlocks the modern surface. **Confidence: HIGH** |
| SwiftUI | macOS 14+ SDK | Primary UI framework | `MenuBarExtra` (macOS 13+) is the supported menu bar surface, and macOS 14 is when it became practical (settings/observation maturity). Constraint document already commits to SwiftUI primary. **Confidence: HIGH** |
| AppKit (interop) | macOS 14+ SDK | `NSStatusItem` escape hatch + `NSWindow` for the disk-analyzer window | `MenuBarExtra` has documented limitations: no API for the underlying `NSStatusItem`, no right-click handling, no draggable popover, fragile dynamic-label rendering, broken `SettingsLink`. Bridge to AppKit only where SwiftUI's surface is insufficient (status item right-click menu, disk-analyzer window styling, drag-to-app target). **Confidence: HIGH** |
| Observation framework (`@Observable`) | macOS 14+ | View-model state | macOS 14 minimum specifically unlocks this; pull-based, finer-grained invalidation than `ObservableObject`, and is now the documented Apple-recommended replacement. Prefer over `ObservableObject` for every new model. **Confidence: HIGH** |
| Swift Charts | macOS 14+ | Inline live-stat sparklines and bar/area charts in the popover | Built-in, declarative, native. Sufficient for CPU/GPU/mem/net trend lines and for non-treemap visuals. **Note:** Swift Charts has no built-in treemap — render the disk treemap with `Canvas` + a layout algorithm (squarified treemap). **Confidence: HIGH** |
| Foundation `Process` | system | Subprocess orchestration of bundled `mole` | `Process` is the production-grade option today. Wrap it in an actor that exposes `AsyncThrowingStream<Data, Error>` for stdout, drains stderr separately, and parses NDJSON line-by-line. **Do not** ship `swiftlang/swift-subprocess` yet for a v1 — it's still pre-1.0 (0.4.0 in March 2026; 1.0 review concludes April 2026) and the docs warn that minor releases may break API. Migrate post-1.0. **Confidence: HIGH** |
| Sparkle | 2.9.1 (or current 2.9.x) | In-app auto-update of MoleBar itself | The de facto standard for non-MAS macOS app updates. EdDSA mandatory (DSA is migrated away from), supports signed appcasts, hardware/minimum-version requirement keys, and Apple Code Signing verification. **Distribute via SwiftPM:** `https://github.com/sparkle-project/Sparkle`. Note: the upstream-CLI auto-updater (mole binary) is **separate** and is a custom downloader, not Sparkle — Sparkle's appcast model is per-app, not per-resource. **Confidence: HIGH** |
| `launchd` user `LaunchAgent` | system | Recurring scheduled cleanups | Apple's documented mechanism for scheduled jobs on macOS. `BackgroundTasks` framework / `BGAppRefreshTask` is **iOS/iPadOS/tvOS/Catalyst only — not native macOS AppKit/SwiftUI apps** (confirmed: Apple docs list iOS/iPadOS/tvOS and Catalyst, not macOS). A user-scope `LaunchAgent` plist installed to `~/Library/LaunchAgents/` with `StartCalendarInterval` is the right primitive. Use Foundation `Timer` only for in-session refresh of live stats while the popover is open. **Confidence: HIGH** |
| `os.Logger` (Unified Logging) | macOS 14+ | Logging / observability | The Apple-recommended modern API. One subsystem (`com.<you>.molebar`) with multiple categories (`cli`, `scheduler`, `updater`, `permissions`, `ui`). Free at release-build optimisation, integrates with Console.app, and lets users export logs for bug reports. **Confidence: HIGH** |
| UserDefaults / `@AppStorage` | system | Settings persistence | Project settings are key/value (display mode, dry-run-toggle counters, scheduled jobs metadata, FDA-onboarding-completed). UserDefaults is the right size and SwiftUI's `@AppStorage` makes binding trivial. Reserve SwiftData for if the disk-analyzer history grows into a relational/queryable cache — not v1. **Confidence: HIGH** |
| XCTest + `pointfreeco/swift-snapshot-testing` | latest | Unit + view snapshot tests | Built-in `XCTest` for logic. `swift-snapshot-testing` is the standard tool for SwiftUI view snapshots; it asserts on image *and* textual representations, integrates with XCTest, no extra runner. UI testing for a menu bar app is famously brittle (no addressable status item) — favour snapshot tests for popover content + integration tests for the CLI orchestrator. **Confidence: HIGH** |

### Build / Project Generation

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **Native Xcode project** (`.xcodeproj`) committed to repo | Xcode 16.3+ | Single source of truth for project config | For a single-developer, single-target indie app, Tuist is overkill — its real wins (caching, modular generation, merge-conflict avoidance) only matter at team/scale. Xcode 16's native SPM integration covers the dependency story (Sparkle, swift-snapshot-testing). Revisit Tuist only if MoleBar grows into multiple modules/targets. **Confidence: MEDIUM** (this is a soft call; reasonable people choose Tuist) |
| Swift Package Manager | bundled | Dependency manager only (Sparkle, swift-snapshot-testing) | Use SPM through Xcode for fetching dependencies. **Do not** use SPM as a *project manager* (no `Package.swift` as the app's root) — SwiftPM still has gaps for app targets that need entitlements, code-signing, custom build phases for binary bundling, and Sparkle integration. **Confidence: HIGH** |
| swift-format (built into Xcode 16) | bundled | Code formatting | Free, Apple-blessed, runs via `Editor > Structure > Format File` and as a build-phase / pre-commit hook. No extra dependency. SwiftLint is broader (lints + formats), but for a single-developer MIT app the lighter touch wins. Add SwiftLint later if/when contributors arrive and style debates start. **Confidence: MEDIUM** |

### Distribution & Release

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| `xcrun notarytool` | bundled (Xcode 16+) | Apple notarization | The only supported notarization CLI since Apple deprecated `altool` for notarization. Authenticate with App Store Connect API key (preferred for CI) or app-specific password + Team ID. Pair with `xcrun stapler staple` to staple the ticket onto the `.app` and `.dmg`. **Confidence: HIGH** |
| `create-dmg` (the [create-dmg/create-dmg](https://github.com/create-dmg/create-dmg) shell script — *not* the npm package) | latest | Build the distributable `.dmg` | Lightweight, no Python dependency, used widely in CI. Sign and notarize the resulting `.dmg` with `codesign` + `notarytool`. Sindresorhus's npm `create-dmg` is fine for hand-building locally but adds a Node toolchain to CI. `dmgbuild` (Python) is more customisable but heavier. **Confidence: MEDIUM** (either tool is defensible; pick one and stop debating) |
| GitHub Actions (macOS runner) | `macos-14`/`macos-15` runner | CI: build, sign, notarize, publish | The ecosystem-standard CI for indie macOS apps in 2025/2026. Self-hosted Apple-silicon runners are not needed at v1. Actions to use: official `actions/checkout`, then a custom job that imports the Developer ID cert from a base64 secret into a temporary keychain, `xcodebuild archive`, `xcodebuild -exportArchive`, sign embedded `mole` first, then app, build dmg, notarize, staple, attach to GitHub Release. **Confidence: HIGH** |
| Sparkle `generate_appcast` | shipped with Sparkle SPM artifact | Generate + sign the appcast XML | Found inside the SPM checkout at `…/artifacts/Sparkle/bin/generate_appcast`. Run after each release; signs the DMG with EdDSA, updates the appcast, supports `sparkle:hardwareRequirements` (Apple-silicon-only) and `sparkle:minimumUpdateVersion` (skip-version-gate enforcement). Host the appcast in the repo's `gh-pages` branch or in `Releases`. **Confidence: HIGH** |
| Homebrew Cask | n/a | Brew-installable distribution channel | Submit a `Cask` PR to `Homebrew/homebrew-cask`. Use `auto_updates true` since Sparkle handles in-app updates after install (Cask only needs to deliver the first install + livecheck for cold-install version freshness). `livecheck` strategy: GitHub releases. Automate cask version bumps with [LanikSJ/homebrew-bump-cask](https://github.com/LanikSJ/homebrew-bump-cask) GitHub Action triggered on a new GitHub Release. **Confidence: HIGH** |
| Plain `bash` release scripts (or `Makefile`) — not Fastlane | n/a | Local one-shot release commands | Fastlane is over-engineered for a single Mac target with no App Store / TestFlight / Match needs. Indie consensus (e.g., Jesse Squires) is that Fastlane is worth its complexity once you have multiple stores / Match-managed certs / TestFlight. MoleBar has none of those — a `release.sh` that calls `xcodebuild`, `codesign`, `create-dmg`, `notarytool`, `stapler`, `generate_appcast`, and `gh release create` is shorter and more maintainable. **Confidence: MEDIUM** |

### CLI Bundling (Mole binary)

| Decision | Detail | Confidence |
|----------|--------|------------|
| Bundle location | `MoleBar.app/Contents/Resources/mole` (a precompiled binary, not a script). Resources/ is correct for a non-bundle helper executable that the app launches via `Process`. Apple's structure also allows `Contents/Helpers/` but Resources/ is fine for a single binary. | HIGH |
| Architecture | Universal2 (`arm64` + `x86_64`). Mole upstream ships per-arch — combine with `lipo -create` at build time, or fetch both and pick at runtime. Universal is friendlier to Cask reviewers and to users on older Intel hardware. | HIGH |
| Signing | Sign the embedded `mole` binary **first** (inside-out): `codesign --force --options runtime --timestamp --sign "Developer ID Application: …" Resources/mole` *before* signing the `.app`. **Never** use `codesign --deep` — Apple has documented it as deprecated for signing since macOS 13 and "considered harmful". | HIGH |
| Entitlements | App needs Hardened Runtime (`-o runtime`) for notarization. Required entitlements: `com.apple.security.cs.allow-jit` = NO (default), `com.apple.security.cs.disable-library-validation` = **YES** (the bundled `mole` is signed by *your* Developer ID, not Apple's, but if it dynamically loads anything not signed by you, library validation will reject it — start without this entitlement and add only if needed). No App Sandbox (project decision: not MAS). | MEDIUM |
| Auto-update of the bundled binary | Custom downloader that polls `tw93/mole`'s GitHub Releases, downloads the new binary to Application Support, verifies a checksum, and re-signs ad-hoc (or hosts your own pre-signed mirror). Apple requires that any executable run by a notarized app be signed by *something* — ad-hoc is acceptable for user-installed updates if Gatekeeper has already approved the parent app. **Sparkle does not solve this** — Sparkle is one appcast per app. | MEDIUM |
| Where the auto-updated binary lives | `~/Library/Application Support/MoleBar/cli/mole` (writable user path). At launch, prefer the Application Support copy if present and newer; fall back to the bundled copy in Resources. | HIGH |

### Permissions / TCC

| Concern | Approach | Confidence |
|---------|----------|------------|
| Full Disk Access | No API to programmatically request it. Detect by attempting a known protected read (`~/Library/Mail`) and checking the error. On failure, run an onboarding flow that opens `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles` and explains the steps with screenshots. | HIGH |
| Other permissions | Automation (AppleScript) has a check API. Screen Recording / Accessibility do not — same try-and-detect pattern. | HIGH |
| `osascript` privilege escalation | For network reset, Spotlight reindex, etc. that need `sudo`, use `osascript -e 'do shell script "…" with administrator privileges'`. This produces the standard system password prompt (no helper-tool / SMJobBless required). Documented Mole behaviour. | HIGH |

---

## Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| [`sparkle-project/Sparkle`](https://github.com/sparkle-project/Sparkle) | 2.9.x | App auto-update | Always (unless distributing via MAS, which we are not) |
| [`pointfreeco/swift-snapshot-testing`](https://github.com/pointfreeco/swift-snapshot-testing) | latest 1.x | Snapshot tests for SwiftUI views | All popover screens + Disk Analyzer window |
| [`orchetect/MenuBarExtraAccess`](https://github.com/orchetect/MenuBarExtraAccess) | latest | Bridges `MenuBarExtra` to its underlying `NSStatusItem` and exposes show/hide bindings | Add only if you need programmatic open/close (e.g., open popover from a hotkey or after a scheduled-job notification). The need will surface during Phase 2 or 3 — don't pre-add. |
| (Future) [`swiftlang/swift-subprocess`](https://github.com/swiftlang/swift-subprocess) | wait for 1.0 | Replacement for `Foundation.Process` | After 1.0 ships and reviews settle (review concluded April 2026). Migrate in v1.x maintenance, not v1.0. |
| (Future) [`yahoo/YMTreeMap`](https://github.com/yahoo/YMTreeMap) | latest | Treemap layout engine | If the hand-rolled `Canvas`-based squarified treemap proves too slow for >50k items in the disk analyzer. Defer until measured. |

**Explicitly NOT recommended for v1:** `ChartsOrg/Charts` (cross-platform legacy library, far heavier than Swift Charts), `willdale/SwiftUICharts` (unmaintained-tier), Fastlane, Tuist, SwiftLint, SwiftData, Combine for state.

---

## Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Xcode 16.3+ | IDE, build, archive, sign | Pin a minimum Xcode version in CI (`actions/setup-xcode` or `xcodes` runner-step). Required for Swift 6 strict concurrency and built-in swift-format. |
| swift-format (Xcode 16 built-in) | Format on save / pre-commit | Add a `.swift-format` config at repo root to lock style across contributors. |
| `xcrun notarytool` | Notarize | Use a stored keychain profile (`notarytool store-credentials`) locally and an App Store Connect API key in CI. |
| `xcrun stapler` | Staple notarization ticket | Run on both `.app` and `.dmg`. |
| `codesign` | Sign | Sign inside-out, use `--options runtime --timestamp`, never `--deep`. |
| `create-dmg` (shell) | DMG packaging | Background image, Applications-folder symlink, sign + notarize after creation. |
| `gh` CLI | GitHub Releases automation | `gh release create`, `gh release upload`. |
| Console.app | Read unified logs | Filter by subsystem `com.<you>.molebar`. |

---

## Installation

```bash
# All of MoleBar's dependencies are added through Xcode > File > Add Package Dependencies:
#   https://github.com/sparkle-project/Sparkle             (target: MoleBar)
#   https://github.com/pointfreeco/swift-snapshot-testing  (target: MoleBarTests)
#   https://github.com/orchetect/MenuBarExtraAccess        (target: MoleBar — only if/when needed)

# Toolchain prerequisites on the dev machine + CI runner:
#   Xcode 16.3 or newer (Swift 6.x toolchain, swift-format built-in, notarytool/stapler)
#   create-dmg (shell version):
brew install create-dmg

#   GitHub CLI for release automation:
brew install gh

# One-time CI / local secret setup:
xcrun notarytool store-credentials "MoleBar-Notary" \
    --apple-id "you@example.com" \
    --team-id "YOURTEAMID" \
    --password "<app-specific-password>"
```

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| `MenuBarExtra` + `MenuBarExtraAccess` for hatch-bridging | Pure AppKit `NSStatusItem` from the start | If you need right-click context menus on the status item, dynamic colour/animation in the icon, or a draggable popover. Steipete and others have documented that `MenuBarExtra` will fight you on these. Could be worth starting with `NSStatusItem` if early prototyping reveals more friction than expected. |
| `Foundation.Process` | `swiftlang/swift-subprocess` | After Subprocess 1.0 ships and stabilises (post-review, mid-2026+). Worth migrating in a 1.x maintenance release. |
| `Foundation.Process` | `jamf/Subprocess` (third-party) | If you want a battle-tested wrapper *now* without writing one yourself. Fine choice — maintained by Jamf and pre-dates the Apple effort. Trade-off: third-party dep vs. ~100 LOC of actor wrapping. |
| Native Xcode project | Tuist | Once the project grows past one app target into multiple library/framework modules. Re-evaluate at v2 (full GUI app). |
| Native Xcode project | XcodeGen (`.yml`-driven) | Lighter than Tuist; sensible if merge conflicts on `project.pbxproj` start to bite. Single-dev avoids that. |
| Plain shell `release.sh` | Fastlane | If you grow into TestFlight, App Store, or multi-team certificate management. Not before. |
| `create-dmg` (shell) | `dmgbuild` (Python) | If you need pixel-perfect DMG appearance and don't mind the Python dep — common in Qt/PyQt land. Overkill here. |
| `create-dmg` (shell) | Sindresorhus's `create-dmg` (Node/npm) | If you already have a Node toolchain in CI. We don't. |
| Custom downloader for upstream `mole` updates | Bundle a fixed CLI version per release | If auto-updating the CLI proves too brittle (signing edge cases, broken upstream releases). v1 should ship with a manual-bump fallback path even if auto-update is the goal. |
| `swift-snapshot-testing` | XCUITest for menu bar | XCUITest is unreliable for `NSStatusItem` — there's no stable accessibility hook into the menu bar. Use only for the disk-analyzer window if needed. |
| UserDefaults / `@AppStorage` | SwiftData | If/when the disk analyzer history needs queryable, relational storage (e.g., "show me deltas vs. last week"). Defer. |
| `LaunchAgent` | Foundation `Timer` (in-process) | For live-stat refresh while the app is foreground/popover-open — `Timer` is right. Never use it for *scheduled cleanups* — those need to run when MoleBar is not running. |
| os.Logger | Print to stdout / `print()` | Never. `os.Logger` is free at release optimisation, integrates with Console.app, supports privacy redaction. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `codesign --deep` | Deprecated for signing since macOS 13. Documented by Apple as "considered harmful". Doesn't apply per-file flags correctly. | Sign nested executables individually, inside-out (`mole` first, then `.app`). |
| `BackgroundTasks` framework / `BGAppRefreshTask` | Not available on native macOS apps — iOS / iPadOS / tvOS / Mac Catalyst only. | `launchd` user `LaunchAgent` plist installed to `~/Library/LaunchAgents/`. |
| `altool` for notarization | Apple deprecated it for notarization in favour of `notarytool`. | `xcrun notarytool submit --wait` + `xcrun stapler staple`. |
| `ObservableObject` + `@Published` for new code | Coarser-grained invalidation, more recompiles, slower. macOS 14 deployment target makes the Observation framework available unconditionally. | `@Observable` macro everywhere. |
| `ChartsOrg/Charts` (formerly Daniel Cohen Gindi's iOS Charts) | Cross-platform abstraction overhead, large binary footprint, declarative-SwiftUI-mismatch. | Apple's Swift Charts for line/bar/area; custom `Canvas` (or YMTreeMap) for the disk treemap. |
| Sparkle 1.x (DSA) | Deprecated signing scheme. | Sparkle 2.9.x with EdDSA (ed25519). |
| MAS-style App Sandbox | Project decision: shipping outside App Store. Sandbox would block deep cleans. | Hardened Runtime only. No `com.apple.security.app-sandbox`. |
| Reading `mole` stdout with `Pipe.readabilityHandler` and synchronous `String(data:)` | Famous deadlock pattern with `Process` — pipe buffer fills, child blocks on write, `terminationHandler` never fires. | Drain stdout *and* stderr concurrently into `AsyncThrowingStream<Data, Error>` from the inside of an actor; parse line-delimited JSON as it arrives. |
| `Process.launchPath` (deprecated API) | Deprecated. | `Process.executableURL`. |
| Fastlane Match for code signing | Designed for App Store team workflows. Overkill for one Developer ID cert on one Mac + one CI runner. | Store the cert + private key as a base64 secret in GitHub Actions; `security import` into a temp keychain at the start of each CI run; delete keychain on exit. |
| `print()` for logging | Not captured by Console.app, no privacy controls, no levels. | `os.Logger(subsystem: "com.<you>.molebar", category: "<area>")`. |

---

## Stack Patterns by Variant

**If the disk analyzer becomes a separate full window with rich interaction (v2):**
- Promote the analyzer to its own `WindowGroup` or `Window` scene, keep the menu bar as `MenuBarExtra`. The activation policy juggle (`NSApplication.shared.setActivationPolicy(.regular)` while a window is open, `.accessory` otherwise) is the standard pattern documented by Steipete et al.
- Consider importing YMTreeMap at this point if `Canvas` rendering is no longer fast enough for animations.

**If contributors arrive and the `project.pbxproj` starts merge-conflicting:**
- Adopt XcodeGen first (lower learning cost than Tuist).
- Move to Tuist only when build caching becomes valuable, i.e., multiple modules.

**If SMJobBless / privileged helper becomes necessary (e.g., to drop the `osascript` password prompt for repeat operations):**
- Use the modern `SMAppService` API (macOS 13+), *not* the deprecated `SMJobBless` flow. This is materially harder to get notarized and signed correctly, so defer until user feedback proves the password-prompt friction is real.

**If the project ever pursues MAS distribution:**
- Strip every cleaning operation that requires a path outside the sandbox and ship a "lite" SKU. The constraint document already rules this out — keep ruling it out.

**If `mole` upstream stops shipping or pivots:**
- Architectural insurance: keep the CLI orchestrator behind a protocol so a Swift-native re-implementation could slot in. The constraint document already calls for this UI-agnostic core split.

---

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| Sparkle 2.9.x | macOS 10.13+ (we target 14+) | Sparkle's own floor is older than ours; safe. |
| Swift 6.x toolchain | Xcode 16.3+ | Required for swift-subprocess 0.4+ if/when we adopt it. |
| swift-snapshot-testing 1.x | XCTest, Swift 5.7+ | Compatible with Swift 6 strict concurrency mode. |
| `MenuBarExtra` | macOS 13.0+ | Our floor is macOS 14, so safe. |
| `@Observable` / Observation framework | macOS 14.0+ | Exactly our floor. |
| Swift Charts | macOS 13.0+ (richer APIs land each release) | Treemap support is **not** in Swift Charts at any version — implement custom. |
| Hardened Runtime | macOS 10.14+ | Required for notarization. |
| `notarytool` | Xcode 13+ | Always available on macOS 14+ runner. |
| `auto_updates true` Cask stanza | brew current | Required so Brew doesn't fight Sparkle on updates. |

---

## Sources

### High-confidence (official / authoritative)

- [Apple Developer — Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime) — entitlements, library validation, `-o runtime`
- [Apple Developer — Configuring the hardened runtime](https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime) — embedded executable signing
- [Apple Developer — Observation framework](https://developer.apple.com/documentation/Observation) — macOS 14 minimum, `@Observable` semantics
- [Apple Developer — Migrating from ObservableObject to @Observable](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro) — official migration guidance
- [Apple Developer — BGAppRefreshTask](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask) — confirms iOS/iPadOS/tvOS/Catalyst availability (no native macOS)
- [Apple Developer — Swift Charts](https://developer.apple.com/documentation/charts) — supported chart marks (no treemap)
- [Apple Developer — Scheduling Timed Jobs (launchd)](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/ScheduledJobs.html) — `StartCalendarInterval`
- [Apple Developer Forums — `--deep` Considered Harmful](https://forums.developer.apple.com/forums/thread/129980) — Quinn "The Eskimo!" on inside-out signing
- [Apple Developer Forums — Right way to asynchronously wait for a Process to terminate](https://forums.swift.org/t/right-way-to-asynchronously-wait-for-a-process-to-terminate/64036) — `Process` + async/await patterns
- [Apple TN2206 — macOS Code Signing in Depth](https://developer.apple.com/library/archive/technotes/tn2206/_index.html) — bundle structure, embedded executables
- [Sparkle official documentation](https://sparkle-project.org/documentation/) — programmatic SwiftUI setup, EdDSA key generation, Apple Code Signing verification
- [Sparkle — Upgrading from previous versions](https://sparkle-project.org/documentation/upgrading/) — DSA → EdDSA migration
- [Sparkle — Publishing an update](https://sparkle-project.org/documentation/publishing/) — `generate_appcast`, signed appcast
- [Sparkle on Swift Package Index](https://swiftpackageindex.com/sparkle-project/Sparkle) — current version, SPM URL
- [GitHub — Sparkle releases/tags page](https://github.com/sparkle-project/Sparkle/tags) — confirms 2.9.1 (March 2026) is current stable
- [GitHub — swiftlang/swift-subprocess](https://github.com/swiftlang/swift-subprocess) — 0.4.0 March 2026, 1.0 review concludes April 2026
- [Swift Forums — SF-0037: Subprocess 1.0 review](https://forums.swift.org/t/review-sf-0037-subprocess-1-0/86004) — pre-1.0 status
- [Swift Forums — Subprocess 1.0 pitch](https://forums.swift.org/t/pitch-subprocess-1-0/85589) — API direction
- [Swift.org — Swift 6.2 release notes](https://www.swift.org/blog/swift-6.2-released/) — Subprocess introduction
- [Homebrew — Cask Cookbook](https://docs.brew.sh/Cask-Cookbook) — `auto_updates true` stanza, livecheck patterns
- [Homebrew — `brew livecheck`](https://docs.brew.sh/Brew-Livecheck) — strategies for GitHub releases
- [GitHub — pointfreeco/swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) — snapshot strategies, XCTest integration

### Medium-confidence (community / blog / synthesised)

- [SwiftLee — OSLog and unified logging as recommended by Apple](https://www.avanderlee.com/debugging/oslog-unified-logging/) — subsystem/category conventions
- [Donny Wals — Modern logging with the OSLog framework](https://www.donnywals.com/modern-logging-with-the-oslog-framework/) — best-practice categorisation
- [Steipete — Showing Settings from macOS Menu Bar Items: A 5-Hour Journey (2025)](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items) — `MenuBarExtra` real-world friction
- [Multi.app blog — Pushing the limits of NSStatusItem](https://multi.app/blog/pushing-the-limits-nsstatusitem) — `NSStatusItem` advanced patterns
- [JPToroDev/FontSwitch (GitHub)](https://github.com/JPToroDev/FontSwitch) — reference SwiftUI menu-bar app combining `MenuBarExtra`, AppKit interop, and Sparkle 2
- [TrozWare — Moving from Process to Subprocess (2025)](https://troz.net/post/2025/process-subprocess/) — migration patterns
- [Tuist blog — Why generate Xcode projects in 2025](https://tuist.dev/blog/2025/02/25/project-generation) — when project generation pays off
- [Jesse Squires — A simple fastlane setup for solo indie developers](https://www.jessesquires.com/blog/2024/01/22/fastlane-for-indies/) — argument against Fastlane for solo
- [Federico Terzi — Automatic code-signing and notarization for macOS apps using GitHub Actions](https://federicoterzi.com/blog/automatic-code-signing-and-notarization-for-macos-apps-using-github-actions/) — base64-cert-into-temp-keychain pattern
- [orchetect/MenuBarExtraAccess (GitHub)](https://github.com/orchetect/MenuBarExtraAccess) — `MenuBarExtra` ↔ `NSStatusItem` bridge
- [LanikSJ/homebrew-bump-cask (GitHub Action)](https://github.com/LanikSJ/homebrew-bump-cask) — automated Cask bump on release
- [BleepingSwift — @AppStorage vs UserDefaults vs SwiftData](https://bleepingswift.com/blog/appstorage-vs-userdefaults-vs-swiftdata) — persistence-choice decision frame
- [phalladar/MacDirStat (GitHub)](https://github.com/phalladar/MacDirStat) — reference SwiftUI disk analyzer with treemap (note: Swift 6 / macOS 15 — treats macOS 14 as a hard floor for *us*)
- [yahoo/YMTreeMap (GitHub)](https://github.com/yahoo/YMTreeMap) — Swift treemap layout engine, fallback if Canvas is too slow

### Low-confidence (single-source / training-data only — flagged for validation during phase research)

- The exact set of entitlements required when launching the bundled `mole` binary: validated only via community search, not test. Phase 1 (CLI orchestration) should produce a notarization smoke-test that confirms the minimal entitlement set. **Validate during Phase 1.**
- Whether `osascript … with administrator privileges` is sufficient for *every* destructive operation `mole` performs (e.g., Spotlight reindex, network reset). Mole's docs imply yes; concrete behaviour should be verified per-operation. **Validate during Phase 2 / per-feature.**
- Whether ad-hoc-signed binaries downloaded by the CLI auto-updater pass Gatekeeper's quarantine layer when invoked as subprocesses by an already-notarized parent. The community evidence says yes (Gatekeeper does not re-evaluate subprocess signatures of an approved parent), but a deliberate end-to-end test is warranted. **Validate during the auto-update phase.**
- Performance ceiling of `Canvas`-based squarified treemap vs YMTreeMap at 100k+ filesystem entries — only benchmarkable. **Validate during the disk-analyzer phase.**

---

*Stack research for: public, MIT-licensed, notarized, single-developer macOS 14+ menu bar app wrapping a third-party CLI (Mole), distributed via GitHub Releases + Homebrew Cask + Sparkle.*

*Researched: 2026-04-27*
