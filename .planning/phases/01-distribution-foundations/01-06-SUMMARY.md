---
phase: 01-distribution-foundations
plan: 06
status: complete
completed_at: "2026-04-28"
requirements: [DIST-05, DIST-06, DIST-08, OSS-04]
---

# Plan 01-06 Summary — CI workflows (release + build)

## What was built

Two GitHub Actions workflow files implementing the Phase 1 release pipeline (DIST-05 / DIST-06 / DIST-08) and the PR-time build verification (DIST-05 verify):

- **`.github/workflows/build.yml`** — runs on every `push` to `main` and every `pull_request` to `main`. macos-15 runner + Xcode 16.4. Steps: checkout → SPM resolve → `xcodebuild build` (Debug, arm64, unsigned) → `xcodebuild test` (vacuous in Phase 1, populated in Phase 2). `concurrency.cancel-in-progress: true` so superseded PR builds free runner capacity.

- **`.github/workflows/release.yml`** — triggers ONLY on `push` of `v*.*.*` tags. Full scaffolded-but-skipped pipeline per D-18:
  1. Checkout (with full history)
  2. Compute versions from the tag (`MARKETING_VERSION = ${TAG#v}`, `CURRENT_PROJECT_VERSION = run number`)
  3. Select Xcode 16.4
  4. Install create-dmg
  5. Resolve Sparkle SPM artifacts
  6. **Bundle tw93/mole** via `bash scripts/bundle-mole.sh` (parity with local from plan 01-03)
  7. Build & archive (unsigned in Phase 1, hardened-runtime later)
  8. Stage `.app` + Mole bundle into `build/staged/MoleBar.app/Contents/Helpers/mole/` and smoke-test `mole --version`
  9. **STUB**: Import Developer ID certificate (skipped while `MACOS_CERT` is empty)
  10. **STUB**: Sign Go helpers + .app inside-out (skipped while `MACOS_CERT_NAME` is empty)
  11. Build DMG via `bash scripts/package-dmg.sh` (parity with local from plan 01-05)
  12. **STUB**: Notarize via `notarytool submit --wait` + `stapler staple` (skipped while `ASC_API_KEY_P8` is empty)
  13. **Sparkle EdDSA sign** the DMG (LAST mutation of the DMG, Pitfall A3) — fails loudly if `SPARKLE_EDDSA_PRIVATE_KEY` is empty (Plan 04 enforces it pre-tag-push)
  14. Render `appcast.xml` from a heredoc template using the `sign_update` whole-line capture (per Pitfall A2 robustness)
  15. Upload DMG to GitHub Release via `softprops/action-gh-release@v3`
  16. Publish `appcast.xml` to `gh-pages` via `peaceiris/actions-gh-pages@v4` with `keep_files: true` (Pitfall A6 — preserves index.html from Plan 01)
  17. **STUB**: Bump Homebrew Cask (skipped while `HOMEBREW_GITHUB_TOKEN` is empty)

`concurrency.cancel-in-progress: false` for release.yml — never kill a release mid-flight.

## Stub-skip pattern — job-level env indirection

