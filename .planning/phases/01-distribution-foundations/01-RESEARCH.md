# Phase 1: Distribution Foundations - Research

**Researched:** 2026-04-27
**Domain:** macOS app CI/CD pipeline (Xcode + SwiftPM workspace bootstrap, Sparkle 2.x EdDSA appcast, create-dmg, GitHub Actions, gh-pages)
**Confidence:** HIGH on Sparkle/CI/create-dmg/GH-Pages topology; MEDIUM on `tw93/mole` bundling recipe (the upstream binary topology differs materially from what `01-CONTEXT.md` D-14 assumes — see Pitfall A1); HIGH on MenuBarExtra `.window` style and SwiftUI Sparkle wiring.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01 (signing deferred):** Apple Developer ID signing is **deferred** for Phase 1. The CI pipeline includes signing/notarization/staple/Cask jobs as scaffolded stubs (skip-on-empty-secret pattern: `if: ${{ secrets.X != '' }}`) so they activate the moment the Dev ID and ASC API Key land in GitHub Actions secrets. Phase 1.5 turns them on and ships the first real signed release.
- **D-02 (repo):** Repo lives at `github.com/romatroskin/molebar` — personal namespace, public, MIT-licensed. No org for v1.
- **D-03 (bundle ID):** macOS bundle identifier is `app.molebar.MoleBar` (reverse-DNS based on hypothetical `molebar.app` domain). Locked into `Info.plist`, Sparkle's `SUFeedURL` resolution, Keychain ACLs, and the LaunchAgent label that Phase 7 will use.
- **D-04 (Cask deferred):** Homebrew Cask deferred to Phase 1.5. Phase 1 ships only the GitHub Releases `.dmg` + Sparkle appcast.
- **D-05 (EdDSA key origin):** Private key generated **locally on the developer Mac** via Sparkle's `generate_keys` tool, then imported into the **macOS Keychain** with a strong password. Key file on disk deleted; Keychain entry is canonical.
- **D-06 (key backup):** iCloud Keychain sync is the backup strategy.
- **D-07 (CI delivery):** GitHub Actions repository secret named `SPARKLE_EDDSA_PRIVATE_KEY`. One-time-bootstrapped by exporting from local Keychain and pasting into GH UI.
- **D-08 (`SUPublicEDKey` frozen):** Public key embedded in `Info.plist`. Once the first real release is published, frozen forever — every prior MoleBar install only accepts updates signed by the matching private key.
- **D-09 (runner):** Release builds run on **GitHub-hosted `macos-15`**.
- **D-10 (notarization auth):** App Store Connect API Key (Issuer ID + Key ID + `.p8`). Plumbing wired in Phase 1 with empty-secret stub-out. Secrets `ASC_API_KEY_ID`, `ASC_ISSUER_ID`, `ASC_API_KEY_P8` added in Phase 1.5.
- **D-11 (CI trigger):** Tag push in `vX.Y.Z` semver format. `git tag v0.0.1 && git push --tags` triggers the release workflow.
- **D-12 (appcast URL):** `https://puffpuff.dev/molebar/appcast.xml` via `gh-pages` branch. URL locked into `Info.plist`'s `SUFeedURL`.
- **D-13 (0.0.1 dummy scope):** `MenuBarExtra(style: .window)` stub with: tiny popover showing "MoleBar 0.0.1 — nothing here yet"; "Check for Updates…" menu item wired to `SPUUpdater.checkForUpdates()`; Quit item.
- **D-14 (mole binary bundling):** Real `mole` bundled at `Contents/Helpers/mole`, **Universal2** (lipo of arm64+x86_64). Pinned upstream version recorded in `mole-version.txt`. Smoke test invokes once with `--version`. **⚠ Critical caveat:** as written, this decision is technically infeasible — `mole` is a Shell script, not a Mach-O. See Pitfall A1 below for the corrected recipe (lipo applies only to the two Go helpers `analyze-go` and `status-go`; the Shell wrapper + lib/ tree must be copied as-is).
- **D-15 (versioning):** `CFBundleShortVersionString` = git tag's semver (`v0.0.1` → `0.0.1`); `CFBundleVersion` = GitHub Actions run number. Injected via `xcodebuild` build settings; `Info.plist` uses `$(MARKETING_VERSION)` and `$(CURRENT_PROJECT_VERSION)` placeholders.
- **D-16 (DMG layout):** Standard drag-to-Applications via shell `create-dmg/create-dmg`. Background image at `dmg-assets/background.png`; falls back to no-background two-icon layout if missing.
- **D-17 (bundle path):** `Contents/Helpers/mole` for the bundled CLI fallback. Phase 8's auto-updated copy lives in `~/Library/Application Support/MoleBar/bin/mole`. Resolver prefers user copy.
- **D-18 (scaffolded-but-skipped CI pattern):** `.github/workflows/release.yml` already contains every step (sign, notarize, staple, Cask bump). Each guarded by `if: ${{ secrets.SECRET_NAME != '' }}`. Phase 1.5's work is mostly **adding the secrets**, not editing the workflow file.

### Claude's Discretion

- Exact pinned upstream `tw93/mole` version for the Phase 1 bundled binary — the planner picks the latest stable tagged release at the time Phase 1 ships, records it in `mole-version.txt`, and pins it. **Recommendation: pin `V1.36.2` (April 27, 2026)** — verified latest stable tag.
- Exact disk layout of `dmg-assets/` (background dimensions, icon placement, window size) — sensible defaults consistent with `create-dmg` examples.
- README's exact prose — contributor-friendly per OSS-01, sections on what MoleBar is, install, build-from-source, license, clear `tw93/mole` upstream attribution. Tone matches Mole project ethos.

### Deferred Ideas (OUT OF SCOPE)

- **GitHub Actions Environment with required reviewer approval before release jobs run** — discussed, not selected for v1.
- **OIDC federation to AWS Secrets Manager / 1Password Connect for CI secrets** — overkill for solo project.
- **Submitting Cask to `homebrew/cask` main repo** — personal tap is the v1 channel; main-repo submission is post-v1.
- **Custom domain (`molebar.app`)** — bundle ID anticipates it but acquiring the domain is post-v1.
- **`CFBundleVersion = git short SHA`** — discussed; CI run number won out for monotonic ordering.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description (verbatim from REQUIREMENTS.md) | Research Support |
|----|---------------------------------------------|------------------|
| **DIST-04** | "A signed/notarized `.dmg` is produced via `create-dmg` for every release" — Phase 1 produces UNSIGNED `.dmg`; signing is stubbed per D-01. | `create-dmg/create-dmg` shell tool (Homebrew formula `create-dmg` v1.2.3+); flags documented in §`create-dmg` Invocation. |
| **DIST-05** | "GitHub Actions workflow builds, signs, notarizes, staples, packages, and uploads release artifacts on tag push" — sign/notarize/staple stubbed; build + package + upload active. | macos-15 runner ships Xcode 16.4 default; full workflow shape documented in §GitHub Actions Workflow. |
| **DIST-06** | "Sparkle 2.x in-app updater fetches a signed appcast from a project-controlled URL with EdDSA verification" | Sparkle 2.9.1 (Mar 28, 2026 stable); SPM dependency; `SPUStandardUpdaterController` + `CheckForUpdatesView` pattern documented in §Sparkle Setup. |
| **DIST-08** | "A round-trip 0.0.1 → 0.0.2 update succeeds end-to-end before any feature ships (Sparkle smoke test)" | Smoke test plan documented in §Smoke Test Plan; reproducible 5-step procedure. |
| **OSS-01** | "Repo is public, MIT-licensed, with a `LICENSE` file and a contributor-friendly `README.md`" | README structure + tone documented in §README Content. |
| **OSS-04** | "Signing keys, EdDSA private keys, and Developer ID secrets live in GitHub Actions secrets — never in the repo, never logged" | EdDSA-key-via-Keychain → GH Actions secret bootstrap documented in §EdDSA Key Tooling; `add-mask` + temp file with `umask 077` + `shred` pattern in §Secret Hygiene. |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

CLAUDE.md is the GSD-managed project context (sourced from PROJECT.md + research/STACK.md + PITFALLS.md). The directives that apply to Phase 1 specifically:

- **Tech stack:** Swift + SwiftUI primary; AppKit only where required.
- **CLI dependency:** Bundle the `mole` binary inside the `.app`; auto-update separately via Phase 8 (NOT this phase).
- **Distribution:** GitHub Releases (signed/notarized `.dmg`) + Homebrew Cask + Sparkle 2 — Phase 1 delivers unsigned DMG + Sparkle only; Cask is Phase 1.5.
- **License:** MIT, public repository from day one — Phase 1 directly delivers this.
- **Apple Developer ID:** Required for notarization — DEFERRED per D-01.
- **No telemetry, no analytics:** Sparkle's appcast check is the ONLY allowed outbound network call in this phase. (Verified by Phase 8's Little Snitch test, but the invariant must hold from day one.)

## Summary

Phase 1 is the canonical "ship a 0.0.1 dummy through every distribution-layer mechanism before features exist" pattern. The unrotatable decisions (Sparkle EdDSA public key, bundle ID, appcast URL, repo identity) are locked here so a future user installing v0.0.1 can be safely upgraded to every subsequent release.

Six requirements span five distinct technical workstreams: (1) Xcode project + SwiftPM-workspace bootstrap; (2) Sparkle 2.9.1 wiring with EdDSA-signed appcast; (3) GitHub Actions release workflow with scaffolded-but-stubbed signing; (4) `create-dmg` packaging; (5) gh-pages-hosted appcast publication; (6) Universal2 bundling of the upstream `tw93/mole` Mole CLI.

**Primary recommendation:** Treat the workflow file (`.github/workflows/release.yml`) as the single source of truth for distribution. Implement it complete-with-stubs in Phase 1 (sign/notarize/staple/Cask jobs all present, all guarded by `if: ${{ secrets.X != '' }}`); the Phase 1.5 PR adds secrets and removes guards in a minimal, auditable diff.

