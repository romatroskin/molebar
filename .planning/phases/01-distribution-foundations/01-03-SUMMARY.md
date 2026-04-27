---
phase: 01-distribution-foundations
plan: 03
status: complete
completed_at: "2026-04-28"
requirements: [DIST-08]
---

# Plan 01-03 Summary — Mole bundling recipe (corrected per A1)

## What was built

The committed recipe that produces a stage-able bundle of the upstream `tw93/mole` tree at a pinned version:

- **`mole-version.txt`** at repo root, exact content: `V1.36.2\n` (8 bytes). Pre-flight verification confirmed all 4 upstream release artifacts return 2xx on HEAD and the `V1.36.2` git tag is reachable.
- **`scripts/bundle-mole.sh`** (mode 0755) — the corrected recipe from 01-RESEARCH.md §Pitfall A1: clones the upstream tree at the pinned tag for the Shell wrappers (`mole`, `mo`) + module trees (`lib/`, `cmd/`, `scripts/`), then `lipo -create`s ONLY the two Go helpers (`analyze-go`, `status-go`) from the per-arch release artifacts. Hardened with `set -euo pipefail`, `curl --retry 3`, `file` + `lipo -archs` post-verification (Pitfall A7), and an A9 absolute-path-reference warning block for Phase 2 awareness.

## End-to-end run on the dev Mac

```
$ ./scripts/bundle-mole.sh
[bundle-mole] Pinned tw93/mole version: V1.36.2
[bundle-mole] Downloading analyze-darwin-arm64
[bundle-mole] Downloading analyze-darwin-amd64
[bundle-mole] Downloading status-darwin-arm64
[bundle-mole] Downloading status-darwin-amd64
[bundle-mole] Cloning tw93/mole at V1.36.2
[bundle-mole] lipo -create analyze-go (arm64+amd64 -> Universal2)
[bundle-mole] lipo -create status-go (arm64+amd64 -> Universal2)
[bundle-mole] WARN: mole/mo wrapper references absolute paths that may not resolve
                    inside MoleBar.app/Contents/Helpers/. Inspect the lines above.
[bundle-mole] Smoke test: …/mole-bundle/mole --version

Mole version 1.36.2
macOS: 26.3.1
Architecture: arm64
Kernel: 25.3.0
SIP: Enabled
Disk Free: 10Gi
Install: Homebrew
Shell: /bin/zsh

[bundle-mole] DONE. Bundle is ready at …/mole-bundle
```

## Verification artifacts

| Check | Output |
|-------|--------|
| `cat mole-version.txt` | `V1.36.2` |
| `wc -c < mole-version.txt` | `8` |
| `mole-bundle/mole --version` exit | `0` |
| First line of `mole --version` | `Mole version 1.36.2` ← Phase 2's parser anchor |
| `file mole-bundle/bin/analyze-go` | `Mach-O universal binary with 2 architectures: [x86_64:Mach-O 64-bit executable x86_64] [arm64]` |
| `file mole-bundle/bin/status-go` | `Mach-O universal binary with 2 architectures: [x86_64:Mach-O 64-bit executable x86_64] [arm64]` |
| `lipo -archs mole-bundle/bin/analyze-go` | `x86_64 arm64` |
| `lipo -archs mole-bundle/bin/status-go` | `x86_64 arm64` |
| `git check-ignore mole-bundle` | exits `0` (`mole-bundle/` is ignored per `.gitignore` from plan 01-01) |
| `du -sh mole-bundle` | **`16M`** ← informs Phase 1.5 DMG-size and notarization planning |

## Bundle layout (recipe output)

```
mole-bundle/
├── bin/
│   ├── analyze-go   (Universal2 Mach-O, mode 0755)
│   └── status-go    (Universal2 Mach-O, mode 0755)
├── cmd/             (upstream Shell command tree)
├── lib/             (upstream Shell library tree)
├── mo               (Shell wrapper, mode 0755)
├── mole             (Shell wrapper, mode 0755 — entry point)
└── scripts/         (upstream Shell scripts)
```

Plan 05's `package-dmg.sh` and Plan 06's `release.yml` install this tree at `MoleBar.app/Contents/Helpers/mole/` (the `mole/` subdirectory pattern locked by D-14 amendment in CONTEXT.md).

## A9 observations — for Phase 2's MoleClient

The script's A9 warning block surfaced absolute-path references in the bundled `mole` wrapper that Phase 2's `MoleClient.runAction` will need to handle by setting environment variables before invocation:

