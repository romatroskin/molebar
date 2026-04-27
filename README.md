# MoleBar

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue.svg)](https://www.apple.com/macos/)
[![Build](https://github.com/romatroskin/molebar/actions/workflows/build.yml/badge.svg)](https://github.com/romatroskin/molebar/actions/workflows/build.yml)

A menu bar interface for [`tw93/mole`](https://github.com/tw93/mole) — deep-clean, optimize, and analyze your Mac without opening a terminal.

> **Status:** v0.0.1 is a distribution-pipeline smoke test. Real features land in v0.1+.

## Highlights

- **Menu bar first.** Live system stats + one-click cleaning, all from the menu bar.
- **Mole's safety model.** Dry-run-first by default; Trash, not `rm -rf`.
- **Native Swift.** macOS 14+, no Electron.
- **Zero telemetry.** The Sparkle update check is the only outbound network call.
- **Open source, MIT.** Same license as upstream Mole.

## Install

> Phase 1 ships UNSIGNED. The first signed/notarized build (Phase 1.5) will be the recommended install. For now:

1. Download `MoleBar-<version>.dmg` from the [latest GitHub Release](https://github.com/romatroskin/molebar/releases/latest).
2. Open the DMG, drag `MoleBar.app` to `/Applications`.
3. The first launch will show "MoleBar.app is from an unidentified developer" because the Phase 1 build is unsigned. Right-click `MoleBar.app` in Finder → **Open** → **Open Anyway** in System Settings → Privacy & Security. (Signed builds in v0.1+ remove this step.)
4. The MoleBar icon appears in the menu bar.

Homebrew Cask install (`brew install --cask molebar`) lands in v0.1.

## Build from source

Requirements: macOS 14+, Xcode 16.4+, Homebrew (for `create-dmg`).

```bash
git clone https://github.com/romatroskin/molebar.git
cd molebar
brew install create-dmg
open MoleBar.xcodeproj
# Cmd+R to run from Xcode
```

To build a release DMG locally (without signing):

```bash
./scripts/bundle-mole.sh   # downloads + lipos the bundled tw93/mole tree
./scripts/package-dmg.sh   # builds the .dmg via create-dmg
```

## Architecture

MoleBar is a thin SwiftUI app target over a local SwiftPM package (`Packages/MoleBarPackage/`) with three modules:

- `MoleBarCore` — UI-agnostic subprocess orchestration, models, resolver. Filled in Phase 2.
- `MoleBarStores` — `@Observable @MainActor` view-models. Filled in Phase 3+.
- `MoleBarUI` — SwiftUI views. Filled in Phase 3+.

The bundled Mole tree (Shell wrappers + per-arch Go helpers, lipo'd Universal2) lives at `MoleBar.app/Contents/Helpers/`. The runtime resolver prefers a user copy at `~/Library/Application Support/MoleBar/bin/mole` if present (Phase 8 ships the user-copy auto-updater). The bundle ID is `app.molebar.MoleBar` (FROZEN — see `Info.plist`). The Sparkle appcast feed is `https://puffpuff.dev/molebar/appcast.xml` (FROZEN — see `Info.plist`'s `SUFeedURL`).

## Contributing

Pull requests welcome.

- Run swift-format (Xcode 16+ built-in: Editor → Structure → Format File) before committing.
- **No telemetry / analytics PRs accepted.** MoleBar makes exactly one outbound network call: Sparkle's appcast check. Anything else is a hard reject.
- Mole's safety model (dry-run-first, Trash-not-`rm`, explicit confirmation) is non-negotiable.
- Run `xcodebuild build -project MoleBar.xcodeproj -scheme MoleBar -destination 'platform=macOS,arch=arm64'` and confirm green before pushing.

## License

MIT — see [LICENSE](LICENSE).

Bundles [`tw93/mole`](https://github.com/tw93/mole), MIT-licensed (attribution file `LICENSE-MOLE.txt` lands in v0.1, per Phase 2's `CORE-08`).

## Acknowledgments

MoleBar wraps [`tw93/mole`](https://github.com/tw93/mole) by tw93 and contributors. All deep-clean, optimize, and analyze logic comes from Mole; MoleBar is just the UI.