**Critical correction surfaced during research:** `01-CONTEXT.md` decision D-14 says "lipo arm64+x86_64 of upstream `tw93/mole` release into Universal2 binary." This is technically infeasible as written — `mole` itself is a **Shell script**, not a Mach-O. The upstream releases ship two per-arch Go helpers (`analyze-darwin-{arm64,amd64}` and `status-darwin-{arm64,amd64}`); the `mole` command is a Shell wrapper that calls them and references a sibling `lib/` tree of cleanup modules. The corrected bundling recipe (lipo only the two Go helpers; copy the rest of the tree verbatim) is documented in §Mole Binary Bundling Recipe. The planner MUST adopt the corrected recipe — D-14 cannot be implemented as worded.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Xcode project / target config | Build system (`.xcodeproj`) | — | Single-developer; native Xcode wins over Tuist/XcodeGen. |
| SwiftPM module shape (`MoleBarCore`/`Stores`/`UI`) | Local SwiftPM package | Xcode app target consumes it | Roadmap-mandated split; Phase 1 introduces empty modules so Phase 2 has a place to land. |
| MenuBarExtra UI host | macOS app target (SwiftUI) | — | `MenuBarExtra(style: .window)` is the SwiftUI primitive. |
| Sparkle update orchestration | macOS app target | SPM package (Sparkle) | `SPUStandardUpdaterController` lives in the app; SPM provides the framework. |
| EdDSA signing of `.dmg` | CI (GitHub Actions runner) | Sparkle SPM artifact bundle (`sign_update`) | Signing happens during release, not in app code. |
| Appcast XML generation | CI (GitHub Actions) | Inline bash + `sign_update` output | Single XML file, single artifact per release; `generate_appcast` not strictly needed for one-DMG releases. |
| Appcast hosting | GitHub Pages (`gh-pages` branch) | — | Free, HTTPS, sufficient for v1. |
| Release artifact hosting | GitHub Releases | — | tag-triggered, public, free; the standard. |
| `mole` binary lipo'ing | CI (download + lipo step) | — | Done at release time so the bundle has the merged Universal2. |
| Bundle path resolution at runtime | macOS app target (Phase 2's `MoleResolver`) | — | Out of scope for Phase 1 except for smoke-test launch validation. |

## Standard Stack

### Core

| Library / Tool | Version | Purpose | Why Standard |
|----------------|---------|---------|--------------|
| Sparkle | 2.9.1 (released Mar 28, 2026) | In-app auto-update with EdDSA-signed appcast | De facto standard for non-MAS macOS app updates. SwiftPM-native, EdDSA mandatory in 2.x. **VERIFIED** via [Sparkle tags](https://github.com/sparkle-project/Sparkle/tags). |
| `create-dmg/create-dmg` (shell) | 1.2.3+ (Homebrew bottle as of researched date) | Build distributable `.dmg` with drag-to-Applications layout | Lightweight, no Python/Node dep, used widely in CI. **VERIFIED** via `brew info create-dmg`. |
| `xcodebuild` | bundled with Xcode 16.4 (default on macos-15 runner) | Archive + export | Apple-blessed build tool. **VERIFIED** via [actions/runner-images macos-15 readme](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md). |
| `xcrun notarytool` | bundled (Xcode 13+) | Notarization (Phase 1.5 — STUBBED in Phase 1) | The only supported notarization CLI since `altool` deprecation. |
| `xcrun stapler` | bundled | Staple notarization ticket (Phase 1.5 — STUBBED in Phase 1) | Pair with `notarytool`. |
| `gh` CLI | 2.90+ (macos-15 runner pre-installed) | GitHub Releases automation | Standard for indie macOS apps. |
| `lipo` | bundled (Xcode CLT) | Combine arm64 + x86_64 Mach-O into Universal2 | Native Apple toolchain. |
| `peaceiris/actions-gh-pages` | v4.0.0 (Apr 8, 2024 — latest stable) | Commit appcast.xml to gh-pages branch from CI | De facto standard for gh-pages publication from GH Actions. **VERIFIED.** |
| `softprops/action-gh-release` | v3.0.0 (Apr 12, 2026) | Upload .dmg as GitHub Release asset on tag push | Most-used GH Release publisher. **VERIFIED.** |
| `actions/checkout` | v4 | Standard checkout step | GH Actions stdlib. |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `pointfreeco/swift-snapshot-testing` | 1.x latest | Snapshot tests for SwiftUI views | Phase 3+ — NOT this phase. Mention only because the test target shape created in Phase 1 will host these later. |
| `orchetect/MenuBarExtraAccess` | latest | `MenuBarExtra` ↔ `NSStatusItem` bridge | NOT this phase. Add only when programmatic open/close need surfaces (Phase 3+). |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Native `.xcodeproj` | XcodeGen / Tuist | Tuist's wins (caching, modular generation, merge-conflict avoidance) only matter at team scale. Single-dev avoids that. **STACK.md decision: native Xcode project.** Use **XcodeGen** only if `project.pbxproj` merge conflicts start to bite. |
| `create-dmg` (shell) | `dmgbuild` (Python) | More customisable but heavier (Python dep in CI). Overkill here. |
| `create-dmg` (shell) | Sindresorhus's `create-dmg` (Node/npm) | Adds Node toolchain to CI for nothing. |
| `peaceiris/actions-gh-pages` | Direct `git push` from CI script | peaceiris handles `keep_files`, default-branch protection, deploy-key vs `GITHUB_TOKEN` correctly. Hand-rolled is fragile. |
| `softprops/action-gh-release` | `gh release create` (manual) | Both work; `softprops` is one-step + idempotent for re-runs. Pick one. |
| Sparkle's `generate_appcast` | Inline bash + `sign_update` | `generate_appcast` is best for multi-release scanning. For a single-DMG-per-release flow, hand-rolled XML + one `sign_update` call is simpler and more auditable. **Recommended for Phase 1.** Switch to `generate_appcast` if/when delta updates are introduced (post-v1). |

**Installation:** All Sparkle dependencies are added through Xcode's File → Add Package Dependencies pointing at `https://github.com/sparkle-project/Sparkle` (target: `MoleBar` app target, version rule "Up to Next Major Version" from `2.9.1`).

CI runner needs `create-dmg` installed:
```bash
brew install create-dmg
```

**Version verification (performed during research):**
- Sparkle 2.9.1 — verified via [github.com/sparkle-project/Sparkle/tags](https://github.com/sparkle-project/Sparkle/tags), released Mar 28, 2026. **[VERIFIED]**
- `create-dmg` 1.2.3 — verified via `brew info create-dmg` (output: "stable 1.2.3 (bottled)"). **[VERIFIED]**
- macos-15 runner ships Xcode 16.4 default + 16.0/16.1/16.2/16.3 also installed. macOS 15.7.5. **[VERIFIED]**
- `tw93/mole` latest stable: `V1.36.2` (Apr 27, 2026). **[VERIFIED]**
- `peaceiris/actions-gh-pages@v4.0.0` (Apr 8, 2024). **[VERIFIED]**
- `softprops/action-gh-release@v3.0.0` (Apr 12, 2026). **[VERIFIED]**

## Architecture Patterns

### System Architecture Diagram

```
                    ┌────────────────────────────────────────────┐
                    │     Developer Mac (one-time bootstrap)      │
                    │                                             │
                    │  generate_keys ──► macOS Keychain (private) │
                    │       │                                     │
                    │  generate_keys -x ──► /tmp/sparkle.key       │
                    │       │                                     │
                    │  copy/paste contents to GH Secret           │
                    │       │ SPARKLE_EDDSA_PRIVATE_KEY            │
                    │       ▼                                     │
                    └───────│─────────────────────────────────────┘
                            │
                            ▼
   git tag v0.0.1                               GitHub Actions Secrets
   git push --tags                              ┌──────────────────────────┐
        │                                       │ SPARKLE_EDDSA_PRIVATE_KEY │
        ▼                                       │ ASC_API_KEY_ID (stub)    │
   ┌─────────────────────────────────┐          │ ASC_ISSUER_ID (stub)     │
   │  GitHub: tag-push event         │◄─────────┤ ASC_API_KEY_P8 (stub)    │
   └────────┬────────────────────────┘          │ MACOS_CERT (stub)        │
            │                                   │ MACOS_CERT_PWD (stub)    │
            ▼                                   └──────────────────────────┘
   ┌────────────────────────────────────────────────────────────────────────┐
   │  .github/workflows/release.yml on macos-15 runner                       │
   │                                                                         │
   │  1. Checkout (actions/checkout@v4)                                      │
   │  2. Select Xcode 16.4 (sudo xcode-select -s /Applications/Xcode_16.4)   │
   │  3. Download tw93/mole V1.36.2 release artifacts:                        │
   │     - analyze-darwin-arm64, analyze-darwin-amd64                        │
   │     - status-darwin-arm64, status-darwin-amd64                          │
   │  4. lipo -create ... -output Helpers/analyze-go                         │
   │     lipo -create ... -output Helpers/status-go                          │
   │  5. git clone tw93/mole at V1.36.2 → copy mole + lib/ into Helpers/     │
   │  6. Compute MARKETING_VERSION from $GITHUB_REF (strip refs/tags/v)      │
   │     CURRENT_PROJECT_VERSION=$GITHUB_RUN_NUMBER                          │
   │  7. xcodebuild archive ... MARKETING_VERSION=0.0.1 \                    │
   │           CURRENT_PROJECT_VERSION=$GITHUB_RUN_NUMBER                    │
   │  8. xcodebuild -exportArchive ... → MoleBar.app                         │
   │  9. [STUB] if: secrets.MACOS_CERT != ''                                 │
   │     codesign Helpers/* (inside-out)                                     │
   │     codesign MoleBar.app                                                │
   │ 10. create-dmg ... → MoleBar-0.0.1.dmg                                  │
   │ 11. [STUB] if: secrets.ASC_API_KEY_P8 != ''                             │
   │     notarytool submit + stapler staple                                  │
   │ 12. Decode SPARKLE_EDDSA_PRIVATE_KEY → /tmp/sparkle.key (umask 077)     │
   │     sign_update --ed-key-file /tmp/sparkle.key MoleBar-0.0.1.dmg        │
   │     → captures sparkle:edSignature + length                             │
   │     shred /tmp/sparkle.key                                              │
   │ 13. Render appcast.xml from template (heredoc bash)                     │
   │ 14. softprops/action-gh-release@v3 → upload .dmg to v0.0.1 GH Release   │
   │ 15. peaceiris/actions-gh-pages@v4 → commit appcast.xml to gh-pages       │
   │     (publish_dir contains ONLY appcast.xml; keep_files=true)            │
   └────────┬────────────────────────────────────────────────────────────────┘
            │
            ▼
   ┌──────────────────────────────────────────────────────┐
   │ puffpuff.dev/molebar/appcast.xml (HTTPS)    │
   │ + github.com/romatroskin/molebar/releases/v0.0.1     │
   │   - MoleBar-0.0.1.dmg                                │
   └────────┬─────────────────────────────────────────────┘
            │
            ▼ (user installs v0.0.1, clicks Check for Updates…)
   ┌────────────────────────────────────────────────────────┐
   │  MoleBar.app on user Mac                                │
   │                                                         │
   │  Info.plist:                                            │
   │    SUFeedURL = .../molebar/appcast.xml                  │
   │    SUPublicEDKey = <FROZEN base64>                      │
   │    SURequireSignedFeed = YES (note: optional field)     │
   │  ┌──────────────────────────┐                           │
   │  │ MenuBarExtra(.window)    │ ←── stub popover           │
   │  │   Text("MoleBar 0.0.1")  │                           │
   │  │   Button("Check for      │                           │
   │  │      Updates…")          │                           │
   │  │   Button("Quit")         │                           │
   │  └────────┬─────────────────┘                           │
   │           ▼                                             │
   │  SPUStandardUpdaterController.checkForUpdates()         │
   │           │                                             │
   │           ▼                                             │
   │  HTTPS GET appcast.xml                                  │
   │  Verify EdDSA signature on enclosure                    │
   │  Compare CFBundleShortVersionString vs sparkle:version  │
   │  → if newer, prompt user → download → install → relaunch│
   └────────────────────────────────────────────────────────┘
```

### Recommended Project Structure

```
molebar/                           # repo root (github.com/romatroskin/molebar)
├── .github/
│   └── workflows/
│       └── release.yml            # tag-push triggered; complete-with-stubs (D-18)
├── .gitignore                     # excludes build/, DerivedData/, *.xcuserdata, sparkle keys
├── LICENSE                        # MIT
├── LICENSE-MOLE.txt               # tw93/mole MIT attribution (Phase 2 owns CORE-08; can land here too)
├── README.md                      # OSS-01 — contributor-friendly README
├── mole-version.txt               # pinned upstream tw93/mole version (e.g., "V1.36.2")
├── dmg-assets/
│   └── background.png             # DMG drag-to-Applications hint background (D-16)
├── MoleBar.xcodeproj/             # native Xcode project (D-17 architectural)
├── MoleBar/                       # app target source
│   ├── Info.plist                 # bundle ID app.molebar.MoleBar (D-03), SUFeedURL (D-12),
│   │                              # SUPublicEDKey (D-08), LSUIElement=YES, version placeholders
│   ├── MoleBar.entitlements       # Hardened Runtime (Phase 1.5 effective; Phase 1: empty file
│   │                              # so the entitlement plumbing exists even when --options runtime
│   │                              # isn't applied)
│   ├── MoleBarApp.swift           # @main App entry; MenuBarExtra(.window); SPUStandardUpdaterController
│   ├── PopoverRootView.swift      # The stub popover content — "MoleBar 0.0.1" + buttons
│   └── CheckForUpdatesView.swift  # SwiftUI wrapper around updater.checkForUpdates() — Sparkle pattern
├── MoleBarTests/                  # XCTest target (empty in Phase 1; future tests land here)
└── Packages/
    └── MoleBarPackage/            # local SwiftPM package — module split goes here in Phase 2
        ├── Package.swift          # Phase 1: declares 3 empty library products MoleBarCore,
        │                          # MoleBarStores, MoleBarUI; Phase 2 fills MoleBarCore.
        └── Sources/
            ├── MoleBarCore/       # placeholder file (e.g., a // TODO: Phase 2 marker)
            ├── MoleBarStores/     # placeholder
            └── MoleBarUI/         # placeholder
```

**Note on the SwiftPM split:** Phase 1 only writes UI code (the MenuBarExtra stub) and Sparkle wiring. The local SwiftPM package is created with EMPTY module products so Phase 2 has a place to land `MoleClient`. The app target imports nothing from `MoleBarCore` in Phase 1; the import statement gets added in Phase 2.

### Pattern 1: SwiftUI App with Sparkle "Check for Updates…" Wired

**What:** Wire `SPUStandardUpdaterController` into a SwiftUI `App` and expose a `CheckForUpdatesView` that drives `updater.checkForUpdates()` from the MenuBarExtra popover.

**When to use:** Phase 1's MoleBarApp.swift entry point. Mandatory pattern per D-13.

**Example (verified against [Sparkle programmatic-setup docs](https://sparkle-project.org/documentation/programmatic-setup/)):**

```swift
import SwiftUI
import Sparkle

// CheckForUpdatesViewModel observes updater.canCheckForUpdates
// so the button auto-disables while a check is in-flight.
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}

@main
struct MoleBarApp: App {
    private let updaterController: SPUStandardUpdaterController

    init() {
        // Sparkle's SwiftUI-blessed setup. startingUpdater: true ensures
        // automatic check is scheduled per SUEnableAutomaticChecks Info.plist.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        MenuBarExtra("MoleBar", systemImage: "circle.dotted") {
            VStack(alignment: .leading, spacing: 6) {
                Text("MoleBar 0.0.1 — nothing here yet")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top)
                Divider()
                CheckForUpdatesView(updater: updaterController.updater)
                    .buttonStyle(.borderless)
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("q")
            }
            .padding(.bottom, 8)
            .frame(width: 240)
        }
        .menuBarExtraStyle(.window)
    }
}
```

Sources:
- [Sparkle: Programmatic Setup](https://sparkle-project.org/documentation/programmatic-setup/) **[CITED]**
- [Apple: MenuBarExtraStyle.window — macOS 13+](https://developer.apple.com/documentation/swiftui/menubarextrastyle) **[CITED]**

### Pattern 2: Info.plist Keys Required by Sparkle 2.x (Unsandboxed)

**What:** Minimum viable `Info.plist` for Sparkle 2.x in a Hardened-Runtime-only (non-Sandboxed) app.

**Required keys (verified):**

| Key | Value | Notes |
|-----|-------|-------|
| `CFBundleIdentifier` | `app.molebar.MoleBar` | Per D-03. |
| `CFBundleVersion` | `$(CURRENT_PROJECT_VERSION)` | Injected by xcodebuild (D-15). |
| `CFBundleShortVersionString` | `$(MARKETING_VERSION)` | Injected by xcodebuild (D-15). |
| `LSUIElement` | `YES` (Boolean) | Menu-bar app, no Dock icon. |
| `LSMinimumSystemVersion` | `14.0` | macOS 14+ floor. |
| `SUFeedURL` | `https://puffpuff.dev/molebar/appcast.xml` | Per D-12. |
| `SUPublicEDKey` | `<base64 EdDSA pubkey>` | Per D-08; FROZEN after first release. |
| `SUEnableAutomaticChecks` | `YES` (Boolean) | Optional; controls scheduled background checks. |

**Optional but recommended:**

| Key | Value | Notes |
|-----|-------|-------|
| `SUScheduledCheckInterval` | `86400` (Integer) | Default daily check (in seconds). Avoid setting to "every launch" (Pitfall: spurious traffic). |
| `SUEnableInstallerLauncherService` | NOT NEEDED for unsandboxed apps | XPC services for sandboxed apps only. |
| `SUEnableDownloaderService` | NOT NEEDED for unsandboxed apps | Same. |
| `SURequireSignedFeed` | NOT REQUIRED in 2.x for EdDSA setups | EdDSA enclosure-signing is automatic when `SUPublicEDKey` is set. The `SURequireSignedFeed` key is for **feed-level** signing (additional layer); not needed for Phase 1. The CONTEXT.md mention of `SURequireSignedFeed=YES` reflects an older 1.x/early-2.x paradigm. **Decision: omit for Phase 1**, add only if a separate feed-signing layer is wanted. **[ASSUMED]** — research did not find a definitive Sparkle docs page stating the exact behavior of `SURequireSignedFeed` in 2.9.x, but Sparkle's own EdDSA enclosure verification is the primary security mechanism and is gated on `SUPublicEDKey`. Confirm with discuss-phase before locking. |

**Entitlements (`MoleBar.entitlements`):**

For Phase 1 (unsigned), this file can be empty (`<plist><dict/></plist>`) or absent. The plumbing should exist so Phase 1.5 only adds entries:
- `com.apple.security.cs.allow-jit` = NO (default)
- `com.apple.security.cs.disable-library-validation` = `<true/>` (only if needed; start without per STACK.md guidance)

Source: [Sparkle: Sandboxing](https://sparkle-project.org/documentation/sandboxing/) — confirms unsandboxed apps don't need the XPC service Info.plist keys. **[CITED]**

### Pattern 3: SwiftPM Workspace Bootstrap (Local Package)

**What:** Add a local `Packages/MoleBarPackage/` SwiftPM package with three empty library products. The Xcode app target adds it as a local package reference; this is the "SwiftPM workspace shape" that Phase 2's `MoleClient` will land into.

**`Packages/MoleBarPackage/Package.swift`:**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MoleBarPackage",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MoleBarCore", targets: ["MoleBarCore"]),
        .library(name: "MoleBarStores", targets: ["MoleBarStores"]),
        .library(name: "MoleBarUI", targets: ["MoleBarUI"]),
    ],
    dependencies: [
        // Phase 2+ adds dependencies here (e.g., swift-snapshot-testing)
    ],
    targets: [
        .target(name: "MoleBarCore"),
        .target(name: "MoleBarStores", dependencies: ["MoleBarCore"]),
        .target(name: "MoleBarUI", dependencies: ["MoleBarStores"]),
    ]
)
```

Each `Sources/<Module>/` should contain a single placeholder file (e.g., `Placeholder.swift` with a `// MARK: - Phase 2 lands here` comment) so SwiftPM doesn't fail with "missing source files."

**Note on Sparkle dependency:** Sparkle is added directly to the Xcode app target (NOT to the local SwiftPM package) — STACK.md guidance says SPM has gaps for app-target-specific concerns (entitlements, code-signing) and should be used as a dependency manager only, not project manager.

### Anti-Patterns to Avoid

- **Adding Sparkle to the local SwiftPM package** — leaks the dependency into modules that don't need it (Phase 2's `MoleBarCore` must remain UI-agnostic per ARCHITECTURE.md). Sparkle goes on the Xcode app target only.
- **Using `Package.swift` as the project root** — STACK.md explicitly forbids this. Native `.xcodeproj` is the source of truth.
- **Hand-coding `CFBundleShortVersionString` in Info.plist** — Phase 1 commits will overwrite it on every release; use `$(MARKETING_VERSION)` placeholder.
- **Using `set -x` anywhere in `release.yml`** — instant secret leak path. Use `add-mask` and `umask 077` instead. (Pitfall #12 from PITFALLS.md.)
- **Using `pull_request_target` event for the release workflow** — exposes secrets to forked PRs. The workflow MUST trigger only on `push` to tags. (Pitfall #12.)
- **Re-zipping or re-uploading a release artifact after `sign_update` ran** — the EdDSA signature becomes invalid; users get "improperly signed" failures. The release artifact and the `sparkle:edSignature` value MUST be locked together. (Pitfall #3 from PITFALLS.md.)

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Auto-update framework | A custom URLSession-based update fetcher | Sparkle 2.9.1 | Sparkle handles signature verification, delta updates, rollback, hardware/version requirements, localized prompts, App Translocation safety. |
| EdDSA signing of release artifacts | OpenSSL ed25519 commands | Sparkle's `sign_update` | `sign_update` produces the exact XML fragment Sparkle's verifier expects (`sparkle:edSignature` + length). Hand-rolled OpenSSL invocations fail Sparkle's strict format check. |
| EdDSA key generation + Keychain storage | OpenSSL + manual Keychain CLI | Sparkle's `generate_keys` | Handles Keychain ACLs, label format, and the `-x`/`-f` import/export paths Sparkle's other tools expect. |
| DMG packaging | Hand-rolled `hdiutil` invocations | `create-dmg/create-dmg` shell | Apple's `hdiutil` requires careful sequencing (create → mount → populate → set view options → unmount → convert to read-only); `create-dmg` has decade+ of edge cases baked in. |
| GitHub Release upload | Custom `curl` to GitHub API | `softprops/action-gh-release@v3` | Idempotent (re-runs don't duplicate); handles tag-vs-branch resolution; proper retry semantics. |
| GitHub Pages publish | Custom `git push` from CI | `peaceiris/actions-gh-pages@v4` | Handles the GITHUB_TOKEN-vs-deploy-key distinction; preserves the orphan branch correctly; `keep_files: true` semantics. |
| `xcodebuild`-driven version injection | sed/awk-rewriting Info.plist | `MARKETING_VERSION=X CURRENT_PROJECT_VERSION=Y` build settings | Apple-blessed; reproducible; does not touch source-controlled files. |
| Universal2 binary creation | Manual Mach-O surgery | `lipo -create A B -output AB` | Native Apple tool; handles fat-header generation correctly. |
| MenuBarExtra popover host | Hand-rolled `NSStatusItem` + `NSPopover` | SwiftUI `MenuBarExtra(style: .window)` | macOS 13+; thin shell architecture per CONFLICT 3 in SUMMARY.md (revisit only if blockers surface during Phase 3 testing). |

**Key insight:** Phase 1 is almost entirely "wire well-known tools together correctly." The bug surface is in the integration, not in any one component. Don't build alternatives to any of the tools above.

## Runtime State Inventory

> Phase 1 is greenfield bootstrap (creates new Xcode project, new repo, new GH repo settings). Listing what state will be CREATED (not what's being migrated):

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — greenfield. (Phase 1 doesn't touch any datastore.) | None. |
| Live service config | (1) GitHub repo settings: enable GitHub Pages on `gh-pages` branch root. (2) GitHub repo Branches: optionally protect `main`. (3) GitHub repo Secrets: `SPARKLE_EDDSA_PRIVATE_KEY` (real); `MACOS_CERT`/`MACOS_CERT_PWD`/`ASC_API_KEY_*` (Phase 1.5 — empty in Phase 1). (4) Push Protection enabled on the repo (free for public repos). | Manual one-time GH UI setup; planner must produce a checklist for the user. |
| OS-registered state | None — Phase 1 doesn't register LaunchAgents, login items, daemons, etc. (Phase 7's job.) | None. |
| Secrets and env vars | One real secret created in Phase 1: `SPARKLE_EDDSA_PRIVATE_KEY` (developer Mac local Keychain → exported via `generate_keys -x` → pasted into GH UI). All other release-related secrets are stubbed empty in Phase 1. The corresponding values are checked at workflow runtime via `if: ${{ secrets.X != '' }}`. | Documented bootstrap in §EdDSA Key Tooling. |
| Build artifacts / installed packages | None — there are no installed packages on user machines yet (no published release before this phase finishes). | None. |

**Nothing found in category:** Stored data, OS-registered state, build artifacts — verified by inspection of the empty-greenfield `mole_menu/` working tree (`ls -la` shows only `.planning/`, `CLAUDE.md`, `.git/`, `.claude/`).

## Common Pitfalls

### Pitfall A1: D-14's "Universal2 mole binary" is not literally implementable (P0)

**What goes wrong:** The phase context decision D-14 says "CI downloads both arm64 and x86_64 from a pinned upstream `tw93/mole` release, runs `lipo -create`, drops the result in the bundle." A naive read of this triggers the planner to write a CI step like `lipo -create mole-arm64 mole-amd64 -output mole`. **There is no `mole-darwin-arm64` artifact in `tw93/mole`'s GitHub Releases.** The actual upstream release artifacts are:
- `analyze-darwin-arm64`, `analyze-darwin-amd64` (Go binary)
- `status-darwin-arm64`, `status-darwin-amd64` (Go binary)

The `mole` command itself is a **Shell script** in the repository root that calls into `lib/` Shell modules and invokes `analyze-go` / `status-go` from `$CONFIG_DIR/bin/`. You cannot `lipo` a Shell script.

**Why it happens:** The upstream README says "Mole is built for macOS" and STACK.md references a "single binary"; the actual repo composition (Shell 81% / Go 19%) reveals on closer inspection that the Go portion is two helpers, not the full CLI.

**How to avoid (corrected recipe):**

The "real mole binary" we bundle at `Contents/Helpers/mole` is the entire Mole tree:

```
MoleBar.app/Contents/Helpers/
├── mole                            # Shell script, copied verbatim from tw93/mole@V1.36.2
├── mo                              # Shell script alias, copied verbatim
├── lib/                            # Shell modules (clean, optimize, purge, etc.) — copied verbatim
├── cmd/                            # Shell command implementations — copied verbatim
├── scripts/                        # Utility scripts — copied verbatim
└── bin/
    ├── analyze-go                  # lipo -create of analyze-darwin-arm64 + analyze-darwin-amd64
    └── status-go                   # lipo -create of status-darwin-arm64 + status-darwin-amd64
```

The CI recipe:

```bash
MOLE_VERSION=$(cat mole-version.txt)   # e.g., "V1.36.2"
TMP=$(mktemp -d)

# Download per-arch Go helpers from upstream release
for binary in analyze status; do
  for arch in arm64 amd64; do
    curl -fsSL -o "${TMP}/${binary}-darwin-${arch}" \
      "https://github.com/tw93/mole/releases/download/${MOLE_VERSION}/${binary}-darwin-${arch}"
  done
done

# Clone the Mole tree at the pinned tag (for Shell scripts)
git clone --depth 1 --branch "${MOLE_VERSION}" https://github.com/tw93/mole.git "${TMP}/mole-src"

# Stage the bundle Helpers/ directory
HELPERS="MoleBar.app/Contents/Helpers"
mkdir -p "${HELPERS}/bin"
cp "${TMP}/mole-src/mole" "${HELPERS}/mole"
cp "${TMP}/mole-src/mo"   "${HELPERS}/mo"
cp -R "${TMP}/mole-src/lib"     "${HELPERS}/lib"
cp -R "${TMP}/mole-src/cmd"     "${HELPERS}/cmd"
cp -R "${TMP}/mole-src/scripts" "${HELPERS}/scripts"

# Universal2 the Go helpers via lipo
lipo -create \
  "${TMP}/analyze-darwin-arm64" "${TMP}/analyze-darwin-amd64" \
  -output "${HELPERS}/bin/analyze-go"
lipo -create \
  "${TMP}/status-darwin-arm64" "${TMP}/status-darwin-amd64" \
  -output "${HELPERS}/bin/status-go"
chmod 755 "${HELPERS}/mole" "${HELPERS}/mo" \
          "${HELPERS}/bin/analyze-go" "${HELPERS}/bin/status-go"

# Verify Universal2 worked
file "${HELPERS}/bin/analyze-go" | grep -q "Mach-O universal binary"
lipo -archs "${HELPERS}/bin/analyze-go" | grep -q "x86_64 arm64"
```

**Smoke test for D-14's intent (Phase 1 acceptance):** invoke the bundled mole's version subcommand from inside the dummy app:

```swift
// In MoleBarApp init() — debug-only; remove in Phase 2
if let bundleURL = Bundle.main.url(forResource: "mole", withExtension: nil, subdirectory: "Helpers") {
    let process = Process()
    process.executableURL = bundleURL
    process.arguments = ["--version"]
    let pipe = Pipe()
    process.standardOutput = pipe
    try? process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    NSLog("Bundled mole reports: %@", String(data: data, encoding: .utf8) ?? "<nil>")
}
```

This is a single-shot launch-and-version probe per CONTEXT.md's smoke test scope — full subprocess orchestration is Phase 2.

**Warning signs for the planner:**
- A plan that references "the mole binary" as a single Mach-O — likely conflated.
- A plan that tries to lipo the Shell script — will produce nonsense errors.

**Phase to address:** Phase 1 only. Phase 2's `MoleResolver.resolveBinary()` will read `Contents/Helpers/mole` (the Shell wrapper); the Go helpers are an implementation detail Phase 2 won't touch.

**Sources:**
- [tw93/mole/install.sh](https://raw.githubusercontent.com/tw93/mole/main/install.sh) — confirms per-arch Go helpers, Shell wrapper. **[VERIFIED]**
- [tw93/mole/Makefile](https://raw.githubusercontent.com/tw93/mole/main/Makefile) — confirms `release-amd64` / `release-arm64` targets produce `analyze-darwin-*` and `status-darwin-*`. **[VERIFIED]**

### Pitfall A2: `SUPublicEDKey` is unrotatable post-launch (P0)

**What goes wrong:** Phase 1 ships v0.0.1 with a given `SUPublicEDKey`. Six months later you realize the private key was leaked or you switched Macs and lost it. You generate a new keypair and ship v0.5.0 with the new public key. **Every user on v0.0.1 through v0.4.x rejects the v0.5.0 update** because their on-disk `Info.plist` contains the OLD pubkey, which doesn't match the v0.5.0 EdDSA signature. They are now permanently stranded.

**Why it happens:** Sparkle's update verification reads `SUPublicEDKey` from the *currently-installed* app, not from the new one. There is no key-rotation flow.

**How to avoid:**
- Treat the `SUPublicEDKey` lock-in as the single most important cryptographic decision in Phase 1.
- Generate the keypair via `generate_keys` ONCE on the developer's primary Mac.
- Verify the public key with `generate_keys -p` (prints the public key) before pasting it into `Info.plist`.
- Back up via iCloud Keychain sync (D-06) AND keep an offline copy of the private key on a hardware-encrypted USB drive.
- DO NOT publish a v0.0.1 release until you've also verified you can re-export the private key from Keychain (`generate_keys -x /tmp/test.key`); if export fails, the key is unrecoverable.

**Recovery if it happens:** Project-restart event. Publish a final update on the OLD key with code that displays "Critical: download new version manually" and disables auto-update. Publish new bundle (potentially new bundle ID) with new key. Existing users must reinstall.

**Source:** PITFALLS.md Pitfall #3; [Sparkle Discussion #2174](https://github.com/sparkle-project/Sparkle/discussions/2174). **[CITED]**

### Pitfall A3: Re-zipping artifacts after `sign_update` invalidates the signature (P0)

**What goes wrong:** CI workflow does `sign_update MoleBar-0.0.1.dmg` and captures the signature. Then a later step `cp MoleBar-0.0.1.dmg artifacts/release.dmg` (or worse, repackages the DMG to fix a typo). The signature in the appcast no longer matches the file bytes, and Sparkle rejects the update on every user's machine.

**How to avoid:**
- The release pipeline must follow this strict order:
  1. Build `.app`
  2. Build `.dmg` via create-dmg
  3. (Phase 1.5: sign + notarize + staple — modifies the .dmg by attaching the ticket)
  4. **`sign_update` runs LAST** on the final, untouched `.dmg`
  5. The `.dmg` is uploaded to GitHub Release UNMODIFIED after this point
  6. The signature output of `sign_update` is embedded directly into appcast.xml
- Add a CI verification step: re-run `sign_update` on the uploaded artifact and confirm the signature matches what we wrote into appcast.xml. (Catches accidental in-flight mutation.)
- Never `cp`, `mv`, or `tar` a signed artifact between sign_update and upload.

**Source:** PITFALLS.md Pitfall #3. **[CITED]**

### Pitfall A4: macos-15 runner default Xcode is 16.4, NOT 16.3 — sufficient (P2 informational)

**What goes wrong:** STACK.md mentions "Xcode 16.3+" as the requirement. CONTEXT.md mentions "Xcode 16+." A planner unfamiliar with macos-15 might add a `xcodes select 16.3` step that fails because Xcode 16.3 is installed-but-not-default.

**How to avoid:** Don't bother selecting Xcode in Phase 1. The macos-15 runner default (Xcode 16.4) supports SwiftUI MenuBarExtra `.window` style on macOS 14 deployment target — verified. If we ever need to pin a specific version, use `sudo xcode-select -s /Applications/Xcode_16.4.app` (the version is already installed; `xcodes` action is unnecessary).

**Source:** [GH Actions runner-images macos-15 readme](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md). **[VERIFIED]**

### Pitfall A5: GitHub Pages first-time setup is manual + must be done in repo settings UI (P1)

**What goes wrong:** CI workflow tries to push to `gh-pages` branch via peaceiris-action. The branch is created, but `https://puffpuff.dev/molebar/appcast.xml` returns 404 because GitHub Pages was never enabled in the repo settings. SUFeedURL fetches fail. Sparkle update prompt never appears.

**How to avoid:**
- Manual one-time setup BEFORE the first tag push:
  1. Go to `https://github.com/romatroskin/molebar/settings/pages`
  2. Source: `Deploy from a branch`
  3. Branch: `gh-pages` (will appear after the first CI run creates it; for first-time setup, push an empty commit to `gh-pages` manually)
  4. Folder: `/ (root)`
  5. Save
- Document this in the README's "Setup checklist for new maintainers" section and in a `.planning/phases/01-distribution-foundations/CHECKLIST.md` if the planner emits one.
- Verify after first deploy: `curl -fsSL https://puffpuff.dev/molebar/appcast.xml` should return the XML; HTTP 404 means Pages is not enabled.

**Source:** [peaceiris/actions-gh-pages docs](https://github.com/peaceiris/actions-gh-pages) — confirms manual repo-setting requirement. **[VERIFIED]**

### Pitfall A6: `peaceiris/actions-gh-pages` `keep_files: true` is critical to avoid wiping the appcast on re-run (P1)

**What goes wrong:** When a release is re-run (e.g., re-pushing the same tag after a CI flake), the action by default DELETES all files in the gh-pages branch except those in `publish_dir`. Without `keep_files: true`, every release wipes any unrelated docs you might add later.

**How to avoid:**
- Always pass `keep_files: true` to peaceiris when publishing a single file.
- Make sure `publish_dir` is a directory containing ONLY appcast.xml (e.g., create a temp dir, copy only appcast.xml into it, point peaceiris at the temp dir).

**Pattern:**
```bash
mkdir -p _gh_pages_payload
cp appcast.xml _gh_pages_payload/appcast.xml
# Action then publishes _gh_pages_payload/* into gh-pages root with keep_files: true
```

**Source:** [peaceiris docs](https://github.com/peaceiris/actions-gh-pages). **[CITED]**

### Pitfall A7: `lipo` fails silently if binaries aren't fat-compatible (P2)

**What goes wrong:** If `tw93/mole` ships a malformed or already-Universal binary by mistake, `lipo -create` returns non-zero but bash continues unless `set -e` is on.

**How to avoid:**
- Every CI step is wrapped in `set -euo pipefail` at the top.
- After `lipo`, run `file <output>` and grep for "Mach-O universal binary"; fail the build if not found.
- After `lipo`, run `lipo -archs <output>` and confirm both `x86_64` and `arm64` appear.

### Pitfall A8: `MARKETING_VERSION` injection requires Info.plist placeholder (P1)

**What goes wrong:** Planner sets up `xcodebuild MARKETING_VERSION=0.0.1` but Info.plist has hard-coded `<string>1.0</string>` for `CFBundleShortVersionString`. The build setting has no effect; `Info.plist` ships with `1.0`.

**How to avoid:** `Info.plist` MUST use the placeholder syntax:
```xml
<key>CFBundleShortVersionString</key>
<string>$(MARKETING_VERSION)</string>
<key>CFBundleVersion</key>
<string>$(CURRENT_PROJECT_VERSION)</string>
```

Xcode's "Versioning" build settings tab shows these as "Marketing Version" and "Current Project Version"; verify they reflect "$(MARKETING_VERSION)" / "$(CURRENT_PROJECT_VERSION)" before relying on command-line override.

**Verify locally:** Run `xcodebuild -showBuildSettings | grep -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION"` and confirm the values are dynamic, not hard-coded.

**Source:** [Apple Developer Forum thread on MARKETING_VERSION + Info.plist](https://developer.apple.com/forums/thread/709065). **[CITED]**

## Code Examples

### create-dmg Invocation

The standard drag-to-Applications layout with background image, verified against [create-dmg/create-dmg README](https://github.com/create-dmg/create-dmg) **[CITED]**:

```bash
create-dmg \
  --volname "MoleBar 0.0.1" \
  --background "dmg-assets/background.png" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 128 \
  --icon "MoleBar.app" 165 200 \
  --hide-extension "MoleBar.app" \
  --app-drop-link 495 200 \
  --no-internet-enable \
  "MoleBar-${MARKETING_VERSION}.dmg" \
  "build/export/"
```

Where `build/export/` contains ONLY `MoleBar.app` (the .app produced by `xcodebuild -exportArchive`).

**Fallback (no background image — D-16 fallback):** if `dmg-assets/background.png` doesn't exist, omit `--background` and the `--icon-size 128 --icon "MoleBar.app" 165 200 ... --app-drop-link 495 200` flags can stay; the DMG will use the system default background with the two icons positioned where specified.

### EdDSA Key Tooling

**One-time bootstrap on developer Mac (D-05, D-07):**

```bash
# In the MoleBar repo, after Sparkle SPM dependency resolves:
SPARKLE_BIN="$HOME/Library/Developer/Xcode/DerivedData/MoleBar-<hash>/SourcePackages/artifacts/sparkle/Sparkle/bin"

# Generate keypair (first time only — writes to login Keychain)
"$SPARKLE_BIN/generate_keys"
# Output includes: "Public key: <base64>"
# Note: this is what goes into Info.plist as SUPublicEDKey

# Verify Keychain entry exists
"$SPARKLE_BIN/generate_keys" -p   # prints public key

# Export private key for CI (umask 077 ensures other users can't read it)
( umask 077 && "$SPARKLE_BIN/generate_keys" -x /tmp/sparkle.key )

# Display contents to copy/paste into GitHub Secret SPARKLE_EDDSA_PRIVATE_KEY
cat /tmp/sparkle.key
# COPY THE ENTIRE OUTPUT, including the format header

# Securely wipe the temp file
shred -uvz /tmp/sparkle.key 2>/dev/null || rm -P /tmp/sparkle.key
```

The `generate_keys` tool path verified via [Sparkle Issue #1701](https://github.com/sparkle-project/Sparkle/issues/1701) **[CITED]** and [VibeTunnel docs](https://docs.vibetunnel.sh/mac/docs/sparkle-keys) **[CITED]**.

**CI usage (in `.github/workflows/release.yml`):**

```yaml
- name: Sign DMG with Sparkle EdDSA key
  env:
    SPARKLE_EDDSA_PRIVATE_KEY: ${{ secrets.SPARKLE_EDDSA_PRIVATE_KEY }}
  run: |
    set -euo pipefail
    
    # Locate Sparkle's sign_update from SPM artifact bundle
    SPARKLE_BIN=$(find ~/Library/Developer/Xcode/DerivedData -path '*/sparkle/Sparkle/bin' -type d | head -n 1)
    if [ -z "$SPARKLE_BIN" ]; then
      echo "ERROR: Sparkle bin/ not found in DerivedData"
      exit 1
    fi
    
    # Restore key file with restricted permissions
    KEY_FILE=$(mktemp)
    ( umask 077 && printf '%s' "$SPARKLE_EDDSA_PRIVATE_KEY" > "$KEY_FILE" )
    
    # Mask the private key in any subsequent log output (defense in depth)
    echo "::add-mask::$SPARKLE_EDDSA_PRIVATE_KEY"
    
    # Sign the DMG. Output is "<base64-sig> <length>" on one line.
    SIGN_OUTPUT=$("$SPARKLE_BIN/sign_update" --ed-key-file "$KEY_FILE" "MoleBar-${MARKETING_VERSION}.dmg")
    
    # Securely remove the key file
    shred -uvz "$KEY_FILE" 2>/dev/null || rm -P "$KEY_FILE"
    
    # Capture for next step
    EDDSA_SIG=$(echo "$SIGN_OUTPUT" | awk '{print $2}' | tr -d '"')   # signature
    EDDSA_LEN=$(echo "$SIGN_OUTPUT" | awk '{print $4}' | tr -d '"')   # length attribute
    
    echo "EDDSA_SIG=$EDDSA_SIG" >> "$GITHUB_ENV"
    echo "EDDSA_LEN=$EDDSA_LEN" >> "$GITHUB_ENV"
```

**Note on `sign_update` output format [ASSUMED — verify with Sparkle docs / `sign_update -h` during planning]:**

`sign_update` produces an XML fragment like:

```
sparkle:edSignature="<base64>" length="<bytes>"
```

The exact attribute parsing in the awk above is approximate; the planner should run `sign_update -h` on the macos-15 runner once to confirm the output format, OR use simpler whole-line capture:

```bash
SIGN_FRAGMENT=$("$SPARKLE_BIN/sign_update" --ed-key-file "$KEY_FILE" "MoleBar-${MARKETING_VERSION}.dmg")
echo "SIGN_FRAGMENT=$SIGN_FRAGMENT" >> "$GITHUB_ENV"
# Then embed $SIGN_FRAGMENT directly into appcast.xml inside <enclosure>
```

The whole-line capture approach is more robust against format changes between Sparkle versions.

### Appcast XML Structure

Verified shape per Sparkle 2.x docs **[CITED]**:

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>MoleBar</title>
    <link>https://puffpuff.dev/molebar/appcast.xml</link>
    <description>MoleBar update feed</description>
    <language>en</language>
    <item>
      <title>Version 0.0.1</title>
      <pubDate>Mon, 27 Apr 2026 12:00:00 +0000</pubDate>
      <sparkle:version>1</sparkle:version>
      <sparkle:shortVersionString>0.0.1</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description>
        <![CDATA[
        <h2>0.0.1 — Hello, world.</h2>
        <p>First test release. Nothing to see here yet.</p>
        ]]>
      </description>
      <enclosure
        url="https://github.com/romatroskin/molebar/releases/download/v0.0.1/MoleBar-0.0.1.dmg"
        sparkle:edSignature="<EDDSA-SIG-FROM-SIGN-UPDATE>"
        length="<BYTE-COUNT-FROM-SIGN-UPDATE>"
        type="application/x-apple-diskimage" />
    </item>
  </channel>
</rss>
```

**`sparkle:version` is the `CFBundleVersion` (build number / monotonic);** `sparkle:shortVersionString` is the marketing version. They MUST match the values in the corresponding release's `Info.plist`.

For Phase 1's 0.0.1 → 0.0.2 round-trip, the appcast.xml file maintained on `gh-pages` has TWO `<item>` entries (or just one — the latest, replacing the old one). Sparkle picks the entry with the highest `sparkle:version` that's newer than the running app's version.

**Single-item-per-release pattern (recommended for Phase 1):** each release's CI workflow OVERWRITES `appcast.xml` with the latest release's metadata. Old entries are not preserved. This is acceptable because Sparkle only cares about "is there a newer version?" and we're not yet supporting downgrades or beta channels.

### GitHub Actions Workflow Skeleton

Complete-with-stubs `.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags:
      - 'v*.*.*'

permissions:
  contents: write       # softprops/action-gh-release needs this
  pages: write          # GH Pages publish (when using built-in pages action)
  id-token: write       # OIDC for trusted publishing (future)

concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false   # Never cancel a release mid-flight

jobs:
  release:
    runs-on: macos-15
    timeout-minutes: 30
    
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
      
      - name: Compute versions
        id: versions
        run: |
          set -euo pipefail
          TAG="${GITHUB_REF#refs/tags/}"
          MARKETING_VERSION="${TAG#v}"
          CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER}"
          echo "marketing=$MARKETING_VERSION" >> "$GITHUB_OUTPUT"
          echo "build=$CURRENT_PROJECT_VERSION" >> "$GITHUB_OUTPUT"
          echo "tag=$TAG" >> "$GITHUB_OUTPUT"
      
      - name: Select Xcode 16.4
        run: sudo xcode-select -s /Applications/Xcode_16.4.app
      
      - name: Install create-dmg
        run: brew install create-dmg
      
      - name: Resolve Sparkle SPM artifacts
        # Force SPM resolution so generate_keys/sign_update tools are present
        run: |
          set -euo pipefail
          xcodebuild -resolvePackageDependencies -project MoleBar.xcodeproj
      
      - name: Bundle tw93/mole at pinned version
        run: |
          set -euo pipefail
          MOLE_VERSION=$(cat mole-version.txt)
          TMP=$(mktemp -d)
          
          # Download per-arch Go helpers
          for binary in analyze status; do
            for arch in arm64 amd64; do
              curl -fsSL --retry 3 -o "${TMP}/${binary}-darwin-${arch}" \
                "https://github.com/tw93/mole/releases/download/${MOLE_VERSION}/${binary}-darwin-${arch}"
            done
          done
          
          # Clone Mole tree at pinned tag
          git clone --depth 1 --branch "${MOLE_VERSION}" \
            https://github.com/tw93/mole.git "${TMP}/mole-src"
          
          # Stage in a known location for the Xcode build phase to consume
          mkdir -p mole-bundle/bin
          cp "${TMP}/mole-src/mole" mole-bundle/mole
          cp "${TMP}/mole-src/mo"   mole-bundle/mo
          cp -R "${TMP}/mole-src/lib"     mole-bundle/lib
          cp -R "${TMP}/mole-src/cmd"     mole-bundle/cmd
          cp -R "${TMP}/mole-src/scripts" mole-bundle/scripts
          
          # Universal2 the Go helpers
          lipo -create \
            "${TMP}/analyze-darwin-arm64" "${TMP}/analyze-darwin-amd64" \
            -output mole-bundle/bin/analyze-go
          lipo -create \
            "${TMP}/status-darwin-arm64" "${TMP}/status-darwin-amd64" \
            -output mole-bundle/bin/status-go
          chmod 755 mole-bundle/mole mole-bundle/mo \
                    mole-bundle/bin/analyze-go mole-bundle/bin/status-go
          
          # Verify Universal2
          file mole-bundle/bin/analyze-go | grep -q "Mach-O universal binary"
          lipo -archs mole-bundle/bin/analyze-go | grep -q "x86_64"
          lipo -archs mole-bundle/bin/analyze-go | grep -q "arm64"
      
      - name: Build & archive
        run: |
          set -euo pipefail
          xcodebuild archive \
            -project MoleBar.xcodeproj \
            -scheme MoleBar \
            -configuration Release \
            -archivePath build/MoleBar.xcarchive \
            -destination "generic/platform=macOS" \
            MARKETING_VERSION="${{ steps.versions.outputs.marketing }}" \
            CURRENT_PROJECT_VERSION="${{ steps.versions.outputs.build }}" \
            CODE_SIGN_IDENTITY="-" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO \
            | tee build/archive.log
      
      - name: Export .app
        run: |
          set -euo pipefail
          mkdir -p build/export
          # Copy .app out of archive (no signing in Phase 1)
          cp -R build/MoleBar.xcarchive/Products/Applications/MoleBar.app build/export/MoleBar.app
          
          # Inject the bundled mole tree into Contents/Helpers
          mkdir -p build/export/MoleBar.app/Contents/Helpers
          cp -R mole-bundle/. build/export/MoleBar.app/Contents/Helpers/
      
      # ---------- STUBBED — activates in Phase 1.5 ----------
      
      - name: Import Developer ID certificate (STUB)
        if: ${{ secrets.MACOS_CERT != '' }}
        env:
          MACOS_CERT: ${{ secrets.MACOS_CERT }}
          MACOS_CERT_PWD: ${{ secrets.MACOS_CERT_PWD }}
          MACOS_CI_KEYCHAIN_PWD: ${{ secrets.MACOS_CI_KEYCHAIN_PWD }}
        run: |
          set -euo pipefail
          echo "$MACOS_CERT" | base64 --decode > certificate.p12
          security create-keychain -p "$MACOS_CI_KEYCHAIN_PWD" build.keychain
          security default-keychain -s build.keychain
          security unlock-keychain -p "$MACOS_CI_KEYCHAIN_PWD" build.keychain
          security import certificate.p12 -k build.keychain -P "$MACOS_CERT_PWD" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$MACOS_CI_KEYCHAIN_PWD" build.keychain
          rm certificate.p12
      
      - name: Sign embedded mole helpers + .app (inside-out) (STUB)
        if: ${{ secrets.MACOS_CERT_NAME != '' }}
        env:
          MACOS_CERT_NAME: ${{ secrets.MACOS_CERT_NAME }}
        run: |
          set -euo pipefail
          APP="build/export/MoleBar.app"
          # Sign the Go helpers first (innermost)
          for bin in "$APP/Contents/Helpers/bin/analyze-go" "$APP/Contents/Helpers/bin/status-go"; do
            codesign --force --options runtime --timestamp --sign "$MACOS_CERT_NAME" "$bin"
          done
          # Note: Shell scripts (mole, mo, lib/*.sh) are NOT signable — they're text files.
          # Phase 1.5 needs to consider this; codesign only applies to Mach-O binaries.
          # The .app's signature covers the contents via signed-resources rules.
          codesign --force --options runtime --timestamp \
            --entitlements MoleBar/MoleBar.entitlements \
            --sign "$MACOS_CERT_NAME" "$APP"
      
      # ---------- always runs ----------
      
      - name: Build DMG
        run: |
          set -euo pipefail
          mkdir -p build/dmg
          if [ -f "dmg-assets/background.png" ]; then
            create-dmg \
              --volname "MoleBar ${{ steps.versions.outputs.marketing }}" \
              --background "dmg-assets/background.png" \
              --window-pos 200 120 \
              --window-size 660 400 \
              --icon-size 128 \
              --icon "MoleBar.app" 165 200 \
              --hide-extension "MoleBar.app" \
              --app-drop-link 495 200 \
              --no-internet-enable \
              "build/dmg/MoleBar-${{ steps.versions.outputs.marketing }}.dmg" \
              "build/export/"
          else
            # Fallback per D-16: no background image, simpler layout
            create-dmg \
              --volname "MoleBar ${{ steps.versions.outputs.marketing }}" \
              --window-pos 200 120 \
              --window-size 600 400 \
              --icon-size 128 \
              --icon "MoleBar.app" 175 200 \
              --hide-extension "MoleBar.app" \
              --app-drop-link 425 200 \
              --no-internet-enable \
              "build/dmg/MoleBar-${{ steps.versions.outputs.marketing }}.dmg" \
              "build/export/"
          fi
      
      # ---------- STUBBED — activates in Phase 1.5 ----------
      
      - name: Notarize DMG (STUB)
        if: ${{ secrets.ASC_API_KEY_P8 != '' }}
        env:
          ASC_API_KEY_ID: ${{ secrets.ASC_API_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          ASC_API_KEY_P8: ${{ secrets.ASC_API_KEY_P8 }}
        run: |
          set -euo pipefail
          KEY_FILE=$(mktemp)
          ( umask 077 && printf '%s' "$ASC_API_KEY_P8" > "$KEY_FILE" )
          
          xcrun notarytool submit \
            "build/dmg/MoleBar-${{ steps.versions.outputs.marketing }}.dmg" \
            --key "$KEY_FILE" \
            --key-id "$ASC_API_KEY_ID" \
            --issuer "$ASC_ISSUER_ID" \
            --wait
          
          xcrun stapler staple "build/dmg/MoleBar-${{ steps.versions.outputs.marketing }}.dmg"
          
          shred -uvz "$KEY_FILE" 2>/dev/null || rm -P "$KEY_FILE"
      
      # ---------- always runs (real Sparkle signing) ----------
      
      - name: Sign DMG with Sparkle EdDSA
        env:
          SPARKLE_EDDSA_PRIVATE_KEY: ${{ secrets.SPARKLE_EDDSA_PRIVATE_KEY }}
        run: |
          set -euo pipefail
          
          if [ -z "$SPARKLE_EDDSA_PRIVATE_KEY" ]; then
            echo "ERROR: SPARKLE_EDDSA_PRIVATE_KEY secret is empty — release blocked."
            exit 1
          fi
          
          echo "::add-mask::$SPARKLE_EDDSA_PRIVATE_KEY"
          
          SPARKLE_BIN=$(find ~/Library/Developer/Xcode/DerivedData -path '*/sparkle/Sparkle/bin' -type d | head -n 1)
          if [ -z "$SPARKLE_BIN" ]; then
            echo "ERROR: Sparkle bin/ not found in DerivedData"
            exit 1
          fi
          
          KEY_FILE=$(mktemp)
          ( umask 077 && printf '%s' "$SPARKLE_EDDSA_PRIVATE_KEY" > "$KEY_FILE" )
          
          DMG="build/dmg/MoleBar-${{ steps.versions.outputs.marketing }}.dmg"
          SIGN_FRAGMENT=$("$SPARKLE_BIN/sign_update" --ed-key-file "$KEY_FILE" "$DMG")
          
          shred -uvz "$KEY_FILE" 2>/dev/null || rm -P "$KEY_FILE"
          
          echo "SIGN_FRAGMENT=$SIGN_FRAGMENT" >> "$GITHUB_ENV"
          echo "DMG_LENGTH=$(stat -f%z "$DMG")" >> "$GITHUB_ENV"
      
      - name: Render appcast.xml
        run: |
          set -euo pipefail
          mkdir -p _gh_pages_payload
          cat > _gh_pages_payload/appcast.xml <<EOF
          <?xml version="1.0" encoding="utf-8"?>
          <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
            <channel>
              <title>MoleBar</title>
              <link>https://puffpuff.dev/molebar/appcast.xml</link>
              <description>MoleBar update feed</description>
              <language>en</language>
              <item>
                <title>Version ${{ steps.versions.outputs.marketing }}</title>
                <pubDate>$(date -u +'%a, %d %b %Y %H:%M:%S +0000')</pubDate>
                <sparkle:version>${{ steps.versions.outputs.build }}</sparkle:version>
                <sparkle:shortVersionString>${{ steps.versions.outputs.marketing }}</sparkle:shortVersionString>
                <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
                <description><![CDATA[
                <p>See the <a href="https://github.com/romatroskin/molebar/releases/tag/${{ steps.versions.outputs.tag }}">GitHub release notes</a>.</p>
                ]]></description>
                <enclosure
                  url="https://github.com/romatroskin/molebar/releases/download/${{ steps.versions.outputs.tag }}/MoleBar-${{ steps.versions.outputs.marketing }}.dmg"
                  ${SIGN_FRAGMENT}
                  type="application/x-apple-diskimage" />
              </item>
            </channel>
          </rss>
          EOF
      
      - name: Create GitHub Release & upload DMG
        uses: softprops/action-gh-release@v3
        with:
          tag_name: ${{ steps.versions.outputs.tag }}
          name: "MoleBar ${{ steps.versions.outputs.marketing }}"
          generate_release_notes: true
          files: build/dmg/MoleBar-${{ steps.versions.outputs.marketing }}.dmg
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      
      - name: Publish appcast.xml to gh-pages
        uses: peaceiris/actions-gh-pages@v4
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: _gh_pages_payload
          publish_branch: gh-pages
          keep_files: true
          commit_message: "Publish appcast for ${{ steps.versions.outputs.tag }}"
      
      # ---------- STUBBED — Phase 1.5 ----------
      
      - name: Bump Homebrew Cask (STUB)
        if: ${{ secrets.HOMEBREW_GITHUB_TOKEN != '' }}
        run: |
          echo "Phase 1.5: bump romatroskin/homebrew-tap cask formula"
          # Implementation: LanikSJ/homebrew-bump-cask or equivalent
```

### Mole Binary Bundling Recipe

See Pitfall A1 above for the corrected recipe and full bash sequence. Summary:

1. Download `analyze-darwin-{arm64,amd64}` and `status-darwin-{arm64,amd64}` from `https://github.com/tw93/mole/releases/download/V1.36.2/`
2. `git clone --depth 1 --branch V1.36.2` to get `mole`, `mo`, `lib/`, `cmd/`, `scripts/`
3. `lipo -create` arm64+amd64 pairs → `analyze-go`, `status-go`
4. Stage everything under `MoleBar.app/Contents/Helpers/`
5. `chmod 755` the Shell scripts and Go helpers
6. Verify with `file` + `lipo -archs`

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `altool` for notarization | `xcrun notarytool` | Apple deprecated `altool` for notarization in 2022 | Required — `altool` notarization endpoint is removed. (Phase 1.5 concern.) |
| Sparkle 1.x DSA signing | Sparkle 2.x EdDSA signing | DSA migrated away from in Sparkle 2.0 (2021); EdDSA is the only modern path | Locked in Phase 1; D-08 is unrotatable. |
| `codesign --deep` | Inside-out signing (sign embedded helpers first, then `.app`) | Apple deprecated `--deep` in macOS 13 | (Phase 1.5 concern; the workflow file's stubbed signing job already uses inside-out.) |
| Apple ID + app-specific password for notarization | App Store Connect API Key (Issuer ID + Key ID + .p8) | API key path matured around 2023 | Per D-10 — already adopted. |
| `ObservableObject` + `@Published` for SwiftUI state | `@Observable` macro | macOS 14 deployment target unlocks Observation framework | Not Phase 1's concern (the dummy stub doesn't have state); Phase 2+ uses `@Observable`. |
| `.menu` style MenuBarExtra | `.window` style | `.menu` blocks runloop while open (FB13683957/FB13683950) | `.window` is mandatory per D-13 and ARCHITECTURE.md Conflict 3. |

**Deprecated/outdated:**

- **`SURequireSignedFeed`** as a separately-required key — in Sparkle 2.x with `SUPublicEDKey` set, EdDSA enclosure verification happens automatically; `SURequireSignedFeed` adds a separate feed-level signing layer that's optional. **Decision:** omit from Phase 1 Info.plist; revisit if discuss-phase wants the extra layer. **[ASSUMED]**
- **Hand-rolled `release.sh`** — STACK.md mentions this as an alternative to Fastlane; the actual artifact for Phase 1 is `release.yml` (CI-native). A local `release.sh` is unnecessary because tag-push triggers everything.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `SURequireSignedFeed` is optional in Sparkle 2.x with EdDSA enclosure signing (omit from Info.plist) | Pattern 2 | LOW — if needed, just add the key in Phase 1.5; doesn't affect public API. |
| A2 | The `sign_update` output format `sparkle:edSignature="..." length="..."` is parseable as an XML fragment that can be inlined directly into `<enclosure ... ${SIGN_FRAGMENT} ...>` | Code Examples → Appcast XML | LOW-MEDIUM — confirm by running `sign_update -h` and `sign_update <test.dmg> --ed-key-file <key>` once during Phase 1 implementation. If output differs, parse via awk as shown in EdDSA Key Tooling. |
| A3 | `Contents/Helpers/` is an acceptable path for the Mole tree, vs. STACK.md's mention of `Contents/Resources/` | (CONTEXT.md D-17 locks `Contents/Helpers/`) | NONE — D-17 is locked; the planner uses Helpers/. |
| A4 | The macos-15 runner's default Xcode 16.4 supports SwiftUI MenuBarExtra `.window` style on macOS 14 deployment target | Pitfall A4 | LOW — Apple docs confirm `.window` is macOS 13+. |
| A5 | Sparkle SPM artifacts land at `~/Library/Developer/Xcode/DerivedData/<project>/SourcePackages/artifacts/sparkle/Sparkle/bin/` | EdDSA Key Tooling | LOW — verified via Sparkle issue #1701 and community docs; path is stable across recent SPM versions. CI workflow uses `find` with the stable suffix `*/sparkle/Sparkle/bin` so DerivedData hash variance doesn't matter. |
| A6 | `peaceiris/actions-gh-pages@v4.0.0` is still the recommended path even though the action's last release was Apr 2024; no breaking changes since | Standard Stack | LOW — v4 is stable; last published is fine for our limited use case (single-file commit). |
| A7 | `softprops/action-gh-release@v3.0.0` is non-breaking from v2 for our usage | Standard Stack | LOW — flag set is the same (tag_name, name, files, generate_release_notes). |
| A8 | `tw93/mole`'s install.sh URL pattern (`/releases/download/V${version}/${binary}-darwin-${arch}`) is stable | Mole Binary Bundling Recipe | MEDIUM — upstream could in theory rename artifacts; planner should verify by running a one-off `curl -fsSI` against the pinned tag during Phase 1 implementation, before committing the workflow. |
| A9 | The `mole` Shell wrapper at the repo root invokes `bin/analyze-go` / `bin/status-go` relative to its own location (so the bundled tree at `Contents/Helpers/` works) — NOT relative to `~/.config/mole` like the user-installed flow does | Pitfall A1 + Mole Binary Bundling Recipe | MEDIUM — verify by reading the `mole` script (look for `SCRIPT_DIR` resolution); the install.sh uses `sed` to patch this at install time, so the bundled copy may need similar patching. **PLANNER MUST VERIFY** during Phase 1 implementation by inspecting the `mole` script post-clone and either (a) confirming relative path lookup works out-of-box, or (b) `sed`-patching `SCRIPT_DIR` in CI to point at `$BUNDLE_DIR/Contents/Helpers`. |
| A10 | `LICENSE-MOLE.txt` (the upstream Mole MIT license) is a Phase 2 deliverable per CORE-08 — Phase 1 doesn't strictly need it, but landing it now (since we're cloning the repo for Shell scripts) is convenient | Project Structure → repo layout | NONE — pulling in `LICENSE` from the cloned tree alongside the shell scripts is a 1-line CI step. |

## Open Questions

1. **Should the workflow run `xcodebuild test` before producing the release artifact?**
   - **What we know:** Phase 1 has effectively no testable code (the dummy stub has no behavior). MoleBarTests target exists but is empty.
   - **What's unclear:** Should we wire `xcodebuild test` even though it always passes vacuously, so Phase 2 just enables it?
   - **Recommendation:** Add an empty `xcodebuild test` step now (against an empty test target). It's free, exercises the test plumbing, and Phase 2 only has to add tests, not workflow steps.

2. **Should appcast.xml accumulate history (one item per release) or always reflect only the latest?**
   - **What we know:** Sparkle picks the highest `sparkle:version` newer than the running app's version.
   - **What's unclear:** Single-item appcast loses release history but is simpler. Multi-item lets users see the upgrade path.
   - **Recommendation:** Phase 1 ships single-item appcast. Phase 8 (v1.0 launch) considers switching to multi-item if release-notes UX matters at that point.

3. **Should Phase 1's workflow include `xcodebuild -exportArchive` or just copy the .app from `xcarchive`?**
   - **What we know:** Without signing, `xcodebuild -exportArchive` requires an `exportOptions.plist` that specifies `signingStyle=manual` and certificate identity. Phase 1 has neither.
   - **What's unclear:** The simpler path is `cp -R MoleBar.xcarchive/Products/Applications/MoleBar.app ./`. Is there value in going through `-exportArchive` with `signingStyle=manual` + no identity?
   - **Recommendation:** For Phase 1, use `cp -R` (simpler, fewer moving parts). Phase 1.5's signing PR adds the proper `-exportArchive` flow.

4. **Should `mole-version.txt` use the `V`-prefixed tag or the bare semver?**
   - **What we know:** Upstream tags are `V1.36.2`; download URLs need the `V` prefix; install.sh uses fallback logic.
   - **Recommendation:** Store `V1.36.2` verbatim (with `V` prefix). The CI step `MOLE_VERSION=$(cat mole-version.txt)` then directly substitutes into URLs and `git clone --branch`.

5. **Does the `mole` Shell wrapper require its `lib/` and `cmd/` to be at fixed relative paths?**
   - See Assumption A9 — needs verification during planning.

## Environment Availability

| Dependency | Required By | Available (CI) | Available (Dev Mac) | Version | Fallback |
|------------|------------|----------------|---------------------|---------|----------|
| Xcode 16+ | Build | ✓ (16.4 default on macos-15) | Required (developer must install) | 16.4 | Higher (16.0/16.1/16.2/16.3 also pre-installed; can `xcode-select`) |
| `xcodebuild` | Build | ✓ | ✓ | bundled | — |
| `lipo` | mole bundling | ✓ (Xcode CLT) | ✓ | bundled | — |
| `create-dmg` | DMG packaging | ✗ (must `brew install`) | Optional (dev rebuilds locally) | 1.2.3 | None — install required step |
| Homebrew | Installing create-dmg in CI | ✓ | ✓ (most dev Macs) | latest | None |
| `gh` CLI | `softprops/action-gh-release` does not need it directly (uses GH API), but useful for diagnostics | ✓ (2.90+ on macos-15) | Optional | 2.90+ | Action handles GH API directly |
| `git` | Clone tw93/mole at pinned tag | ✓ | ✓ | 2.x+ | — |
| `curl` | Download Mole release artifacts | ✓ | ✓ | bundled | — |
| Sparkle SPM | App auto-update | ✓ (resolved by xcodebuild -resolvePackageDependencies) | ✓ (Xcode resolves) | 2.9.1 | None — Sparkle is the ONLY supported solution |
| `peaceiris/actions-gh-pages@v4` | Appcast publish | ✓ (any GH Actions runner) | N/A | 4.0.0 | Direct `git push` from script — fragile |
| `softprops/action-gh-release@v3` | DMG release | ✓ | N/A | 3.0.0 | `gh release create` manually |
| `actions/checkout@v4` | Workflow checkout | ✓ | N/A | 4 | — |
| Apple Developer ID (signing cert) | Phase 1.5 ONLY | ✗ (stubbed) | — | — | None — empty-secret guards keep workflow green |
| App Store Connect API Key | Phase 1.5 ONLY | ✗ (stubbed) | — | — | None — empty-secret guards |

**Missing dependencies with no fallback:**
- None for Phase 1 happy path. (Phase 1.5 requires real Apple Dev ID + ASC API key, but Phase 1 explicitly defers these.)

**Missing dependencies with fallback:**
- `dmg-assets/background.png` — if absent, `create-dmg` falls back to no-background layout per D-16.

## Validation Architecture

> Phase 1 has minimal automated test surface — the dummy app has no behavior. Validation is dominated by **integration / smoke tests** validated end-to-end against a real CI run + real user-machine install.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (built-in to Xcode 16.4) — empty target in Phase 1, populated in Phase 2 |
| Config file | `MoleBar.xcodeproj/xcshareddata/xcschemes/MoleBar.xcscheme` (test action enabled) |
| Quick run command | `xcodebuild test -project MoleBar.xcodeproj -scheme MoleBar -destination 'platform=macOS,arch=arm64'` (passes vacuously in Phase 1) |
| Full suite command | Same as quick run in Phase 1 |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DIST-04 | `.dmg` produced via create-dmg on tag push | integration (CI) | `act push` (locally) OR observe `release.yml` run on tag push; verify `MoleBar-${ver}.dmg` is uploaded to GitHub Release | ❌ Wave 0 — needs `release.yml` |
| DIST-05 | GH Actions release workflow runs on tag push | integration (CI) | Tag-push `v0.0.1`; observe `release.yml` completes green; all stubbed steps emit `if: secrets.X != ''` skipped logs | ❌ Wave 0 — needs `release.yml` |
| DIST-06 | Sparkle 2.x in-app updater fetches signed appcast with EdDSA verify | integration (manual) | Run app → Check for Updates… → confirm Sparkle prompts; corrupt appcast.xml on gh-pages by 1 byte → confirm Sparkle refuses update | ❌ Wave 0 — needs SwiftUI app + appcast deployed |
| DIST-08 | 0.0.1 → 0.0.2 round-trip succeeds end-to-end | integration (manual) | See §Smoke Test Plan | ❌ Wave 0 — needs both 0.0.1 + 0.0.2 published |
| OSS-01 | Public MIT repo + README | review (manual) | Verify `LICENSE` file exists at repo root with MIT text; verify README has install/build/contributing sections; `gh repo view --json visibility` returns `PUBLIC`; verify GitHub repo settings → enable Pages | ❌ Wave 0 — needs README.md, LICENSE |
| OSS-04 | Signing keys in GH Actions secrets only — no leaks in repo or logs | automated check + review | (1) `git log --all -p \| grep -E "BEGIN.*PRIVATE KEY\|edpr"` returns nothing; (2) `gh api repos/romatroskin/molebar/actions/runs --paginate \| jq` and `gh run view <id> --log` for last 5 runs, search for known secret prefixes; (3) GitHub Push Protection enabled in repo Settings → Code Security | ❌ Wave 0 — verification is post-CI |

### Sampling Rate

- **Per task commit:** `xcodebuild build -project MoleBar.xcodeproj -scheme MoleBar -destination 'platform=macOS,arch=arm64'` (≤30s typically); if test target has anything: `xcodebuild test`.
- **Per wave merge:** Same as above; `xcodebuild test` (vacuous in Phase 1).
- **Phase gate:** Tag-push `v0.0.1` to a test branch repo first if possible, OR push to main repo with a pre-baked decision to delete the release if anything fails. Confirm:
  1. CI run is green.
  2. `MoleBar-0.0.1.dmg` is on the GitHub Release.
  3. `https://puffpuff.dev/molebar/appcast.xml` returns 200 with the expected XML.
  4. After tag-push `v0.0.2` (with a tiny version-string change in the popover), the smoke test in §Smoke Test Plan passes.
  5. `git log --all -p` post-release shows no key material; CI logs are clean.

### Wave 0 Gaps

- [ ] `MoleBar.xcodeproj` — Xcode project file (greenfield)
- [ ] `MoleBar/Info.plist` — bundle ID, SUFeedURL, SUPublicEDKey, LSUIElement, version placeholders
- [ ] `MoleBar/MoleBar.entitlements` — empty file (Phase 1.5 fills it)
- [ ] `MoleBar/MoleBarApp.swift` — @main App with MenuBarExtra(.window) + Sparkle wiring
- [ ] `MoleBar/PopoverRootView.swift` — stub popover content
- [ ] `MoleBar/CheckForUpdatesView.swift` — Sparkle-pattern wrapper
- [ ] `MoleBarTests/` — empty test target
- [ ] `Packages/MoleBarPackage/Package.swift` — local SwiftPM package with 3 empty modules
- [ ] `.github/workflows/release.yml` — complete-with-stubs release workflow
- [ ] `LICENSE` — MIT license text
- [ ] `README.md` — contributor-friendly README
- [ ] `mole-version.txt` — pinned upstream Mole version (`V1.36.2`)
- [ ] `dmg-assets/background.png` — DMG background (or omit per D-16 fallback)
- [ ] `.gitignore` — excludes build outputs, DerivedData, xcuserdata, sparkle key files
- [ ] **Manual GitHub repo settings:**
  - Push Protection enabled (Settings → Code Security)
  - GitHub Pages enabled, source = `gh-pages` branch root
  - Repository secret created: `SPARKLE_EDDSA_PRIVATE_KEY` (from local Keychain via `generate_keys -x`)
  - `MACOS_CERT`, `MACOS_CERT_PWD`, `MACOS_CERT_NAME`, `MACOS_CI_KEYCHAIN_PWD`, `ASC_API_KEY_ID`, `ASC_ISSUER_ID`, `ASC_API_KEY_P8`, `HOMEBREW_GITHUB_TOKEN` — created EMPTY for Phase 1 (filled in Phase 1.5). Note: an empty secret is the same as no secret to GH Actions; `if: ${{ secrets.X != '' }}` evaluates correctly either way.

### Smoke Test Plan (DIST-08 Acceptance — the canonical Phase 1 deliverable)

The plan name is "round-trip 0.0.1 → 0.0.2 update succeeds end-to-end." The exact sequence:

**Setup (one-time):**
1. Tag and push `v0.0.1`. Confirm `release.yml` produces `MoleBar-0.0.1.dmg` on the GH Release and `appcast.xml` deployed to gh-pages.
2. Download `MoleBar-0.0.1.dmg` from `https://github.com/romatroskin/molebar/releases/download/v0.0.1/MoleBar-0.0.1.dmg` to a clean Mac (or fresh user account).
3. Open the DMG, drag `MoleBar.app` into `/Applications/`.
4. Launch `MoleBar` from `/Applications/`. Note: macOS will likely show "MoleBar.app is from an unidentified developer" because Phase 1 is unsigned. The user must right-click → Open → Open Anyway in System Settings → Privacy. **This is expected for Phase 1 and explicitly documented in CONTEXT.md as deferred to Phase 1.5.**
5. Confirm the menu bar icon appears (LSUIElement = YES means no Dock icon).
6. Click the menu bar icon. Confirm popover shows: "MoleBar 0.0.1 — nothing here yet" + "Check for Updates…" + "Quit".

**Round trip (the actual smoke test):**
7. Make a tiny change in the repo — e.g., update the popover text from "MoleBar 0.0.1" to "MoleBar 0.0.2". Commit, tag `v0.0.2`, `git push --tags`.
8. Wait for `release.yml` to complete. Verify `MoleBar-0.0.2.dmg` is on the GH Release for `v0.0.2` and `appcast.xml` on gh-pages now references `0.0.2`.
9. Back on the Mac running 0.0.1, click the menu bar icon → "Check for Updates…".
10. **Acceptance criterion:** Sparkle's UI prompt appears, says "MoleBar 0.0.2 is available — Install?". The release notes from the GH Release body are visible.
11. Click "Install Update."
12. **Acceptance criterion:** Sparkle downloads the new DMG, verifies the EdDSA signature against the embedded `SUPublicEDKey`, mounts it, replaces `/Applications/MoleBar.app`, prompts to relaunch.
13. After relaunch, click the menu bar icon. **Acceptance criterion:** popover now reads "MoleBar 0.0.2 — nothing here yet".
14. (Optional supplementary check) Open Console.app, filter by "sparkle" subsystem, confirm no "EdDSA signature verification failed" messages.
15. (Optional supplementary check) Manually corrupt one byte in `appcast.xml` on gh-pages (push a deliberate typo), trigger Check for Updates… on a fresh 0.0.1 install. **Acceptance criterion:** Sparkle refuses the update with a signature-mismatch message in Console; UI shows "Update could not be loaded" or similar. Revert the typo afterward.

**Failure modes to watch for:**
- Sparkle says "improperly signed update" → check the `SUPublicEDKey` in the 0.0.1 Info.plist matches the public key derived from `SPARKLE_EDDSA_PRIVATE_KEY` (run `generate_keys -p` against the dev Keychain entry).
- Sparkle says "could not load feed" → check `https://puffpuff.dev/molebar/appcast.xml` is publicly reachable (incognito browser); GitHub Pages first-time setup wasn't done.
- The "Check for Updates…" button is permanently disabled → check `CheckForUpdatesViewModel.canCheckForUpdates` is being set; `startingUpdater: true` was passed to `SPUStandardUpdaterController.init`.
- The 0.0.2 install replaces 0.0.1 but launches showing 0.0.1's text → caching / wrong DMG was uploaded; verify `xcodebuild` injection of `MARKETING_VERSION` worked (`defaults read /Applications/MoleBar.app/Contents/Info CFBundleShortVersionString`).

## README Content (OSS-01)

Per CONTEXT.md "Claude's Discretion" + OSS-01:

**Tone:** match `tw93/mole` ethos (warm, technical, honest about what's done and not done). Include emoji sparingly per project convention; always lead with what MoleBar IS.

**Structure (recommended sections):**

```markdown
# MoleBar

A menu bar interface for [`tw93/mole`](https://github.com/tw93/mole) — deep-clean, optimize, and analyze your Mac without opening a terminal.

> **Status:** v0.0.1 is a distribution-pipeline smoke test. Real features land in v0.1+.

## Highlights

- **Menu bar first.** Live system stats + one-click cleaning, all from the menu bar.
- **Mole's safety model.** Dry-run-first by default; Trash, not `rm -rf`.
- **Native Swift.** macOS 14+, no Electron, ~5MB binary.
- **Zero telemetry.** Sparkle update check is the only outbound call.
- **Open source, MIT.** Same license as upstream Mole.

## Install

(For v0.0.1 dummy: GitHub Releases only; Homebrew Cask in Phase 1.5.)

```bash
# Download MoleBar.dmg from the latest GitHub Release
# Drag MoleBar.app to /Applications
# (v0.0.1 is unsigned; right-click → Open → Open Anyway. Signed builds in v0.1+.)
```

## Build from source

Requirements: macOS 14+, Xcode 16.4+, Homebrew.

```bash
git clone https://github.com/romatroskin/molebar.git
cd molebar
brew install create-dmg
open MoleBar.xcodeproj
# Cmd+R to run from Xcode
```

## Architecture

(Brief note on the SwiftPM module split + bundled Mole tree.)

## Contributing

(Guidelines: PRs welcome, run swift-format, no telemetry/analytics PRs accepted, Mole's safety model is non-negotiable.)

## License

MIT (see [LICENSE](LICENSE)).

Bundles Mole, MIT-licensed (see [LICENSE-MOLE.txt](LICENSE-MOLE.txt) — landing in v0.1).

## Acknowledgments

MoleBar wraps [`tw93/mole`](https://github.com/tw93/mole) by tw93 and contributors. All deep-clean, optimize, and analyze logic comes from Mole; MoleBar is just the UI.
```

**Badges (top of README):** GitHub Release (downloads), license (MIT), macOS version (14+), build status (GitHub Actions). Use shields.io URLs.

## Security Domain

Phase 1 has minimal direct security surface (no user data handled, no external network beyond Sparkle), but the secret-handling and supply-chain decisions made here echo through every later phase.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V1 Architecture | yes | Document the supply chain (Sparkle SPM, tw93/mole pinned tag) |
| V2 Authentication | partial | EdDSA signature verifies update authenticity; no user-facing auth |
| V3 Session Management | no | No sessions. |
| V4 Access Control | no | No multi-user model. |
| V5 Input Validation | no | No user input in Phase 1's stub. |
| V6 Cryptography | yes | Ed25519 (EdDSA) for update signatures — Sparkle implements; never hand-roll. |
| V7 Error Handling & Logging | partial | `os.Logger` planned for Phase 2; Phase 1's stub is silent. |
| V10 Malicious Code | yes | Supply-chain: pin Sparkle version + tw93/mole version; verify SHA at download time (Phase 8 expands this). |
| V14 Configuration | yes | CI secret hygiene; Push Protection; tempfile umask 077; shred. |

### Known Threat Patterns for Phase 1

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Sparkle EdDSA private key leak via CI logs | Tampering / Information Disclosure | `add-mask`; tempfile with `umask 077`; `shred` after use; never `set -x`; never `pull_request_target` |
| `SUPublicEDKey` mismatch / drift | Tampering | Lock public key into Info.plist BEFORE first public release; never modify; back up private key via iCloud Keychain + offline copy |
| Update artifact tampering between sign_update and upload | Tampering | sign_update LAST in pipeline; never re-zip / re-package after signing; CI verification step that re-runs sign_update on uploaded artifact (can be added Phase 1.5) |
| Compromised tw93/mole upstream release shipped to users | Tampering / Supply Chain | Pin upstream version in `mole-version.txt`; Phase 8 adds SHA-256 allowlist verification (deferred from Phase 1) |
| Forked-PR exfiltrates GH Actions secrets | Information Disclosure | Workflow triggers ONLY on `push` to tags, not `pull_request` or `pull_request_target` |
| GH Pages compromise serves malicious appcast | Tampering | EdDSA signature in appcast is verified by client app against Info.plist's `SUPublicEDKey` — even a malicious appcast cannot pass EdDSA verification without the private key |
| Repo secrets exposed via committed file | Information Disclosure | GitHub Push Protection enabled; `.gitignore` excludes `*.key`, `*.p8`, `*.p12`, `private/`; pre-commit hook (optional Phase 1.5) |

## Sources

### Primary (HIGH confidence)

- [Sparkle 2.9.1 release tag](https://github.com/sparkle-project/Sparkle/tags) — verified March 28, 2026 stable. **[VERIFIED]**
- [Sparkle Programmatic Setup docs](https://sparkle-project.org/documentation/programmatic-setup/) — `SPUStandardUpdaterController` SwiftUI integration. **[CITED]**
- [Sparkle Sandboxing docs](https://sparkle-project.org/documentation/sandboxing/) — confirms unsandboxed apps don't need XPC service Info.plist keys. **[CITED]**
- [Sparkle CHANGELOG 2.x branch](https://github.com/sparkle-project/Sparkle/blob/2.x/CHANGELOG) — 2.9.0 markdown release notes + feed signing + hardware requirements; 2.9.1 bug fixes. **[CITED]**
- [tw93/mole tags page](https://github.com/tw93/Mole/tags) — V1.36.2 (Apr 27, 2026) latest. **[VERIFIED]**
- [tw93/mole install.sh](https://raw.githubusercontent.com/tw93/mole/main/install.sh) — confirms per-arch Go helpers + Shell wrapper structure. **[VERIFIED]**
- [tw93/mole Makefile](https://raw.githubusercontent.com/tw93/mole/main/Makefile) — `release-amd64`/`release-arm64` targets produce `analyze-darwin-*`/`status-darwin-*`. **[VERIFIED]**
- [actions/runner-images macos-15 readme](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md) — Xcode 16.4 default; macOS 15.7.5; gh CLI 2.90; create-dmg NOT pre-installed. **[VERIFIED]**
- [create-dmg/create-dmg README](https://github.com/create-dmg/create-dmg) — Homebrew installable; standard CLI flags. **[VERIFIED]** + `brew info create-dmg` confirms 1.2.3 stable. **[VERIFIED]**
- [Apple: MenuBarExtraStyle](https://developer.apple.com/documentation/swiftui/menubarextrastyle) — `.window` style; macOS 13+. **[CITED]**
- [softprops/action-gh-release](https://github.com/softprops/action-gh-release) — v3.0.0 Apr 12, 2026. **[VERIFIED]**
- [peaceiris/actions-gh-pages](https://github.com/peaceiris/actions-gh-pages) — v4.0.0 Apr 8, 2024. **[VERIFIED]**

### Secondary (MEDIUM confidence — community / blog)

- [Sparkle Issue #1701 — SPM tools paths](https://github.com/sparkle-project/Sparkle/issues/1701) — confirms `SourcePackages/artifacts/sparkle/Sparkle/bin/` location. **[CITED]**
- [VibeTunnel: Sparkle keys docs](https://docs.vibetunnel.sh/mac/docs/sparkle-keys) — practical CI key handling (export from Keychain, store in CI secret, restore tempfile). **[CITED]**
- [Sparkle Discussion #2597 — sign_update for .dmg with EdDSA](https://github.com/sparkle-project/Sparkle/discussions/2597) — confirms `--ed-key-file` flag pattern. **[CITED]**
- [Sparkle Discussion #2174 — EdDSA verification failing](https://github.com/sparkle-project/Sparkle/discussions/2174) — common pitfalls in signing pipeline. **[CITED]**
- [Federico Terzi — Code-signing macOS apps with GitHub Actions](https://federicoterzi.com/blog/automatic-code-signing-and-notarization-for-macos-apps-using-github-actions/) — base64 cert into temp keychain pattern (Phase 1.5 reference). **[CITED]**
- [Apple Developer Forum thread on MARKETING_VERSION + Info.plist](https://developer.apple.com/forums/thread/709065) — confirms `$(MARKETING_VERSION)` placeholder pattern. **[CITED]**
- [Alex Perathoner — Automating Xcode Sparkle Releases with GitHub Actions](https://medium.com/@alex.pera/automating-xcode-sparkle-releases-with-github-actions-bd14f3ca92aa) — release-yaml shape reference. **[CITED]**
- [Ram Patra — Automatically generate appcast.xml](https://blog.rampatra.com/automatically-generate-appcast-xml-and-dmg-files-for-your-mac-app-updates) — appcast XML structure reference. **[CITED]**
- [Sarunw — Create a mac menu bar app in SwiftUI with MenuBarExtra](https://sarunw.com/posts/swiftui-menu-bar-app/) — MenuBarExtra `.window` reference. **[CITED]**

### Tertiary (LOW confidence — needs validation during planning)

- A2: `sign_update` output format `sparkle:edSignature="..." length="..."` direct-XML inline pattern — verify by running `sign_update -h` once. Mitigation: whole-line capture pattern is robust against format changes.
- A8: `tw93/mole` URL pattern stability — verify by `curl -fsSI` against pinned tag at planning time.
- A9: `mole` Shell wrapper's relative-path resolution behavior — verify by reading the script during Phase 1 implementation; may require `sed`-patching `SCRIPT_DIR`.

## Metadata

**Confidence breakdown:**

- Standard stack (Sparkle 2.9.1, create-dmg 1.2.3, GH Actions versions, macos-15 runner Xcode 16.4): **HIGH** — every version verified against official sources during this session.
- Architecture patterns (SwiftUI MenuBarExtra `.window` + Sparkle `SPUStandardUpdaterController`): **HIGH** — Apple-documented + Sparkle-documented.
- EdDSA key tooling + CI secret hygiene: **HIGH** — multi-source verification (Sparkle issues, VibeTunnel docs, Federico Terzi blog).
- Mole binary bundling recipe: **MEDIUM** — the corrected recipe (Pitfall A1) is sound based on upstream artifacts inspection, but the assumption A9 about `mole` script path-resolution behavior needs verification during planning.
- Common pitfalls: **HIGH** for the canonical 4 (EdDSA unrotatability, re-zip-after-sign, Push Protection, MARKETING_VERSION placeholder); **MEDIUM** on the Mole-specific pitfall A1 (which is novel in this research).

**Research date:** 2026-04-27
**Valid until:** 2026-07-27 (90 days for distribution-layer; Sparkle 2.9.x is mature, GH Actions changes infrequently, `tw93/mole` cadence is ~weekly so version pin should be reviewed before each Phase 1 ship)

---

*Phase 1 research synthesized 2026-04-27. Ready for `/gsd-plan-phase` to proceed.*
