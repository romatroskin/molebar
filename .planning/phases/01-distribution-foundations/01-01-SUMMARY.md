---
phase: 01-distribution-foundations
plan: 01
status: complete
completed_at: "2026-04-28"
requirements: [OSS-01, OSS-04]
---

# Plan 01-01 Summary — Bootstrap GitHub repo + LICENSE/README/.gitignore + gh-pages

## What was built

The public open-source posture (OSS-01) and the on-platform secret-hygiene controls (OSS-04 part 1) for `github.com/romatroskin/molebar`:

- **Public repo** at https://github.com/romatroskin/molebar with MIT license metadata (`gh repo view --json licenseInfo` returns `mit`).
- **Three repo-root files** committed to `main` in commit `393890c` (`chore(01-01): bootstrap MIT LICENSE, README, and .gitignore (OSS-01, OSS-04)`):
  - `LICENSE` — MIT verbatim, copyright 2026 romatroskin.
  - `README.md` — contributor-friendly per OSS-01: Highlights / Install / Build from source / Architecture / Contributing / License / Acknowledgments. References FROZEN bundle ID `app.molebar.MoleBar` and (current) FROZEN appcast URL.
  - `.gitignore` — explicit globs for Sparkle key files (`*.key`, `*.p8`, `*.p12`, `*.pem`, `private/`, `sparkle*.key`), Apple notarization creds (`AuthKey_*.p8`, `notarytool*.json`), Xcode build outputs, env scratch.
- **Orphan `gh-pages` branch** with `index.html` placeholder (commit `e71a8e7`, `chore(gh-pages): initial gh-pages landing`), pushed to origin.
- **GitHub Pages enabled** with source `gh-pages / (root)`; first deploy succeeded (`gh api .../pages` returns `status: built`).
- **Push Protection + Secret Scanning enabled** at repo level (defense-in-depth alongside the .gitignore globs).

## Branches at origin

| Branch | Tip | Purpose |
|--------|-----|---------|
| `main` | `393890c` chore(01-01): bootstrap … | Default; LICENSE + README + .gitignore committed atop the pre-existing 10-commit `.planning/` history. |
| `gh-pages` | `e71a8e7` chore(gh-pages): initial gh-pages landing | Orphan; will host `appcast.xml` once Plan 06's release CI publishes (per Pitfall A6). |

## Verification (Task 5, all 6 checks)

| # | Check | Expected | Actual |
|---|-------|----------|--------|
| 1 | `gh repo view --json visibility,licenseInfo` | `PUBLIC mit` | ✅ `PUBLIC mit` |
| 2 | Secret scanning + Push Protection status | `enabled` × 2 | ✅ `enabled` / `enabled` |
| 3 | `gh api .../branches/gh-pages` | `gh-pages` | ✅ `gh-pages` |
| 4 | `gh api .../pages` status | `built` | ✅ `built` |
| 5 | `curl https://romatroskin.github.io/molebar/index.html` | `200` | ⚠️ `301` direct, `200` after redirect (see Deviation 1) |
| 6 | `git log --all -p \| grep -E 'BEGIN.*PRIVATE KEY\|^edpr'` | empty | ✅ no key material outside `.planning/` docs (regex matched only the validation docs that document the regex itself; refined check excluding `.planning/` is empty) |

## Deviations from the plan

### Deviation 1 — GitHub Pages redirect to `puffpuff.dev`

**What:** `https://romatroskin.github.io/molebar/index.html` returns `301 → https://puffpuff.dev/molebar/index.html` (which returns `200`). The redirect comes from a **user-account-level custom domain** on `github.com/settings/pages` for `romatroskin`. The `gh-pages` branch contains no `CNAME` file; `gh api repos/romatroskin/molebar/pages` confirms `cname: null` but `html_url: http://puffpuff.dev/molebar/`.

**Functional impact:** Pages serves correctly via redirect. Sparkle 2.x follows 30x redirects by default, so the FROZEN appcast URL still resolves end-to-end.

**Project-level impact:** The D-12 frozen appcast URL was `https://romatroskin.github.io/molebar/appcast.xml`. With the redirect in place, that URL's longevity is now tied to `puffpuff.dev` staying registered. Because no v0.0.1 has shipped yet, this is the cheapest moment to revisit D-12.

**Decision:** Update D-12 to use `https://puffpuff.dev/molebar/appcast.xml` as the canonical FROZEN URL. The follow-up patch lands as a docs-only commit immediately after this plan and rewrites every `romatroskin.github.io/molebar` reference across `.planning/` + `README.md`. README.md was committed in this plan with the old URL and will be rewritten by the follow-up patch.

### Deviation 2 — Local branch was `master`, plan assumed `main`

**What:** The pre-existing 10-commit local history was on `master`. Renamed to `main` (`git branch -m master main`) before adding the SSH remote and pushing. No history rewrite — pure pointer rename.

### Deviation 3 — Force-push required to seed origin/main

**What:** GitHub auto-created an initial commit containing a templated `LICENSE` when the user selected "MIT License" in the repo creation form. Local `main` had unrelated history (the 10 `.planning/` commits + our bootstrap commit), so `git push -u origin main` rejected with `non-fast-forward`. After user authorization, force-pushed (`git push -u origin main --force`), overwriting the auto-LICENSE commit. MIT license metadata is detected from the `LICENSE` file content (verified via Check 1 = `PUBLIC mit`), so the metadata survived.

## Outputs / artifacts

- `LICENSE` (root, 1099 bytes)
- `README.md` (root, ~3.9 KB)
- `.gitignore` (root, ~600 bytes)
- `index.html` on `gh-pages` (~200 bytes; Plan 06's release workflow keeps this via `peaceiris/actions-gh-pages@v4 keep_files=true`, per Pitfall A6)
- Repo: https://github.com/romatroskin/molebar (PUBLIC, MIT, Push Protection + Secret Scanning enabled)
- Pages: serves at `https://romatroskin.github.io/molebar/` → 301 → `https://puffpuff.dev/molebar/` (HTTPS cert covers `puffpuff.dev` + `www.puffpuff.dev`)

## Carry-forward

- **D-12 update follow-up** (this commit's immediate sibling): replace `https://romatroskin.github.io/molebar/...` with `https://puffpuff.dev/molebar/...` across PROJECT.md, ROADMAP.md, RESEARCH.md, every plan file in this phase, the just-committed README.md, and the `gh-pages` branch's `index.html`. Plan 01-02's `Info.plist` `SUFeedURL` will use the new URL.
- **Plan 06** (release CI) inherits the new appcast URL in its `peaceiris/actions-gh-pages@v4` `publish_dir` and any documentation references.
- **Phase 1.5** (Sign & Ship for Real) — branch protection on `main` was deferred per VALIDATION.md and is unaffected.
