# Phase 1: Distribution Foundations - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-27
**Phase:** 1-distribution-foundations
**Areas discussed:** Identity & ownership, Sparkle EdDSA key, CI & secret model, 0.0.1 dummy scope

---

## Identity & Ownership

### Apple Developer ID source

| Option | Description | Selected |
|--------|-------------|----------|
| I have one ready | Active Apple Developer Program membership with Developer ID Application cert | |
| I will enroll now | Will enroll in Apple Developer Program before Phase 1 ships ($99/yr) | |
| Use a friend's Team ID | Sign under someone else's Developer ID for now | |
| Defer signing setup | Build everything except actual signing in Phase 1; stub out signing | ✓ |

**User's choice:** Defer signing setup
**Notes:** Triggered the Phase 1.5 insertion. Phase 1 ships unsigned through the pipeline; signing is retrofitted in Phase 1.5 once Apple Developer Program enrollment completes.

### Repo home

| Option | Description | Selected |
|--------|-------------|----------|
| github.com/romatroskin/molebar | Personal namespace under existing account | ✓ |
| Dedicated org | Create a `molebar` org and house everything under it | |
| Different namespace | Other handle / org | |

**User's choice:** github.com/romatroskin/molebar
**Notes:** Solo open-source project; no co-maintainer overhead needed for v1.

### Bundle identifier

| Option | Description | Selected |
|--------|-------------|----------|
| app.molebar.MoleBar | Reverse-DNS based on hypothetical molebar.app domain | ✓ |
| io.github.romatroskin.MoleBar | Reverse-DNS of GitHub URL — zero domain dependency | |
| com.romatroskin.MoleBar | Reverse-DNS of personal namespace | |
| Decide later | Lock in during scaffolding plan task | |

**User's choice:** app.molebar.MoleBar
**Notes:** Anticipates owning `molebar.app` domain; usable today even without the domain. Locked into Info.plist, Sparkle resolution, Keychain ACLs, and LaunchAgent label (Phase 7).

### Cask tap location

| Option | Description | Selected |
|--------|-------------|----------|
| Personal tap | `romatroskin/homebrew-tap` — ship from day one | |
| homebrew-cask main | Submit to official `homebrew/cask` repo | |
| Both, eventually | Personal tap for v1.x; main repo post-v1 | |
| Skip Cask in Phase 1 | Defer Cask publication entirely | ✓ |

**User's choice:** Skip Cask in Phase 1
**Notes:** DIST-07 moved to Phase 1.5. Personal tap (`romatroskin/homebrew-tap`) is the eventual channel; official Cask submission deferred to a post-v1 phase.

---

## Sparkle EdDSA Key

### Key generation

| Option | Description | Selected |
|--------|-------------|----------|
| Local Mac, one time | Run `generate_keys` on Mac in Phase 1; key stays on machine + backups | |
| Local + macOS Keychain | Generate locally, immediately import into Keychain with strong password | ✓ |
| 1Password / hardware key | Generate locally, move to 1Password Secrets Automation | |
| Defer | Set up plumbing in Phase 1; generate real key right before first signed release | |

**User's choice:** Local + macOS Keychain
**Notes:** Highest security with reasonable friction. Plain key file on disk is deleted after Keychain import. Keychain is canonical source of truth; CI secret is a mirror.

### Key backup

| Option | Description | Selected |
|--------|-------------|----------|
| iCloud Keychain | Synced to Apple ID; recoverable via account recovery | ✓ |
| 1Password / Bitwarden | Stored in personal vault with backup codes | |
| Encrypted file + offline | Encrypted USB + printed paper copy in safe | |
| Multiple of the above | Combination | |

**User's choice:** iCloud Keychain
**Notes:** Apple ID compromise = EdDSA key compromise. Mitigation: strong Apple ID password + hardware security key on the Apple ID account.

### CI key injection

| Option | Description | Selected |
|--------|-------------|----------|
| GH Actions secret | Repo secret `SPARKLE_EDDSA_PRIVATE_KEY`; piped to `sign_update` | ✓ |
| GH Actions environment | Required reviewer approval before release jobs read secret | |
| OIDC + Vault / Secrets Mgr | Federate to AWS / Vault / 1Password Connect | |
| I'll handle CI manually | Sign appcast locally, commit signed appcast file | |

**User's choice:** GH Actions secret
**Notes:** Standard pattern, two-keystroke setup. Manual one-time bootstrap from local Keychain → GH secret. Refresh by re-exporting.

### Public key location

| Option | Description | Selected |
|--------|-------------|----------|
| Info.plist (standard) | Embed `SUPublicEDKey` in app's Info.plist | ✓ |
| Hardcoded in Swift | Define as a Swift constant | |
| Decide later | Decide during scaffolding plan task | |

**User's choice:** Info.plist (standard)
**Notes:** Industry-standard Sparkle pattern. Once first release published with this public key, the value is **frozen forever**.

---

## CI & Secret Model

### CI runner

| Option | Description | Selected |
|--------|-------------|----------|
| GH-hosted macos-15 | Free for public repos, current Xcode 16+ | ✓ |
| GH-hosted macos-14 | Pin to deployment-target floor | |
| Self-hosted Mac | Mac mini / iMac running GitHub Actions runner | |
| Both, eventually | Start hosted; switch if build times become painful | |

**User's choice:** GH-hosted macos-15
**Notes:** Default for v1. Reconsider if hosted-runner build times exceed 15 minutes.

### Notarization auth

| Option | Description | Selected |
|--------|-------------|----------|
| ASC API Key | App Store Connect API Key (Issuer ID + Key ID + .p8) | ✓ |
| Apple ID + app password | Apple ID + app-specific password + Team ID | |
| Decide when Dev ID lands | Stub in Phase 1; pick auth model in Phase 1.5 | |

