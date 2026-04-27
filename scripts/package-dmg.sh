#!/usr/bin/env bash
# scripts/package-dmg.sh
# Produce build/dmg/MoleBar-${MARKETING_VERSION}.dmg from a built MoleBar.app
# plus the bundled mole tree (mole-bundle/) staged into Contents/Helpers/.
#
# Inputs (env or default-detected):
#   MARKETING_VERSION  — required; the user-facing version (e.g., 0.0.1).
#   APP_PATH           — optional; defaults to xcodebuild's CONFIGURATION_BUILD_DIR/MoleBar.app.
#   MOLE_BUNDLE_DIR    — optional; defaults to ./mole-bundle (Plan 03's output).
#   DMG_DIR            — optional; defaults to ./build/dmg.
#
# Output:
#   ${DMG_DIR}/MoleBar-${MARKETING_VERSION}.dmg
#
# Source-of-truth: 01-RESEARCH.md §create-dmg Invocation.
# Plan 06's release.yml "Build DMG" step invokes this script unmodified.
# NEVER re-package or re-zip the DMG after Plan 06's sign_update step
# (Pitfall A3 — invalidates the EdDSA signature).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

: "${MARKETING_VERSION:?MARKETING_VERSION must be set (e.g., MARKETING_VERSION=0.0.1)}"
: "${MOLE_BUNDLE_DIR:=${REPO_ROOT}/mole-bundle}"
: "${DMG_DIR:=${REPO_ROOT}/build/dmg}"

# 1. Locate the built MoleBar.app.
if [[ -z "${APP_PATH:-}" ]]; then
  APP_PATH="$(xcodebuild -project MoleBar.xcodeproj -scheme MoleBar -showBuildSettings \
                -destination 'platform=macOS,arch=arm64' 2>/dev/null \
              | awk -F' = ' '/CONFIGURATION_BUILD_DIR/{print $2; exit}' \
              | tr -d ' ')/MoleBar.app"
fi
if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: MoleBar.app not found at $APP_PATH" >&2
  echo "       Build first:" >&2
  echo "         xcodebuild build -project MoleBar.xcodeproj -scheme MoleBar \\" >&2
  echo "           -destination 'platform=macOS,arch=arm64' \\" >&2
  echo "           MARKETING_VERSION=${MARKETING_VERSION} CURRENT_PROJECT_VERSION=1 \\" >&2
  echo "           CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO" >&2
  exit 1
fi

echo "[package-dmg] App: $APP_PATH"
echo "[package-dmg] Marketing version: $MARKETING_VERSION"
echo "[package-dmg] Mole bundle source: $MOLE_BUNDLE_DIR"

# 2. Stage a clean copy of MoleBar.app at build/export/ (so we don't pollute the build dir).
#    SAFETY: only rm -rf EXPORT_DIR if APP_PATH is OUTSIDE it. Otherwise we'd delete our own input.
EXPORT_DIR="${REPO_ROOT}/build/export"
APP_REAL=$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")
EXPORT_REAL=$(cd "$(dirname "$EXPORT_DIR")" 2>/dev/null && pwd)/$(basename "$EXPORT_DIR") || EXPORT_REAL="$EXPORT_DIR"
case "$APP_REAL" in
  "$EXPORT_REAL"/*)
    echo "[package-dmg] APP_PATH is already inside EXPORT_DIR — using in-place (no destructive copy)."
    ;;
  *)
    rm -rf "$EXPORT_DIR"
    mkdir -p "$EXPORT_DIR"
    cp -R "$APP_PATH" "$EXPORT_DIR/MoleBar.app"
    ;;
esac

# 3. Inject the bundled Mole tree into Contents/Helpers/mole/ (a SUBDIRECTORY).
#    Per CONTEXT.md D-14 amended: Helpers/mole/ is the directory; Helpers/mole/mole is the wrapper script (entry point).
#    SAFETY: skip if Helpers/mole/ is already populated (idempotent for caller-pre-staged inputs).
if [[ ! -d "$MOLE_BUNDLE_DIR" ]]; then
  echo "ERROR: $MOLE_BUNDLE_DIR not found. Run scripts/bundle-mole.sh first." >&2
  exit 1
fi
HELPERS_DIR="$EXPORT_DIR/MoleBar.app/Contents/Helpers"
MOLE_DEST="$HELPERS_DIR/mole"
if [[ -x "$MOLE_DEST/mole" ]]; then
  echo "[package-dmg] $MOLE_DEST already populated — skipping mole-bundle re-injection."
else
  mkdir -p "$HELPERS_DIR"
  rm -rf "$MOLE_DEST"
  cp -R "$MOLE_BUNDLE_DIR" "$MOLE_DEST"
fi
# Confirm the bundled mole survived the copy. Wrapper is at Contents/Helpers/mole/mole.
if ! "$MOLE_DEST/mole" --version >/dev/null 2>&1; then
  echo "ERROR: $MOLE_DEST/mole --version failed after staging." >&2
  echo "       Bundle was copied but is not invokable inside the .app layout." >&2
  exit 1
fi
echo "[package-dmg] Bundled mole staged + smoke-tested OK"

# 4. Run create-dmg.
if ! command -v create-dmg >/dev/null 2>&1; then
  echo "ERROR: create-dmg not on PATH. Install via 'brew install create-dmg'." >&2
  exit 1
fi

mkdir -p "$DMG_DIR"
DMG_OUT="${DMG_DIR}/MoleBar-${MARKETING_VERSION}.dmg"
rm -f "$DMG_OUT"

if [[ -f "${REPO_ROOT}/dmg-assets/background.png" ]]; then
  echo "[package-dmg] Using dmg-assets/background.png (with-background layout)"
  create-dmg \
    --volname "MoleBar ${MARKETING_VERSION}" \
    --background "${REPO_ROOT}/dmg-assets/background.png" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 128 \
    --icon "MoleBar.app" 165 200 \
    --hide-extension "MoleBar.app" \
    --app-drop-link 495 200 \
    --no-internet-enable \
    "$DMG_OUT" \
    "$EXPORT_DIR/"
else
  echo "[package-dmg] dmg-assets/background.png absent — using D-16 fallback layout"
  create-dmg \
    --volname "MoleBar ${MARKETING_VERSION}" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 128 \
    --icon "MoleBar.app" 175 200 \
    --hide-extension "MoleBar.app" \
    --app-drop-link 425 200 \
    --no-internet-enable \
    "$DMG_OUT" \
    "$EXPORT_DIR/"
fi

if [[ ! -f "$DMG_OUT" ]]; then
  echo "ERROR: create-dmg did not produce $DMG_OUT" >&2
  exit 1
fi

SIZE_BYTES=$(stat -f%z "$DMG_OUT")
echo "[package-dmg] DONE. ${DMG_OUT} (${SIZE_BYTES} bytes)"
echo "[package-dmg] Verify mountability:"
echo "                hdiutil verify ${DMG_OUT}"
echo "                open ${DMG_OUT}"
