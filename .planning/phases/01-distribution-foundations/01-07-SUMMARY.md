---
phase: 01-distribution-foundations
plan: 07
status: deferred
deferred_at: "2026-04-28"
deferral_reason: "User paused before tag push v0.0.1 (SUPublicEDKey freeze gate); no clean test Mac/account available for smoke-test installs"
requirements: [DIST-04, DIST-05, DIST-06, DIST-08]
---

# Plan 01-07 Summary — 0.0.1 → 0.0.2 round-trip smoke test (DEFERRED)

## Status: deferred — Phase 1 execution complete, smoke test pending

Plans 01-01 through 01-06 are complete and committed/pushed to `origin/main`. The full release pipeline is wired and ready to fire on the first `v*.*.*` tag push, but **no tag has been pushed yet**, so:

- ✅ All 6 prior plans verified end-to-end on the dev Mac (build, test, DMG, EdDSA key, secrets, CI workflows)
- ✅ `build.yml` ran green on `main` (run `25024201247`, 1m 17s) — proves the build half of the CI works
- ❌ `release.yml` has not run — no v0.0.1 tag pushed
- ❌ No Sparkle round-trip exercised — no clean test Mac/account currently available
- ⚠️ **SUPublicEDKey is NOT YET FROZEN** — the public key in `Info.plist` is still rotatable until the first v0.0.1 GitHub Release publishes

## Why deferred

User decision (interactive checkpoint, 2026-04-28):

1. **No clean install target available now.** Plan 01-07 Tasks 2, 4, 5 require a clean Mac OR a freshly-created macOS user account with no prior MoleBar or Sparkle Keychain state. The current dev account has Sparkle Keychain entries and populated DerivedData — running the round-trip here would muddy the "this is what a fresh user sees" evidence.
2. **SUPublicEDKey freeze is irreversible post-v0.0.1 ship.** Pausing before the tag push preserves the option to regenerate keys / restart Plan 01-04 if a defect surfaces between now and resumption. Once v0.0.1 is on GitHub Releases, that escape valve closes.
3. **The smoke test is best done in one uninterrupted ~60–90-min window** with the test Mac, Console.app, and the dev Mac all in front of the operator simultaneously.

This is a deferred-with-clean-handoff, NOT a partial failure.

## What's been verified (6/7 plans, evidence already captured)

| Plan | Status | Evidence |
|------|--------|----------|
| 01-01 | ✅ | `01-01-SUMMARY.md` — repo + Pages + push protection live |
| 01-02 | ✅ | `01-02-SUMMARY.md` — `xcodebuild build` + `xcodebuild test` green; smoke launch survived |
| 01-03 | ✅ | `01-03-SUMMARY.md` — `mole-bundle/mole --version` returns "Mole version 1.36.2" |
| 01-04 | ✅ | `01-04-SUMMARY.md` — Keychain entry recoverable, GH secret set, Info.plist matches Keychain |
| 01-05 | ✅ | `01-05-SUMMARY.md` — 6.8 MB DMG hdiutil-verifies, mounts, bundled mole survives round-trip |
| 01-06 | ✅ | `01-06-SUMMARY.md` — actionlint clean, build.yml first run green in 1m 17s |
| **01-07** | **deferred** | this file |

## What remains — exact resume protocol

