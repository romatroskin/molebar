#!/usr/bin/env bash
# scripts/bundle-mole.sh
# Produce a staged bundle of the upstream tw93/mole tree at a pinned version.
# Output: ./mole-bundle/{mole,mo,lib/,cmd/,scripts/,bin/{analyze-go,status-go}}
# The Shell wrappers are copied verbatim from a `git clone --branch <tag>`.
# The two Go helpers (analyze-go, status-go) are produced by `lipo -create`
# of the per-arch upstream release artifacts (arm64 + amd64).
#
# Usage:
#   scripts/bundle-mole.sh                # uses ./mole-version.txt
#   MOLE_VERSION=V1.36.2 scripts/bundle-mole.sh
#
# Source-of-truth: 01-RESEARCH.md §Pitfall A1 + §Mole Binary Bundling Recipe.
# Why this script exists (vs. inlining in release.yml): the developer must
# be able to run the same recipe locally before pushing a tag, so failures
# surface on the dev Mac, not in CI. Plan 06's release.yml invokes this
# script unmodified.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

: "${MOLE_VERSION:=$(cat mole-version.txt)}"
if [[ -z "$MOLE_VERSION" ]]; then
  echo "ERROR: MOLE_VERSION is empty (mole-version.txt missing or empty)." >&2
  exit 1
fi

OUT_DIR="${OUT_DIR:-${REPO_ROOT}/mole-bundle}"
TMP="$(mktemp -d -t bundle-mole.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

echo "[bundle-mole] Pinned tw93/mole version: ${MOLE_VERSION}"
echo "[bundle-mole] Workspace: ${TMP}"
echo "[bundle-mole] Output:    ${OUT_DIR}"

# 1. Download per-arch Go helpers from upstream release page.
BASE_URL="https://github.com/tw93/mole/releases/download/${MOLE_VERSION}"
for binary in analyze status; do
  for arch in arm64 amd64; do
    target="${TMP}/${binary}-darwin-${arch}"
    echo "[bundle-mole] Downloading ${binary}-darwin-${arch}"
    curl -fsSL --retry 3 --retry-delay 2 -o "$target" \
      "${BASE_URL}/${binary}-darwin-${arch}"
    # Sanity: each download should be a Mach-O for the named arch.
    if ! file "$target" | grep -qE 'Mach-O'; then
      echo "ERROR: ${target} is not a Mach-O. Upstream artifact may have drifted." >&2
      file "$target" >&2
      exit 1
    fi
  done
done

# 2. Clone the upstream tree at the pinned tag (for Shell wrappers + lib/ + cmd/ + scripts/).
SRC="${TMP}/mole-src"
echo "[bundle-mole] Cloning tw93/mole at ${MOLE_VERSION}"
git clone --depth 1 --branch "${MOLE_VERSION}" \
  https://github.com/tw93/mole.git "${SRC}"

# 3. Stage the bundle.
rm -rf "$OUT_DIR"
mkdir -p "${OUT_DIR}/bin"

# The Shell wrappers and module trees are copied verbatim. NEVER `lipo` these — they are text.
cp "${SRC}/mole" "${OUT_DIR}/mole"
cp "${SRC}/mo"   "${OUT_DIR}/mo"
cp -R "${SRC}/lib"     "${OUT_DIR}/lib"
cp -R "${SRC}/cmd"     "${OUT_DIR}/cmd"
cp -R "${SRC}/scripts" "${OUT_DIR}/scripts"

# 4. Universal2 the Go helpers via lipo. NOT applied to mole/mo (Shell scripts).
echo "[bundle-mole] lipo -create analyze-go (arm64+amd64 -> Universal2)"
lipo -create \
  "${TMP}/analyze-darwin-arm64" "${TMP}/analyze-darwin-amd64" \
  -output "${OUT_DIR}/bin/analyze-go"

echo "[bundle-mole] lipo -create status-go (arm64+amd64 -> Universal2)"
lipo -create \
  "${TMP}/status-darwin-arm64" "${TMP}/status-darwin-amd64" \
  -output "${OUT_DIR}/bin/status-go"

# 5. Make Shell wrappers + Go helpers executable.
chmod 755 "${OUT_DIR}/mole" "${OUT_DIR}/mo" \
          "${OUT_DIR}/bin/analyze-go" "${OUT_DIR}/bin/status-go"

# 6. Verify Universal2 worked (Pitfall A7).
for helper in "${OUT_DIR}/bin/analyze-go" "${OUT_DIR}/bin/status-go"; do
  if ! file "$helper" | grep -q 'Mach-O universal binary'; then
    echo "ERROR: ${helper} is not a Mach-O universal binary after lipo." >&2
    file "$helper" >&2
    exit 1
  fi
  archs="$(lipo -archs "$helper")"
  if ! grep -q 'arm64' <<<"$archs" || ! grep -q 'x86_64' <<<"$archs"; then
    echo "ERROR: ${helper} missing arm64 or x86_64 (lipo -archs: ${archs})" >&2
    exit 1
  fi
done

# 7. Verify A9 — the Shell wrapper resolves bin/* relative to its own location.
#    The script must succeed regardless of where it's invoked from.
#    If `mole` references $HOME/.config/mole or any absolute path that wouldn't
#    exist inside an .app bundle's Contents/Helpers, surface a warning here.
if grep -nE '(\$HOME/\.config/mole|/usr/local/share/mole|~/.config/mole)' \
     "${OUT_DIR}/mole" "${OUT_DIR}/mo" 2>/dev/null | grep -v '^[^:]*:[[:space:]]*#'; then
  echo "[bundle-mole] WARN: mole/mo wrapper references absolute paths that may not resolve" >&2
  echo "                    inside MoleBar.app/Contents/Helpers/. Inspect the lines above." >&2
  echo "                    Phase 1 acceptance: mole-bundle/mole --version still works because" >&2
  echo "                    --version doesn't need those paths. Phase 2's MoleClient may need" >&2
  echo "                    additional environment setup (HOME, MOLE_DIR) to override." >&2
  # Non-fatal — recorded as observation for Phase 2.
fi

# 8. Smoke test: run mole --version to confirm the bundled tree is invokable.
echo "[bundle-mole] Smoke test: ${OUT_DIR}/mole --version"
"${OUT_DIR}/mole" --version || {
  echo "ERROR: ${OUT_DIR}/mole --version failed." >&2
  echo "       This breaks D-14's smoke test. Inspect the wrapper script and PATH/HOME." >&2
  exit 1
}

echo "[bundle-mole] DONE. Bundle is ready at ${OUT_DIR}"
echo "[bundle-mole] To install into a built MoleBar.app:"
echo "                 mkdir -p MoleBar.app/Contents/Helpers"
echo "                 cp -R ${OUT_DIR}/. MoleBar.app/Contents/Helpers/"
