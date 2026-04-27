---
phase: 01-distribution-foundations
plan: 05
status: complete
completed_at: "2026-04-28"
requirements: [DIST-04]
---

# Plan 01-05 Summary — DMG packaging script + placeholder background

## What was built

- **`dmg-assets/background.png`** — 1353-byte placeholder PNG, exactly **660 × 400** pixels, dark-grey (RGB 0x222222) solid color. Generated via stdlib Python (`struct` + `zlib`), no Pillow / Homebrew deps. v0.1+ replaces with a designed background.
- **`dmg-assets/.gitkeep`** — explains the placeholder rationale + the fallback testing protocol.
- **`scripts/package-dmg.sh`** (mode 0755) — local + CI-invoked DMG packaging recipe. Two code paths per CONTEXT.md D-16:
  - **With background** (when `dmg-assets/background.png` exists): `--window-size 660 400`, `--app-drop-link 495 200`, `--icon "MoleBar.app" 165 200`.
  - **Fallback** (no background.png): `--window-size 600 400`, `--app-drop-link 425 200`, `--icon "MoleBar.app" 175 200`.
- The script stages `mole-bundle/` into `MoleBar.app/Contents/Helpers/mole/` (D-14 amended subdir layout) and smoke-tests `mole --version` from the staged path before invoking `create-dmg`. Plan 06's `release.yml` invokes this script unmodified.

## End-to-end results

| Step | Outcome |
|------|---------|
| `brew install create-dmg` | ✅ stable 1.2.3 (bottled) |
| Pre-existing `mole-bundle/` from plan 01-03 | ✅ reused (16 MB tree) |
| `xcodebuild build` (Debug, arm64, unsigned) | ✅ `BUILD SUCCEEDED` |
| `MARKETING_VERSION=0.0.1 ./scripts/package-dmg.sh` (with-background) | ✅ produced `build/dmg/MoleBar-0.0.1.dmg` |
| `file build/dmg/MoleBar-0.0.1.dmg` | `zlib compressed data` (Apple DMG) |
| `hdiutil verify build/dmg/MoleBar-0.0.1.dmg` | `checksum … is VALID` |
| Mount via `hdiutil attach` | mounted at `/Volumes/MoleBar 0.0.1` |
| Top-level mount contents | `MoleBar.app`, `Applications` symlink |
| `Contents/Helpers/mole/mole` post-mount | executable ✅ |
| `Contents/Helpers/mole/bin/analyze-go` post-mount | executable + Universal2 ✅ |
| `Contents/Helpers/mole/bin/status-go` post-mount | executable ✅ |
| `git check-ignore build/dmg/MoleBar-0.0.1.dmg` | ✅ ignored |
| **Optional fallback codepath** (background.png moved aside) | ✅ produced verified DMG with `D-16 fallback layout` log line; restored after test |

## Final DMG metadata

- **Path:** `build/dmg/MoleBar-0.0.1.dmg` (gitignored)
- **Size:** **7,130,471 bytes (≈ 6.8 MB)** — comfortably under any GitHub Release size limit and Sparkle download UX threshold (T-01-05-05 mitigation)
- **Sectors:** 90,188 → 40,180 compressed (84.6% savings)
- **Volume name:** `MoleBar 0.0.1`
- **Layout:** with-background (660 × 400 window, MoleBar.app at 165,200, /Applications drop-link at 495,200)

## Tooling versions

| Tool | Version |
|------|---------|
| `create-dmg` (shell, Homebrew) | 1.2.3 (bottled) |
| `hdiutil` | bundled with macOS 26.3.1 |
| `sips` | bundled with macOS |
| Python (placeholder PNG generator) | python3 stdlib (`struct`, `zlib`) |

## Notes on visual oddities (informs v0.1 designed background)

The placeholder background is a flat dark-grey rectangle. Visual concerns when v0.1 supplies a real background:

- **Drop-link target** sits at (495, 200) — visually "right of center" in a 660-wide window. The designed background should place a visual cue (arrow, "drag me here" hint) anchored at this coordinate.
- **MoleBar.app icon** sits at (165, 200) — visually "left of center". Designed background should leave whitespace around this region for the app icon (currently empty AppIcon.appiconset, so the app shows the generic blank document icon — Phase 1.5 / v0.1 supplies real icons).
- **No volume-icon customization** in Phase 1 (`--icon` not used for the volume icon itself). Optional v0.1 enhancement.
- **No EULA, no internet-enable** (we explicitly pass `--no-internet-enable`). Per CONTEXT.md — MoleBar's only outbound network call is the Sparkle appcast check.

## Deviations from the plan

None functional. The plan-prescribed flow (Task 1 → Task 2 → Task 3 → optional fallback test) ran end-to-end on the dev Mac without modification.

## Outputs / artifacts

| Path | Notes |
|------|-------|
| `dmg-assets/background.png` | 1353 bytes; 660×400; placeholder. Committed. |
| `dmg-assets/.gitkeep` | placeholder rationale + fallback-testing protocol. Committed. |
| `scripts/package-dmg.sh` | 4.2 KB; mode 0755; Plan 06 invokes unmodified. Committed. |
| `build/dmg/MoleBar-0.0.1.dmg` | 6.8 MB; runtime artifact (gitignored). |
| `build/export/MoleBar.app` | runtime staging (gitignored). |

## Carry-forward

- **Plan 06** (release CI): `release.yml` "Build DMG" step is `MARKETING_VERSION="${{ github.ref_name#v }}" bash scripts/package-dmg.sh`. The script handles `mole-bundle/` staging and `Contents/Helpers/mole/` injection — release.yml just calls bundle-mole.sh first, then this.
- **Plan 06 (Pitfall A3)**: `sign_update` MUST run AFTER `package-dmg.sh` and AFTER any signing/notarization. Never re-zip / re-package post sign_update. Implementation lives in plan 01-06.
- **Phase 1.5** (Sign & Ship for Real): Add `codesign --force --options runtime --timestamp --sign "Developer ID Application: …"` BEFORE the create-dmg step (sign the .app first, inside-out per Quinn "The Eskimo!"). Then `notarytool submit --wait` on the signed DMG, then `stapler staple`. Then `sign_update`.
- **v0.1+**: Replace `dmg-assets/background.png` with a designed background. Coordinates are FROZEN by D-16 unless the layout is also redesigned in concert.
- **Phase 8** (CLI auto-updater): When a user-side mole-bundle update lands at `~/Library/Application Support/MoleBar/cli/`, the runtime resolver picks it up — no DMG repackage needed. So `package-dmg.sh` never participates in CLI updates, only MoleBar app updates.
