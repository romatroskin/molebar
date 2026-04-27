---
phase: 1
slug: distribution-foundations
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-27
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Phase 1 has minimal automated test surface — the dummy app has no behavior. Validation is dominated by **integration / smoke tests** validated end-to-end against a real CI run + real user-machine install.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (built-in to Xcode 16.4) — empty target in Phase 1, populated in Phase 2 |
| **Config file** | `MoleBar.xcodeproj/xcshareddata/xcschemes/MoleBar.xcscheme` (test action enabled) |
| **Quick run command** | `xcodebuild build -project MoleBar.xcodeproj -scheme MoleBar -destination 'platform=macOS,arch=arm64'` |
| **Full suite command** | `xcodebuild test -project MoleBar.xcodeproj -scheme MoleBar -destination 'platform=macOS,arch=arm64'` (vacuous in Phase 1) |
| **Estimated runtime** | ~30s (build), ~45s (test target with no tests) |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild build -project MoleBar.xcodeproj -scheme MoleBar -destination 'platform=macOS,arch=arm64'`
- **After every plan wave:** Run `xcodebuild test ...` (vacuous but exercises the plumbing)
- **Before `/gsd-verify-work`:** End-to-end smoke test (DIST-08) must pass on a clean Mac
- **Max feedback latency:** ~30s for build; smoke test is manual and ~10 minutes

---

## Per-Task Verification Map

| Req ID | Behavior | Test Type | Automated Command | File Exists | Status |
|--------|----------|-----------|-------------------|-------------|--------|
| DIST-04 | `.dmg` produced via `create-dmg` on tag push | integration (CI) | Push tag `v0.0.1`; observe `release.yml` succeed; verify `MoleBar-0.0.1.dmg` is uploaded to GitHub Release: `gh release view v0.0.1 --json assets --jq '.assets[].name'` should include `MoleBar-0.0.1.dmg` | ❌ W0 | ⬜ pending |
| DIST-05 | GH Actions release workflow runs on tag push | integration (CI) | `gh run list --workflow=release.yml --limit 5`; latest run must be `completed success`; all stubbed-secret-guarded steps emit "skipping (secret not set)" log entries | ❌ W0 | ⬜ pending |
| DIST-06 | Sparkle 2.x in-app updater fetches signed appcast with EdDSA verification | integration (manual) | Launch app → Check for Updates… → confirm Sparkle prompts. Then corrupt appcast.xml on `gh-pages` by 1 byte → confirm Sparkle refuses update with EdDSA-mismatch in Console.app | ❌ W0 | ⬜ pending |
| DIST-08 | 0.0.1 → 0.0.2 round-trip succeeds end-to-end | integration (manual) | See §Smoke Test (Round-Trip) Plan in `01-RESEARCH.md`. Run all 15 steps; all 5 acceptance criteria must pass | ❌ W0 | ⬜ pending |
| OSS-01 | Public MIT repo + README + Pages enabled | review (mostly automated) | `gh repo view romatroskin/molebar --json visibility,licenseInfo` returns `{"visibility":"PUBLIC","licenseInfo":{"key":"mit"}}`; `test -f LICENSE && grep -q 'MIT' LICENSE`; `test -f README.md && grep -qE '## (Install|Build|Contributing)' README.md`; `gh api repos/romatroskin/molebar/pages` returns 200 with `status: built` | ❌ W0 | ⬜ pending |
| OSS-04 | Signing keys in GH Actions secrets only — no leaks in repo or logs | automated check + review | (1) `git log --all -p \| grep -E "BEGIN.*PRIVATE KEY\|^edpr"` returns nothing; (2) `for id in $(gh run list --workflow=release.yml --limit 5 --json databaseId -q '.[].databaseId'); do gh run view $id --log \| grep -iE '(edpr\|BEGIN PRIVATE\|p8\b)'; done` returns nothing; (3) `gh api repos/romatroskin/molebar/secret-scanning/alerts` returns empty list (Push Protection blocked all leaks) | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Phase 1 is greenfield — every artifact is a Wave 0 dependency. Listed in dependency order:

### Source files (created by plan tasks)

- [ ] `MoleBar.xcodeproj/project.pbxproj` — Xcode project (created via Xcode UI or XcodeGen `project.yml`)
- [ ] `MoleBar/Info.plist` — bundle ID `app.molebar.MoleBar`, `LSUIElement=YES`, `SUFeedURL`, `SUPublicEDKey`, `SUEnableInstallerLauncherService`, `SUEnableDownloaderService`, `SUEnableAutomaticChecks`, version placeholders `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`
- [ ] `MoleBar/MoleBar.entitlements` — empty plist (Phase 1.5 fills entitlements)
- [ ] `MoleBar/MoleBarApp.swift` — `@main` App with `MenuBarExtra(.window)` + Sparkle `SPUStandardUpdaterController` wiring
- [ ] `MoleBar/PopoverRootView.swift` — popover content with version string + "Check for Updates…" + "Quit"
- [ ] `MoleBar/CheckForUpdatesView.swift` — Sparkle's standard pattern (binding `canCheckForUpdates`)
- [ ] `MoleBarTests/MoleBarTests.swift` — empty XCTestCase subclass (test target plumbing)
- [ ] `Packages/MoleBarPackage/Package.swift` — local SwiftPM package with three empty modules (`MoleBarCore`, `MoleBarStores`, `MoleBarUI`) — Phase 2+ populates them
- [ ] `Packages/MoleBarPackage/Sources/MoleBarCore/MoleBarCore.swift` — empty module file
- [ ] `Packages/MoleBarPackage/Sources/MoleBarStores/MoleBarStores.swift` — empty module file
- [ ] `Packages/MoleBarPackage/Sources/MoleBarUI/MoleBarUI.swift` — empty module file

### CI / distribution files

- [ ] `.github/workflows/release.yml` — complete-with-stubs release workflow (build → DMG → sign-stub → notarize-stub → staple-stub → sign_update → gh-pages commit → GH Release upload → Cask-stub)
- [ ] `.github/workflows/build.yml` — PR-time build verification (no release artifacts)
- [ ] `mole-version.txt` — pinned upstream Mole version (`V1.36.2` per researcher recommendation; verify still latest at planning time)
- [ ] `dmg-assets/background.png` — DMG background image (or document fallback per CONTEXT D-16)

### Repo metadata

- [ ] `LICENSE` — MIT license text
- [ ] `README.md` — contributor-friendly README per RESEARCH §README Content
- [ ] `.gitignore` — excludes build outputs, `DerivedData/`, `xcuserdata/`, `*.xcuserstate`, Sparkle key files (`*.key`, `*.p8`, `*.p12`, `private/`)
- [ ] `CLAUDE.md` — already exists from `/gsd-new-project`; revisit if Phase 1 changes baseline conventions

### Manual GitHub repo settings (one-time, recorded as a plan task with `autonomous: false`)

- [ ] Repo `romatroskin/molebar` created and made public
- [ ] **Push Protection enabled** (Settings → Code Security → Secret scanning → Push protection)
- [ ] **Secret scanning enabled** (same panel)
- [ ] **GitHub Pages enabled**, source = `gh-pages` branch root → custom 404 not required for Phase 1
- [ ] Repository secret created: `SPARKLE_EDDSA_PRIVATE_KEY` (from local Keychain via Sparkle's `generate_keys -x`)
- [ ] Repository secrets created EMPTY for Phase 1 (filled in Phase 1.5): `MACOS_CERT`, `MACOS_CERT_PWD`, `MACOS_CERT_NAME`, `MACOS_CI_KEYCHAIN_PWD`, `ASC_API_KEY_ID`, `ASC_ISSUER_ID`, `ASC_API_KEY_P8`, `HOMEBREW_GITHUB_TOKEN`. (Note: an empty secret evaluates the same as no secret to GH Actions; `if: ${{ secrets.X != '' }}` works either way.)
- [ ] Branch protection on `main` (optional Phase 1; recommended Phase 1.5): require status checks (`build.yml`); disallow force push

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Round-trip 0.0.1 → 0.0.2 update | DIST-08 | Requires real install on a clean Mac (or fresh user account) + manual click-through of Sparkle's UI; cannot be fully scripted from CI | See `01-RESEARCH.md` §Smoke Test Plan — 15 steps with 5 acceptance criteria |
| EdDSA tampering detection | DIST-06 | Requires manually corrupting appcast.xml then verifying Sparkle's refusal in Console.app | Step 15 of the smoke test plan |
| Gatekeeper "unidentified developer" UX | DIST-04 (partial — unsigned in Phase 1) | Confirms the user-facing experience users will encounter on first launch (right-click → Open → Open Anyway). Documented in README. Resolved in Phase 1.5. | Steps 4-5 of the smoke test plan |
| GitHub Pages first-time setup | DIST-06 (delivery) | One-time UI step in repo settings; not API-automatable cleanly | Settings → Pages → Source = `gh-pages` branch / `(root)` → Save; wait for first deploy |
| Sparkle EdDSA private key generation + Keychain import + GH secret bootstrap | DIST-06 (CI auth) | Local Mac operation; touches user Keychain; manual one-time | `~/Library/Developer/Xcode/DerivedData/MoleBar-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys` (after first SPM resolve); export with `generate_keys -x`; paste into `gh secret set SPARKLE_EDDSA_PRIVATE_KEY` |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies (most Phase 1 verifications ARE Wave 0 — that's expected for a greenfield distribution phase)
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify (use `xcodebuild build` as the universal sampling command between artifact-creation tasks)
- [ ] Wave 0 covers all MISSING references — see Wave 0 Requirements above
- [ ] No watch-mode flags (xcodebuild does not enter watch mode by default)
- [ ] Feedback latency < 60s (build is ~30s on macos-15)
- [ ] `nyquist_compliant: true` set in frontmatter once all manual verifications passed at least once

**Approval:** pending