The plan-prescribed pattern was `if: ${{ secrets.X != '' }}` at step level. actionlint 1.7.12 reports `secrets` is not in the allowed contexts for step `if:` (per GitHub's documented context-availability table). Although the syntax works at runtime, the plan's verify gate requires `actionlint` exit 0.

Resolution: hoist secret-presence evaluations to job-level `env:` (where `secrets` IS available), then check the env flag in step `if:`:

```yaml
jobs:
  release:
    env:
      HAS_MACOS_CERT: ${{ secrets.MACOS_CERT != '' }}
      HAS_MACOS_CERT_NAME: ${{ secrets.MACOS_CERT_NAME != '' }}
      HAS_ASC_API_KEY_P8: ${{ secrets.ASC_API_KEY_P8 != '' }}
      HAS_HOMEBREW_GITHUB_TOKEN: ${{ secrets.HOMEBREW_GITHUB_TOKEN != '' }}
    steps:
      - name: Import Developer ID certificate (STUB)
        if: env.HAS_MACOS_CERT == 'true'
```

Functional behavior is identical: a step skips when the underlying secret is empty, runs when populated. Phase 1.5 just fills secrets in the GitHub UI; the `HAS_*` flags flip to `'true'` automatically. No workflow YAML edits required.

## OSS-04 secret-hygiene patterns

| Pattern | Count in release.yml |
|---|---|
| `echo "::add-mask::$SECRET"` | 4 (MACOS_CERT_PWD, MACOS_CI_KEYCHAIN_PWD, ASC_API_KEY_P8, SPARKLE_EDDSA_PRIVATE_KEY) |
| `umask 077` for tempfile creation | 2 (ASC_API_KEY_P8, SPARKLE_EDDSA_PRIVATE_KEY) |
| `shred -uvz` after key use | 2 (ASC_API_KEY_P8, SPARKLE_EDDSA_PRIVATE_KEY) |
| `set -x` (forbidden) | 0 |
| `pull_request_target` (forbidden) | 0 (build.yml uses `pull_request` only; release.yml has no PR triggers) |

## actionlint verification

```
$ actionlint --version
1.7.12
$ actionlint .github/workflows/build.yml .github/workflows/release.yml
$ echo $?
0
```

Zero errors, zero warnings.

## First end-to-end build.yml run

Triggered by this plan's commit to `main`:

| Field | Value |
|---|---|
| Workflow | Build |
| Run ID | `25024201247` |
| URL | https://github.com/romatroskin/molebar/actions/runs/25024201247 |
| Trigger | push to main |
| Commit | `239de81` (`ci(01-06): scaffold release.yml + build.yml ...`) |
| Outcome | ✅ **success** |
| Wall-clock | 1m 17s (Set up job + Checkout + Xcode select + SPM resolve + Build + Test + Post Checkout) |

All 5 work steps green:
- Checkout
- Select Xcode 16.4
- Resolve SwiftPM dependencies
- Build (arm64, unsigned)
- Test (vacuous in Phase 1)

## release.yml runs

Zero — confirmed via `gh run list --workflow=release.yml --limit 3 --repo romatroskin/molebar`. release.yml fires only on `v*.*.*` tag push; that's plan 01-07's responsibility.

## Annotations / warnings (informational)

GitHub Actions runner annotated:

> Node.js 20 actions are deprecated. The following actions are running on Node.js 20 and may not work as expected: `actions/checkout@v4`. Actions will be forced to run with Node.js 24 by default starting June 2nd, 2026.

Carry-forward: schedule a v0.1+ workflow refresh to bump action versions or set `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true`. Not blocking for Phase 1.

## Deviations from the plan

### Deviation 1 — Stub-skip pattern: `if: secrets.X != ''` → job-env-flag indirection

**What:** Plan task 2 prescribed `if: ${{ secrets.X != '' }}` at step level. actionlint 1.7.12 errors on this (`context "secrets" is not allowed here`). The plan's text says "document and proceed", but its verify gate (`[ $ACTIONLINT_RC -eq 0 ]`) requires zero actionlint errors.

**Resolution:** Refactored to job-level `env:` with `HAS_*` boolean flags evaluated from secrets, then step `if:` checks `env.HAS_*`. Functional behavior unchanged. Documented in the workflow file's job-env comment block.

**Why this is fine:** Phase 1.5's intent is "fill in 8 secrets, no workflow edits needed". The HAS_* flags flip automatically when a secret becomes non-empty — same auditability as the original pattern.

### Deviation 2 — SC2129 style fix in `Compute versions` step

**What:** Original prescribed code wrote three lines to `$GITHUB_OUTPUT` via separate `>>` redirects. shellcheck SC2129 flags this as style.

**Resolution:** Wrapped in a `{ ... } >> "$GITHUB_OUTPUT"` block. Trivial, no behavior change.

## Outputs / artifacts

| Path | Notes |
|------|-------|
| `.github/workflows/build.yml` | 49 lines, 9 named steps, runs on every PR + main push |
| `.github/workflows/release.yml` | 295 lines, 17 steps (3 active stubs + 14 always-run), runs on `v*.*.*` tag push only |

## Carry-forward

- **Plan 01-07** (smoke test): pushes the `v0.0.1` and `v0.0.2` tags that fire `release.yml`. Will be the first end-to-end CI exercise of the entire pipeline (mole bundle → archive → DMG → Sparkle EdDSA sign → GitHub Release upload → gh-pages appcast publish → user-side update from 0.0.1 to 0.0.2).
- **Phase 1.5** (Sign & Ship for Real): fill in `MACOS_CERT`, `MACOS_CERT_PWD`, `MACOS_CERT_NAME`, `MACOS_CI_KEYCHAIN_PWD`, `ASC_API_KEY_ID`, `ASC_ISSUER_ID`, `ASC_API_KEY_P8`, `HOMEBREW_GITHUB_TOKEN` via `gh secret set`. The `HAS_*` env flags flip from `'false'` to `'true'`, the previously-skipped stub steps activate. Diff is "8 secret values" + zero workflow file edits.
- **v0.1+** (workflow refresh): bump `actions/checkout@v4` once a Node.js 24-compatible version exists; revisit `peaceiris/actions-gh-pages@v4` and `softprops/action-gh-release@v3` for the same.
- **Phase 8** (CLI auto-updater): the appcast at `https://puffpuff.dev/molebar/appcast.xml` is for MoleBar app updates only. The bundled-mole-tree updater is a separate runtime mechanism (custom downloader + ad-hoc resigning). Both feed off the same SUPublicEDKey trust anchor from plan 01-04.