| File:line (mole-bundle/mole) | Reference | Phase 2 action |
|---|---|---|
| 87–88 | `/opt/homebrew/bin/mole`, `/usr/local/bin/mole`, `/opt/homebrew/Cellar/mole`, `/usr/local/Cellar/mole` | Self-installation-detection branch — never matches an `.app`-bundled wrapper, so safe (the wrapper falls through to the bundled-tree path). |
| 112, 128, 469 | `${MOLE_CONFIG_DIR:-$HOME/.config/mole}` | Set `MOLE_CONFIG_DIR` env to a path inside `~/Library/Application Support/MoleBar/` so user state lives outside `~/.config/`. |
| 147, 197, 512 | `$HOME/.cache/mole/update_message` | Set `MOLE_CACHE_DIR` if upstream supports it; otherwise accept that Mole writes to `~/.cache/mole/` (acceptable for v1). |
| 544–545 | `/usr/local/bin/brew` (upstream auto-update branch) | Disable upstream auto-update path entirely — MoleBar's bundled-tree updater (Phase 8) replaces this. Set `MOLE_DISABLE_AUTO_UPDATE=1` if upstream supports it; otherwise mask via PATH. |

**Phase 2 carry:** `MoleClient` initializer takes a `helpersDir: URL` and constructs an `[String: String]` env map setting the above. Add to `CORE-04` Acceptance.

## Deviations from the plan

### Deviation 1 — Plan-prescribed Task 2 verify regex used BRE-incompatible patterns

**What:** The plan's Task 2 verify shell command included `grep -q 'mole-bundle/bin/analyze-go' …` and `grep -q 'cp -R "${SRC}/lib"' …`. Both fail under BSD/macOS grep:

1. `mole-bundle/bin/analyze-go` is the *resolved* path; the script source contains the variable form `${OUT_DIR}/bin/analyze-go`. The literal never appears.
2. `'cp -R "${SRC}/lib"'` — even with single quotes, `${SRC}` is parsed by BRE as a meta sequence on macOS's BSD grep; `grep -F` (fixed string) returns the expected `1` match.

The script content is byte-identical to the plan's prescribed code in §`<action>`. Confirmed via `od -c` of the relevant line and `grep -F` re-verification. Functional acceptance was demonstrated end-to-end by Task 3 (which is the canonical check anyway — actually running the script and verifying the produced bundle).

No code change needed. Carry-forward: tighten plan-template verify regex to use `grep -F` for any pattern containing `$`, `{`, or `}`.

### Observation — A9 warnings printed (non-fatal, expected)

The script's WARN block fired (10 absolute-path references in `mole-bundle/mole`). This was anticipated by RESEARCH §A9 and the script intentionally non-fatals it. Captured above; informs Phase 2 design. Not a deviation — by-design.

## Outputs / artifacts

| Path | Notes |
|------|-------|
| `mole-version.txt` | 8 bytes; one line `V1.36.2\n`. Bumping = a deliberate human-reviewed PR + re-run (per D-14). |
| `scripts/bundle-mole.sh` | 4 KB; mode 0755; idempotent (re-runs reproduce the same bundle modulo file timestamps). Plan 06's release.yml invokes `bash scripts/bundle-mole.sh` unmodified. |
| `mole-bundle/` (runtime) | 16 MB; gitignored. Plan 05's `package-dmg.sh` consumes this tree. |

## Carry-forward

- **Plan 05** (DMG packaging): `scripts/package-dmg.sh` should call `./scripts/bundle-mole.sh` (or assume `mole-bundle/` is fresh) and copy `mole-bundle/.` into `MoleBar.app/Contents/Helpers/mole/`.
- **Plan 06** (release CI): `release.yml` step "Bundle tw93/mole at pinned version" runs `bash scripts/bundle-mole.sh`. The script's `set -euo pipefail` + post-lipo verification means a CI failure here is loud and actionable.
- **Phase 1.5** (signing): the 16 MB bundle's Go helpers (`analyze-go`, `status-go`) need to be signed inside-out before the parent `.app`. Add to Phase 1.5 sign script.
- **Phase 2** (`MoleClient.runAction`): set `MOLE_CONFIG_DIR`, `MOLE_CACHE_DIR`, and disable upstream auto-update path per A9 table above.
- **Phase 8** (CLI auto-updater): re-runs this script (or a similar one) at runtime against `~/Library/Application Support/MoleBar/cli/` and re-signs ad-hoc.
