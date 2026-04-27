---
phase: 01-distribution-foundations
plan: 04
status: complete
completed_at: "2026-04-28"
requirements: [DIST-06, OSS-04]
---

# Plan 01-04 Summary — Sparkle EdDSA keypair (FROZEN-after-first-release)

## ⚠ Frozen-after-first-release acknowledgment

**`SUPublicEDKey = ngXkDowRKWzkSnT3/An2xMmhlu8g1/3oVzSPYO8Q/9A=` is now FROZEN.** Plan 06 will publish v0.0.1 — after that, this key cannot be rotated without orphaning every existing user (Pitfall A2 + D-08). The matching ed25519 private key lives in three places:

| Location | Purpose |
|---|---|
| Dev Mac login Keychain | Canonical store; `generate_keys -p` and `generate_keys -x` access it |
| iCloud Keychain | D-06 backup; auto-syncs from login Keychain (sync confirmed ON) |
| GitHub Actions secret `SPARKLE_EDDSA_PRIVATE_KEY` | Plan 06's `release.yml` materializes via `gh secret`, signs DMG, shreds tempfile |

If the private key is leaked or lost AFTER v0.0.1 ships, the only recovery is a project restart with users reinstalling. PRE-v0.0.1 (now), regeneration is recoverable — just re-run plan 01-04.

## What was built

- **Keypair generated** on the dev Mac via Sparkle 2.9.1's `generate_keys` (the SPM artifact populated by plan 01-02 task 4). Stored in the user's login Keychain under Sparkle's standard label. Recoverability test (`generate_keys -x`) succeeded, then re-test succeeded again post-upload — proves Keychain ACL allows export, the failure mode flagged in Pitfall A2 is not present.
- **Public key embedded in `MoleBar/Info.plist`** at the `<key>SUPublicEDKey</key>` slot. The plan-02 placeholder `PLACEHOLDER_SUPUBLICEDKEY_REPLACE_IN_PLAN_04` no longer appears anywhere in the file. `plutil -lint` reports OK; `xcodebuild build` exits 0; the built MoleBar.app's `defaults read … SUPublicEDKey` confirms the real value is injected.
- **Private key uploaded** to `gh secret set SPARKLE_EDDSA_PRIVATE_KEY --repo romatroskin/molebar` from a `umask 077` tempfile, then `shred`ed. No /tmp residue.
- **Eight Phase-1.5 placeholder secrets pre-created** so Plan 06's `if: ${{ secrets.X != '' }}` guards evaluate cleanly without "unknown secret" errors.

## Verification

| Check | Result |
|-------|--------|
| `grep -c 'PLACEHOLDER_SUPUBLICEDKEY_REPLACE_IN_PLAN_04' MoleBar/Info.plist` | `0` |
| `plutil -lint MoleBar/Info.plist` | `OK` |
| `<string>…</string>` after `<key>SUPublicEDKey</key>` matches `^[A-Za-z0-9+/]{43}=$` | ✅ |
| `xcodebuild build` (Debug, arm64, unsigned) | `BUILD SUCCEEDED` |
| Built app's `SUPublicEDKey` (via `defaults read`) | `ngXkDowRKWzkSnT3/An2xMmhlu8g1/3oVzSPYO8Q/9A=` |
| `test -f /tmp/sparkle.key` | absent (shredded) |
| Keychain re-export (recoverability) | succeeds → file size > 0 → shredded |
| Keychain pubkey ↔ Info.plist pubkey | **MATCH** |
| `git log --all -p -- ':(exclude).planning/' \| grep PRIVATE KEY` | empty (no private-key material outside planning docs) |

## GitHub Actions secrets — `gh secret list --repo romatroskin/molebar`