**User's choice:** ASC API Key
**Notes:** Modern path, more granular permissions, no Apple ID 2FA hassle in CI. Plumbed up in Phase 1 with empty-secret stub-out; secrets added in Phase 1.5.

### CI trigger

| Option | Description | Selected |
|--------|-------------|----------|
| Tag push (vX.Y.Z) | `git tag v0.0.1 && git push --tags` triggers release | ✓ |
| Manual workflow dispatch | GH Actions "Run workflow" button with version input | |
| Tag push + manual approval | Tag push triggers workflow; pauses for approval | |
| Branch (main) | Any push to `main` triggers release | |

**User's choice:** Tag push (vX.Y.Z)
**Notes:** Standard semver flow. Clean separation of "build a release" from regular pushes. No manual approval gate in v1; revisit after first incident.

### Appcast hosting

| Option | Description | Selected |
|--------|-------------|----------|
| GitHub Pages (gh-pages) | CI commits signed appcast.xml to gh-pages branch | ✓ |
| Release asset | Append appcast to each GitHub Release as an asset | |
| Custom domain (molebar.app) | Host appcast at https://molebar.app/appcast.xml | |
| Decide later | Use placeholder localhost URL; lock real URL later | |

**User's choice:** GitHub Pages (gh-pages)
**Notes:** Locked URL: `https://romatroskin.github.io/molebar/appcast.xml`. Bakes into Info.plist's `SUFeedURL`. Custom domain migration is a deferred v1.x polish task.

---

## 0.0.1 Dummy Scope

### Dummy UI

| Option | Description | Selected |
|--------|-------------|----------|
| MenuBarExtra stub | Tiny popover saying "MoleBar 0.0.1" + Quit + version | |
| Pure Hello World | Console-only or trivial regular window app | |
| MenuBarExtra + version check | Stub above PLUS "Check for Updates…" via SPUUpdater | ✓ |

**User's choice:** MenuBarExtra + version check
**Notes:** "Check for Updates…" is the user-triggerable smoke-test surface for the Sparkle round-trip, not just polish. Smoke test plan: install 0.0.1 → click "Check for Updates…" → confirm 0.0.2 prompt → install → relaunch → confirm new version string.

### Bundle mole?

| Option | Description | Selected |
|--------|-------------|----------|
| Bundle real mole | Pin upstream release; lipo arm64+x86_64 into Universal2 | ✓ |
| Bundle a stub | 1-line shell stub at Contents/Helpers/mole that echoes "stub" | |
| arm64-only real mole | Bundle real mole but skip lipo step | |
| No mole in 0.0.1 | Defer binary bundling to Phase 2 | |

**User's choice:** Bundle real mole
**Notes:** Pinned upstream version recorded in `mole-version.txt`. Bumping is a manual human-reviewed PR. Phase 1 invokes the binary once with `--version` to validate path resolution; full subprocess orchestration is Phase 2.

### Versioning

| Option | Description | Selected |
|--------|-------------|----------|
| Semver from tag | Tag `v0.0.1` → CFBundleShortVersionString=0.0.1; CFBundleVersion=run number | ✓ |
| Semver + commit hash | CFBundleVersion = git short SHA | |
| Date-based | CFBundleVersion = YYYY.MM.DD.NNN | |
| Manual in Info.plist | Edit values by hand for each release | |

**User's choice:** Semver from tag
**Notes:** Industry-standard. Both values injected at build time via xcodebuild build settings; Info.plist uses `${MARKETING_VERSION}` and `${CURRENT_PROJECT_VERSION}` placeholders.

### DMG style

| Option | Description | Selected |
|--------|-------------|----------|
| Standard drag-to-Applications | MoleBar.app + symlink to /Applications + background image | ✓ |
| Plain DMG | Bare DMG with just MoleBar.app | |
| Decide later | Ship something minimal in 0.0.1; polish in Phase 1.5 | |

**User's choice:** Standard drag-to-Applications
**Notes:** Built via shell `create-dmg/create-dmg` tool. Background image at `dmg-assets/background.png`; falls back to no-background two-icon layout if missing.

---

## Closing Decision

### Phase 1.5 insertion timing

| Option | Description | Selected |
|--------|-------------|----------|
| Ready for context | Write CONTEXT.md; flag Phase 1.5 as follow-up | |
| Insert Phase 1.5 now | Update ROADMAP.md immediately; tighten Phase 1 boundary | ✓ |
| Discuss more areas | Identify additional gray areas | |

**User's choice:** Insert Phase 1.5 now
**Notes:** ROADMAP.md and REQUIREMENTS.md updated in same workflow run. DIST-01, DIST-02, DIST-03, DIST-07 moved Phase 1 → Phase 1.5. Phase 1 success criteria rewritten for unsigned smoke test. Phase 1.5 added with its own goal, depends-on, requirements, and 5 success criteria.

---

## Claude's Discretion

- Exact pinned upstream `tw93/mole` version for the Phase 1 bundled binary — planner picks latest stable release at Phase 1 start, records in `mole-version.txt`.
- Exact disk layout of `dmg-assets/` (background dimensions, icon placement, window size) — sensible `create-dmg` defaults; cheap to iterate.
- README prose — contributor-friendly, matching `tw93/mole` ethos in tone.

## Deferred Ideas

- GitHub Actions Environment with required reviewer approval before release jobs run — post-v1 hardening pass.
- OIDC federation to AWS Secrets Manager / 1Password Connect for CI secrets — overkill for solo project.
- Submitting Cask to `homebrew/cask` main repo — deliberate post-v1 milestone.
- Custom domain (`molebar.app`) acquisition + appcast migration off `github.io` — v1.x polish task.
- `CFBundleVersion = git short SHA` alternative versioning — declined; CI run number won.
