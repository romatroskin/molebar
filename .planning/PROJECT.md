# MoleBar

## What This Is

MoleBar is a native macOS 14+ menu bar app that brings the full power of the open-source [`tw93/mole`](https://github.com/tw93/mole) CLI — system cleaning, monitoring, disk analysis, and maintenance — to a glanceable, click-to-run interface. It targets Mac users (developers and non-developers alike) who want comprehensive Mac maintenance without opening a terminal.

## Core Value

**Full Mole feature parity in the menu bar.** Every capability of the Mole CLI must eventually be reachable from the MoleBar UI — breadth over polish. If MoleBar can only do half of what `mole` does, it has failed its mission.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

(None yet — ship to validate)

### Active

<!-- Current scope. Building toward these. v1 hypothesis set. -->

- [ ] Live system stats (CPU / GPU / memory / disk / network) with configurable display: icon-only, single inline metric, or popover-only (default)
- [ ] One-click cleaning actions (caches, logs, browser data, diagnostics) sourced from Mole CLI's `clean` subcommands
- [ ] Disk space analyzer — visualize large files/folders (will need a window, not just a popover)
- [ ] Project cruft purge — find and remove `node_modules`, build dirs, etc. across user-selected roots
- [ ] System optimization — DB rebuilds, network reset, Finder/Dock refresh, Spotlight reindex
- [ ] Installer leftovers — remove old `.pkg` / `.dmg` files from Downloads / Desktop / Homebrew caches
- [ ] Scheduling / automation — run cleanups on a recurring schedule (built on top of Mole, not in Mole itself); user-visible notifications on result
- [ ] Bundled `mole` binary inside the `.app`, auto-updated separately from the app via GitHub Releases of `tw93/mole`
- [ ] Dry-run-first safety model with a power-user toggle that allows skipping the preview after a destructive action has been used 3+ times
- [ ] Notarized signed `.dmg` distribution via GitHub Releases
- [ ] Homebrew Cask formula (`brew install --cask molebar`)
- [ ] In-app auto-update via Sparkle 2

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- **App uninstaller (smart uninstall with leftover review)** — deferred to v2. Heaviest UX surface (drag-target, leftover diff, multi-step flow); shipping v1 without it lets us validate core value sooner.
- **Full GUI app (separate window beyond the disk analyzer)** — deferred to v2. v1 is menubar-first; architecture must keep core logic UI-agnostic so a SwiftUI window app can be added without rewrites.
- **Mac App Store distribution** — Mole's deep-clean operations require Full Disk Access and write to protected paths the App Store sandbox forbids. Distributing outside the store is the only path that preserves Mole's capabilities.
- **Reimplementing Mole's logic in Swift** — wrapping the CLI keeps us in lockstep with upstream and avoids re-deriving Mole's safety model. We pay for that with a binary-bundling toolchain.
- **Closed-source / proprietary fork** — open-source MIT matches Mole's ethos and lowers trust friction for a tool that performs destructive operations on a user's Mac.
- **Supporting macOS < 14 (Sonoma)** — MoleBar is a new app with no legacy users; targeting 14+ unlocks modern SwiftUI `MenuBarExtra`, the `Observation` framework, and the Charts framework without compatibility shims. We'll revisit if user demand surfaces.
- **iOS / iPadOS / Linux variants** — Mole is macOS-specific; MoleBar inherits that constraint.

## Context

- **Upstream:** `tw93/mole` is an active open-source CLI (Shell 81% / Go 19%) for deep Mac cleaning, smart uninstalls, system optimization, and live monitoring. It's used today via terminal interactive menus (arrow keys / vim bindings) and emits machine-readable JSON for automation — that JSON output is the integration surface MoleBar will rely on.
- **Audience continuity:** Mole's existing audience is technical and brew-comfortable. MoleBar reaches that audience plus less-CLI-comfortable Mac users who would benefit from the same safety guarantees.
- **Trust model:** The app performs destructive operations on the user's machine. Public release means safety, transparency (open source, dry-run defaults, JSON logs visible), and conservative defaults are non-negotiable trust signals.
- **Permissions reality:** Most Mole operations require Full Disk Access; the app must guide users through granting it on first launch. Some operations (Spotlight, network reset) need additional system entitlements or `osascript` privilege escalation flows.
- **Forward compatibility:** v1 is menubar-only, but the disk analyzer already needs a window — so the architecture separates a UI-agnostic core (CLI orchestration, parsing, scheduling) from one or more SwiftUI surfaces (menu bar popover, disk analyzer window, future full GUI).

## Constraints

- **Platform**: macOS 14 (Sonoma) and newer — *Why:* unlocks SwiftUI `MenuBarExtra`, the `Observation` framework, and Charts without compat shims; no legacy users to drag along.
- **Tech stack**: Swift + SwiftUI primary, AppKit only where required (drag-target, status item edge cases) — *Why:* native, smallest possible binary, best system integration for a menu bar tool.
- **CLI dependency**: Bundle the `mole` binary inside the `.app`; auto-update it separately from MoleBar releases via the upstream GitHub Releases — *Why:* zero install friction for users while keeping us in lockstep with upstream feature work; we own signing/notarizing the bundled binary.
- **Distribution**: GitHub Releases (signed/notarized `.dmg`) + Homebrew Cask + Sparkle 2 in-app updates — *Why:* matches Mole's audience expectations; standard for indie Mac apps; avoids App Store sandbox limits.
- **License**: MIT, public repository from day one — *Why:* matches upstream Mole posture; supports trust for a tool that touches user data.
- **Safety**: Every destructive action defaults to a dry-run preview; power-user toggle unlocks one-click execution after a per-action threshold (3+ uses) — *Why:* core value = parity with Mole's safety model; trust is the differentiator.
- **Apple Developer ID**: Required for notarization and Sparkle updates — *Why:* unsigned/un-notarized apps trigger Gatekeeper warnings and erode trust at install time.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Wrap the Mole CLI rather than reimplement | Stays in lockstep with upstream features automatically; avoids re-deriving Mole's safety model | — Pending |
| Menu bar app first, full GUI deferred | Smallest valuable surface area; validates core value with the least code; disk analyzer window forces a clean UI/core split anyway | — Pending |
| macOS 14+ minimum | New app with no legacy users; modern SwiftUI APIs cut implementation cost significantly | — Pending |
| Bundle mole binary, auto-update separately | Zero install friction without locking users to a stale CLI version | — Pending |
| Dry-run-first with power-user toggle | Conservative default for destructive ops; respects experienced users after they've seen previews | — Pending |
| Open source MIT | Matches Mole's ethos; trust signal for an app that touches user data | — Pending |
| Defer app uninstaller to v2 | Highest-UX-cost feature; v1 ships sooner without it; smart uninstall is signature Mole feature so it must follow soon | — Pending |
| Distribution via GitHub + Homebrew Cask + Sparkle, not App Store | App Store sandbox blocks deep-clean operations; this triple matches Mole audience expectations | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-27 after initialization*
