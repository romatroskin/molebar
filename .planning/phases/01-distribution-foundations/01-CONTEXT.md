# Phase 1: Distribution Foundations - Context

**Gathered:** 2026-04-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 1 ships an **unsigned 0.0.1 dummy release** end-to-end through the entire CI pipeline (build → DMG → Sparkle appcast → 0.0.1 → 0.0.2 round-trip). The phase locks every unrotatable distribution-layer decision (Sparkle EdDSA key, repo/tap topology, CI secret hygiene, bundle ID, appcast URL) **before any feature exists**. Code signing and notarization steps are scaffolded into the pipeline as stubbed/skipped jobs — they activate in the inserted Phase 1.5 once the Apple Developer ID is in hand.

**In scope (6 requirements):** DIST-04, DIST-05, DIST-06, DIST-08, OSS-01, OSS-04.

**Moved to Phase 1.5 during discussion (4 requirements):** DIST-01, DIST-02, DIST-03, DIST-07. These remain blocked on Apple Developer Program enrollment; the inserted Phase 1.5 retrofits the pipeline with real signing, notarization, bundled-binary re-signing, and Homebrew Cask publication once the Dev ID arrives.

**Definitely not this phase:** any application feature, any UI beyond the MenuBarExtra version-stub popover, any `mole` subprocess invocation beyond a single launch-and-version smoke test (the actor-wrapped orchestration core is Phase 2), any cleaning/optimize/purge/installer logic.

</domain>

<decisions>
## Implementation Decisions

### Identity & Ownership

- **D-01:** Apple Developer ID signing is **deferred** for Phase 1. The CI pipeline includes signing/notarization/staple/Cask jobs as scaffolded stubs (skip-on-empty-secret pattern) so they activate the moment the Dev ID and ASC API Key land in GitHub Actions secrets. Phase 1.5 turns them on and ships the first real signed release.
- **D-02:** Repo lives at **`github.com/romatroskin/molebar`** — personal namespace, public, MIT-licensed. No dedicated org for v1; revisit if co-maintainers join.
- **D-03:** macOS bundle identifier is **`app.molebar.MoleBar`** (reverse-DNS based on a hypothetical `molebar.app` domain). This value is locked into `Info.plist`, Sparkle's `SUFeedURL` resolution, Keychain ACLs, and the LaunchAgent label that Phase 7 will use — changing it post-launch is hostile to existing users.
- **D-04:** Homebrew Cask is **deferred to Phase 1.5** (DIST-07 moved). Phase 1 ships only the GitHub Releases `.dmg` + Sparkle appcast. The Cask formula will live in **`romatroskin/homebrew-tap`** (personal tap), not in `homebrew/cask` main — official Cask submission deferred to a post-v1 phase once the project meets inclusion criteria.

### Sparkle EdDSA Key (Unrotatable Post-Launch)

- **D-05:** The EdDSA private key is generated **locally on the developer Mac** via Sparkle's `generate_keys` tool (from the SwiftPM artifact bundle), then immediately imported into the **macOS Keychain** with a strong password. The key file on disk is then deleted. The Keychain entry is the canonical source of truth; the key is never stored as a plain file anywhere.
- **D-06:** Backup strategy is **iCloud Keychain sync**. The Keychain entry is automatically synced to all of the developer's Apple-ID-linked devices, with Apple's account-recovery flow as the disaster-recovery path. Acceptable risk: an Apple ID compromise compromises the EdDSA key. Mitigation: strong Apple ID password + hardware security key.
- **D-07:** CI delivery model is a **GitHub Actions repository secret** named `SPARKLE_EDDSA_PRIVATE_KEY`. The key is one-time-bootstrapped by exporting from local Keychain and pasting into the GitHub Actions secret UI. Refresh requires re-exporting — the public key embedded in users' apps never changes (it can't), but the GH-side mirror of the private key can be rotated without affecting users.
- **D-08:** The Sparkle PUBLIC key (`SUPublicEDKey`) is embedded in the app's **`Info.plist`** (Sparkle's industry-standard convention). Once the first real release with a given public key is published, the value is **frozen forever** — every prior MoleBar install will only accept updates signed by the matching private key.

### CI & Secret Model