When the user has a clean Mac (or a freshly-created macOS user account on this machine) AND a ~90-minute uninterrupted window, resume by following plan `01-07-PLAN.md` in order. Re-summarize evidence into this file at completion (don't create a new file). Each task's resume signal must be captured verbatim.

### Pre-flight before resuming

Verify the dev environment is still in a consistent state — these commands must all pass before pushing the v0.0.1 tag:

```bash
cd /Users/romatroskin/Developer/Projects/mole_menu

# 1. Repo is clean and on main
git status                                    # working tree clean
git rev-parse --abbrev-ref HEAD               # main
git push origin main --dry-run                # nothing to push (we're synced)

# 2. SUPublicEDKey hasn't been mutated since plan 01-04
PUBKEY_FROM_PLIST=$(grep -A1 '<key>SUPublicEDKey</key>' MoleBar/Info.plist | tail -1 | sed -E 's|.*<string>(.*)</string>.*|\1|')
echo "Plist pubkey: $PUBKEY_FROM_PLIST"
# expect: ngXkDowRKWzkSnT3/An2xMmhlu8g1/3oVzSPYO8Q/9A=

# 3. Keychain still has the matching private key (recoverability test)
SPARKLE_BIN=$(find ~/Library/Developer/Xcode/DerivedData -path '*/sparkle/Sparkle/bin' -type d | head -n 1)
PUBKEY_FROM_KC=$("$SPARKLE_BIN/generate_keys" -p)
[ "$PUBKEY_FROM_KC" = "$PUBKEY_FROM_PLIST" ] && echo "MATCH" || echo "MISMATCH — STOP, regenerate per Plan 01-04"

# 4. GH secret SPARKLE_EDDSA_PRIVATE_KEY still set
gh secret list --repo romatroskin/molebar | grep '^SPARKLE_EDDSA_PRIVATE_KEY'
# expect a line with a recent-or-original timestamp

# 5. Build still green (sanity, in case of OS / Xcode update since 2026-04-28)
xcodebuild build -project MoleBar.xcodeproj -scheme MoleBar \
  -destination 'platform=macOS,arch=arm64' \
  MARKETING_VERSION=0.0.1 CURRENT_PROJECT_VERSION=1 \
  CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
# expect: BUILD SUCCEEDED

# 6. Build.yml is still happy on main (no regressions during deferral)
gh run list --workflow=build.yml --limit 1 --repo romatroskin/molebar
# expect: completed success
```

If any pre-flight fails, **fix before pushing v0.0.1.** A SUPublicEDKey/Keychain mismatch is a Plan 04 redo — recoverable now, irrecoverable post-v0.0.1.

### Task 1 (when resuming): tag push v0.0.1 — THE FREEZE GATE

```bash
git tag v0.0.1
git push origin v0.0.1
```

Watch the release.yml run via `gh run watch` (or the Actions UI). Typical wall-clock 6–12 min. Per Plan 01-07 Task 1's resume signal, capture all 5 verification command outputs.

### Tasks 2–5 (when resuming): clean-Mac smoke test

Follow plan `01-07-PLAN.md` Tasks 2–5 verbatim. Document the corruption window (Task 5) timestamps so anyone who grabbed the appcast during that ~5-minute window understands what they observed.

### Task 6 (when resuming): OSS-04 secret-leak audit

Three scans (history, CI logs, secret-scanning alerts). All must come back clean.

## Risk profile of the deferral

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| SUPublicEDKey value in `Info.plist` is silently corrupted before v0.0.1 ships | low | medium | Pre-flight Step 2 catches it; the value is in git history at commit `4862028` for restoration |
| Sparkle Keychain entry on dev Mac is wiped (OS reinstall, Keychain reset) before v0.0.1 ships | low | medium | iCloud Keychain backup (D-06) restores it; if iCloud sync is also lost, regenerate via Plan 01-04 (recoverable pre-ship) |
| GitHub repo settings drift (Pages turned off, Push Protection disabled) during deferral | low | low | Pre-flight should add `gh repo view --json visibility,licenseInfo` and Push Protection re-checks |
| GitHub Pages domain redirect (`puffpuff.dev`) lapses during deferral | low | medium | D-12 was rotated to `puffpuff.dev` exactly because `romatroskin.github.io` redirects there; if `puffpuff.dev` lapses, every appcast fetch breaks. Monitor domain renewal. |
| Sparkle 2.9.x SPM artifact path changes when DerivedData is purged | medium | low | `find ~/Library/Developer/Xcode/DerivedData -path '*/sparkle/Sparkle/bin' -type d` finds the new path; `release.yml` already does this dynamically |
| Project sat dormant long enough that some CI action version is yanked | low | low | `actions/checkout@v4`, `peaceiris/actions-gh-pages@v4`, `softprops/action-gh-release@v3` — track GitHub deprecation announcements for Node.js 24 transition (June 2026) |

## What Phase 1 promised vs delivered (so far)

Phase 1's stated goal: a tagged-and-released v0.0.1 that a user can install from a public DMG and update to v0.0.2 via the in-app Sparkle path.

| Deliverable | Status |
|---|---|
| Public open-source repo + LICENSE + README + .gitignore + gh-pages | ✅ |
| Buildable Xcode project with Sparkle wired | ✅ |
| Bundled `tw93/mole` Universal2 tree | ✅ |
| FROZEN-after-release Sparkle keypair (private in Keychain + iCloud + GH; public in Info.plist) | ✅ (frozen-PENDING-ship) |
| Local DMG packaging script | ✅ |
| Tag-push CI release pipeline (release.yml) + PR build verification (build.yml) | ✅ |
| **First v0.0.1 tag pushed and release.yml green** | ❌ deferred |
| **DMG installable on a clean Mac with menu-bar popover working** | ❌ deferred |
| **v0.0.2 tag pushed, Sparkle in-app update from 0.0.1 → 0.0.2 verified end-to-end** | ❌ deferred |
| **Negative test (corrupt appcast → Sparkle refuses) passes** | ❌ deferred |
| **OSS-04 secret-leak audit across release.yml runs** | ❌ deferred (depends on real release.yml runs existing) |

Phase 1 is currently in a **"plumbing complete, live shake-out pending"** state. The deferred tasks have no upstream blockers — they require only operator time + a clean test target.

## Next steps for Phase 2 (independent of 01-07 deferral)

Phase 2 is `MoleClient` actor design + subprocess orchestration. It does NOT depend on v0.0.1 having shipped — it depends only on:

- `Packages/MoleBarPackage/Sources/MoleBarCore/` exists with the empty placeholder (Plan 01-02 ✓)
- `mole-bundle/` recipe is reproducible (Plan 01-03 ✓)
- A9 absolute-path observations from Plan 01-03 are documented (Plan 01-03's SUMMARY ✓)

So **Phase 2 can begin in parallel with Plan 01-07's deferred resumption.** That's the clean factoring of the deferral — it doesn't block downstream work.

## Carry-forward (when 01-07 finally completes)

When the round-trip test passes and OSS-04 audit is clean:

- Replace this file's `status: deferred` frontmatter with `status: complete` and `completed_at: <date>`.
- Append the captured evidence (CI run URLs, appcast.xml snapshots, Console.app exports, three audit-command transcripts) to this file.
- Run `/gsd-verify-work 1` to certify Phase 1 complete.
- Phase 1 retrospective: any first-launch UX papercuts? Any CI flakes? Any Pitfall A9 absolute-path resolution issues that surfaced during install? Carry into Phase 2's RESEARCH.md if they affect `MoleClient` design.