| Secret | Status | Purpose |
|---|---|---|
| `SPARKLE_EDDSA_PRIVATE_KEY` | populated (about 2 min ago at completion) | Plan 06 release.yml's `sign_update --ed-key-file` consumes this |
| `ASC_API_KEY_ID` | empty placeholder | Phase 1.5 (Apple Store Connect API auth for notarization) |
| `ASC_API_KEY_P8` | empty placeholder | Phase 1.5 (`.p8` key file content) |
| `ASC_ISSUER_ID` | empty placeholder | Phase 1.5 (ASC team issuer ID) |
| `MACOS_CERT` | empty placeholder | Phase 1.5 (Developer ID Application cert, base64) |
| `MACOS_CERT_PWD` | empty placeholder | Phase 1.5 (cert export password) |
| `MACOS_CERT_NAME` | empty placeholder | Phase 1.5 (signing identity CN) |
| `MACOS_CI_KEYCHAIN_PWD` | empty placeholder | Phase 1.5 (CI keychain unlock pass) |
| `HOMEBREW_GITHUB_TOKEN` | empty placeholder | Phase 1.5 (Cask bump PR auth) |

All 9 secrets surfaced in `gh secret list` with "less than a minute ago" / "about 2 minutes ago" timestamps. Phase 1.5's diff against this state will be "fill in 8 secrets" — no changes to `release.yml` required.

## D-06 backup status

iCloud Keychain sync confirmed ON. The Sparkle private-key entry will sync to all Apple-ID-linked devices and survive an Apple ID account-recovery flow. T-01-04-04 acceptance applies (Apple ID compromise compromises the EdDSA key — accepted with hardware-key + strong-password mitigations on the Apple ID).

## Deviations from the plan

None. Every step of all three tasks completed as prescribed:

- Task 1: keypair generated, recoverability tested (export → shred), pubkey transmitted to Claude.
- Task 2: shape-validated (44 chars base64 ending `=`), Edit-tool replacement (not sed), `plutil -lint` OK, build green, built-app pubkey matches.
- Task 3: `umask 077` export → `gh secret set < /tmp/sparkle.key` → shred → all 8 placeholder secrets pre-created → `gh secret list` lists 9 secrets.

## Outputs / artifacts

| Where | Content |
|---|---|
| `MoleBar/Info.plist` (committed `4862028`) | `<key>SUPublicEDKey</key><string>ngXkDowRKWzkSnT3/An2xMmhlu8g1/3oVzSPYO8Q/9A=</string>` |
| Dev Mac login Keychain | ed25519 keypair under Sparkle's standard label |
| iCloud Keychain | mirror of above (D-06 backup) |
| `gh secret` `SPARKLE_EDDSA_PRIVATE_KEY` on `github.com/romatroskin/molebar` | populated, encrypted at rest |
| `gh secret` × 8 (Phase-1.5 placeholders) | empty, present |

## Carry-forward

- **Plan 06** (release CI): `release.yml`'s sign-update step materializes `SPARKLE_EDDSA_PRIVATE_KEY` via `umask 077` → `cat <<<"$SECRET" > $RUNNER_TEMP/sparkle.key` → `sign_update --ed-key-file $RUNNER_TEMP/sparkle.key` → `shred`. Implementation is in plan 01-06.
- **Plan 06** must NOT use `set -x` and must `echo "::add-mask::$SPARKLE_EDDSA_PRIVATE_KEY"` immediately after the env var is populated (T-01-04-06 mitigation).
- **Phase 1.5** (Sign & Ship for Real): fill in the 8 Apple-related secrets. No `release.yml` edits required — D-18's "scaffolded but skipped" pattern means the workflow already references all 9 secret names.
- **Phase 8** (CLI auto-updater): re-uses this same SUPublicEDKey to verify the bundled-mole binary signature on user-side updates. The verification path differs (it's our own SHA-256 allowlist + signature scheme, not Sparkle's), but the trust anchor is identical.
- **CRITICAL — Plan 06 prerequisite gate**: do not push the `v0.0.1` tag (which triggers `release.yml`) until plan 01-06 lands AND the smoke-test plan 01-07 has demonstrated end-to-end EdDSA verification works. Once `v0.0.1` is published from the GitHub Releases page, the SUPublicEDKey freezes.