- **D-09:** Release builds run on **GitHub-hosted `macos-15`** runners. Free for public repos, ships current Xcode 16+, builds for the macOS 14+ deployment target without issue. Self-hosted Mac runners reconsidered only if hosted-runner build times exceed 15 minutes.
- **D-10:** Notarization auth uses an **App Store Connect API Key** (Issuer ID + Key ID + `.p8`) — the modern path, more granular permissions than Apple ID + app-specific password, no Apple ID 2FA hassle in CI. The API key plumbing is wired in Phase 1 with empty-secret stub-out; the actual key is added as `ASC_API_KEY_ID`, `ASC_ISSUER_ID`, `ASC_API_KEY_P8` GitHub Actions secrets in Phase 1.5.
- **D-11:** CI release trigger is **tag push** in `vX.Y.Z` semver format. `git tag v0.0.1 && git push --tags` triggers the release workflow which: builds → packages DMG → signs (stub in Phase 1) → notarizes (stub in Phase 1) → produces appcast entry → commits to `gh-pages` → uploads release. No manual approval gate for v1; revisit after first incident if needed.
- **D-12:** Sparkle appcast XML is published to **`https://romatroskin.github.io/molebar/appcast.xml`** via the repo's `gh-pages` branch (GitHub Pages auto-publish). CI commits the EdDSA-signed appcast.xml to `gh-pages` on every release. URL is locked into `Info.plist`'s `SUFeedURL` — changing it later strands existing users.

### 0.0.1 Dummy Scope

- **D-13:** The 0.0.1 dummy is a **`MenuBarExtra(style: .window)` stub** with a tiny popover showing "MoleBar 0.0.1 — nothing here yet", a "Check for Updates…" menu item wired to `SPUUpdater.checkForUpdates()`, and a Quit item. This exercises the actual UI primitive Phase 3 will build on, plus gives the user a one-click way to manually trigger the Sparkle round-trip during the smoke test.
- **D-14:** The dummy bundles the **real `mole` binary** at `Contents/Helpers/mole`, **Universal2** (CI downloads both arm64 and x86_64 from a pinned upstream `tw93/mole` release, runs `lipo -create`, drops the result in the bundle). Pinned upstream version is recorded in `mole-version.txt` at the repo root and is bumped as a deliberate human-reviewed PR (no automation in v1). Phase 1's smoke test invokes the bundled binary once with `--version` to confirm path resolution and execution work; full subprocess orchestration is Phase 2.
- **D-15:** Versioning derives from the git tag: `CFBundleShortVersionString` = the tag's semver (`v0.0.1` → `0.0.1`), `CFBundleVersion` = the GitHub Actions run number (monotonic). Both values are injected at build time via `xcodebuild` build settings; `Info.plist` uses `${MARKETING_VERSION}` and `${CURRENT_PROJECT_VERSION}` placeholders.
- **D-16:** DMG layout is the **standard drag-to-Applications** form: `MoleBar.app` icon + symlink to `/Applications` + a background hint image, built via the shell `create-dmg/create-dmg` tool. The background image is committed to the repo at `dmg-assets/background.png`; if it's missing, the DMG falls back to a no-background two-icon layout (Phase 1 acceptable).

### Architectural Implications for Downstream Phases

- **D-17:** The bundle structure decided here — `Contents/Helpers/mole` for the bundled CLI fallback, with the runtime resolver preferring `~/Library/Application Support/MoleBar/bin/mole` once Phase 8's `MoleBinaryUpdater` ships — is locked. Phase 2's `MoleClient.resolveBinary()` follows this precedence; Phase 8's updater writes ONLY to the user-Application-Support path and never modifies the in-bundle copy.
- **D-18:** The "scaffolded but skipped" CI pattern from Phase 1 means `.github/workflows/release.yml` already contains every step (sign, notarize, staple, Cask bump) but each step is wrapped in `if: ${{ secrets.SECRET_NAME != '' }}`. Phase 1.5's work is mostly **adding the secrets**, not editing the workflow file — which keeps the pipeline auditable and reduces the diff that introduces signing.

### Claude's Discretion

- The exact pinned upstream `tw93/mole` version for the Phase 1 bundled binary — the planner picks the latest stable tagged release at the time Phase 1 ships, records it in `mole-version.txt`, and pins it. Bumping is a manual PR thereafter.
- The exact disk layout of `dmg-assets/` (background dimensions, icon placement, window size) — the planner uses sensible defaults consistent with `create-dmg` examples; iteration is cheap.
- The README's exact prose — the planner produces a contributor-friendly README per OSS-01 with sections on what MoleBar is, install (point users at GitHub Releases for v1, mention Cask once Phase 1.5 ships), build-from-source instructions, license, and a clear `tw93/mole` upstream attribution. Tone matches the Mole project ethos.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project-level

- `.planning/PROJECT.md` — Constraints, Out of Scope, Key Decisions; especially the open-source / no-telemetry / hardened-runtime posture.
- `.planning/REQUIREMENTS.md` — DIST-04, DIST-05, DIST-06, DIST-08, OSS-01, OSS-04 verbatim wording.
- `.planning/ROADMAP.md` — Phase 1 success criteria (revised after this discussion); Phase 1.5 inserted between Phase 1 and Phase 2.

### Research synthesis

- `.planning/research/SUMMARY.md` — Reconciled phase ordering and conflict resolutions (subprocess library, MenuBarExtra style, distribution-before-features).
- `.planning/research/STACK.md` — Specific versioned recommendations for Sparkle 2.9.x, `create-dmg` (shell variant), `notarytool`, GitHub Actions on `macos-14/15`, `LanikSJ/homebrew-bump-cask` (referenced for Phase 1.5).
- `.planning/research/PITFALLS.md` — P0 ship-blockers: bundled-binary notarization, Sparkle EdDSA key handling, CI secret hygiene, `codesign --deep` deprecation. Read before writing the release workflow.

### External / upstream

- [Sparkle 2 documentation](https://sparkle-project.org/documentation/) — `SUFeedURL`, `SUPublicEDKey`, `SURequireSignedFeed`, `generate_keys`, `sign_update` (consult during planning).
- [Apple Developer: notarizing macOS software](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution) — `notarytool`, `stapler` (referenced for Phase 1.5 retrofit).
- [`tw93/mole` Releases](https://github.com/tw93/mole/releases) — pinned-version source for the bundled binary.
- [`create-dmg/create-dmg`](https://github.com/create-dmg/create-dmg) — shell DMG builder.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **None — greenfield.** Repository was just initialized; only `.planning/`, `.git/`, and `CLAUDE.md` exist.

### Established Patterns

- The roadmap-mandated **`MoleBarCore` / `MoleBarStores` / `MoleBarUI` SwiftPM module split** (from `research/ARCHITECTURE.md`) does not yet exist — Phase 1 introduces the Xcode project + the empty SwiftPM workspace shape so Phase 2 has a place to land. Phase 1 itself only writes UI code (the MenuBarExtra stub) and Sparkle wiring; it does NOT introduce Mole subprocess code (that's Phase 2).

### Integration Points

- **`Contents/Helpers/mole` bundle path** — Phase 2's `MoleClient.resolveBinary()` will read from this path. Phase 1 must guarantee the path exists, the binary is executable, and the parent directory's `chmod` allows future user-Application-Support overrides per Phase 8.
- **`Info.plist` keys** — Phase 1 sets `SUFeedURL`, `SUPublicEDKey`, `SURequireSignedFeed=YES`, `LSUIElement=YES` (menu-bar app, no Dock icon), and the bundle identifier `app.molebar.MoleBar`. Subsequent phases append (Phase 4: privacy strings, Phase 7: LaunchAgent helper bundle ref). Phase 1 sets the structural baseline.
- **`.github/workflows/release.yml`** — every later phase that touches CI (Phase 7's LaunchAgent helper, Phase 8's binary updater) appends to or modifies this workflow. The "scaffolded but skipped" pattern from D-18 means downstream work is additive, not rewrites.

</code_context>

<specifics>
## Specific Ideas

- The "Check for Updates…" menu item in the 0.0.1 dummy is non-negotiable — it's the user-triggerable smoke test surface for the Sparkle round-trip, not just polish. The smoke test plan should explicitly script: install 0.0.1 → click "Check for Updates…" → confirm 0.0.2 prompt → install update → relaunch → confirm new version string in popover.
- "Scaffolded but skipped" means the workflow file is *complete* on day one of Phase 1 — including the signing job, the notarize job, the staple job, the Cask-bump job — each guarded by `if: ${{ secrets.SECRET_NAME != '' }}`. The Phase 1.5 PR adds the secrets and removes (or leaves) the guards. The pipeline diff between unsigned and signed is then minimal and auditable.

</specifics>

<deferred>
## Deferred Ideas

- **GitHub Actions Environment with required reviewer approval before release jobs run** — discussed but not selected for v1; revisit after first incident or as a post-v1 hardening pass.
- **OIDC federation to AWS Secrets Manager / 1Password Connect for CI secrets** — overkill for solo project with one EdDSA key; mentioned for completeness, not on roadmap.
- **Submitting Cask to `homebrew/cask` main repo** — requires meeting the `homebrew-cask` inclusion criteria (notarized, signed, stable). Personal tap is the v1 channel; main-repo submission is a deliberate post-v1 milestone.
- **Custom domain (`molebar.app`)** — bundle ID anticipates it (`app.molebar.MoleBar`), but acquiring the domain and migrating appcast off `github.io` is a v1.x polish task, not a Phase 1 deliverable.
- **`CFBundleVersion = git short SHA`** — discussed; CI run number won out for monotonic ordering. Not worth revisiting.

</deferred>

---

*Phase: 1-Distribution Foundations*
*Context gathered: 2026-04-27*
