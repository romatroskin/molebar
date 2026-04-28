---
phase: 2
phase_name: CLI Orchestration Core
phase_slug: cli-orchestration-core
created: "2026-04-28"
discuss_mode: discuss
status: context-captured
---

# Phase 2 Context — CLI Orchestration Core

<domain>
Build the UI-agnostic `MoleBarCore` SwiftPM module that owns every subprocess spawn in the codebase. Deliverables: a non-deadlocking `Foundation.Process` wrapper, versioned Codable models for Mole's JSON output, the `MoleClient` actor public API (`AsyncThrowingStream`-based for streaming subcommands, `async throws` for one-shot subcommands), and the no-outbound-network-traffic invariant — verified, not asserted.

Every later feature (live system monitoring → Phase 3, cleaning pipeline → Phase 5, disk analyzer → Phase 6, settings/scheduling → Phase 7, CLI auto-updater → Phase 8) consumes `MoleClient` through this module. The shape we lock here propagates to all downstream stores and view-models.
</domain>

<carried_forward>
The following decisions land on Phase 2 from earlier phases. Not re-asked:

- **Subprocess wrapper:** `Foundation.Process` actor-wrapped (PROJECT.md "Tech Stack"). `swift-subprocess` migration is post-1.0 v1.x maintenance; `jamf/Subprocess` is an alternative we deliberately skipped for v1 to keep zero third-party deps in `MoleBarCore`.
- **Bundled-mole resolver precedence (D-17):** at runtime, prefer `~/Library/Application Support/MoleBar/bin/mole` if Phase 8's CLI updater wrote one; otherwise fall back to `Contents/Helpers/mole/mole`. `MoleClient.resolveBinary()` implements this two-step resolution.
- **Bundled-mole layout (D-14 amendment):** the bundled tree is a directory at `Contents/Helpers/mole/` containing the Shell wrapper (`mole`, `mo`, `lib/`, `cmd/`, `scripts/`) plus Universal2 Go helpers at `bin/analyze-go` and `bin/status-go`. The Shell wrapper at `Contents/Helpers/mole/mole` is the entry point.
- **A9 absolute-path env handling (Plan 01-03 SUMMARY carry-forward):** `MoleClient` initializer takes `helpersDir: URL` and constructs an env map setting:
  - `MOLE_CONFIG_DIR` → a path inside `~/Library/Application Support/MoleBar/` (so user state lives outside `~/.config/`)
  - `MOLE_CACHE_DIR` → a path inside `~/Library/Caches/MoleBar/` if upstream supports the env var; otherwise accept `~/.cache/mole/` writes
  - `MOLE_DISABLE_AUTO_UPDATE=1` if upstream supports it; otherwise mask `/usr/local/bin/brew` via PATH so the upstream auto-update branch never matches
  - Explicit `PATH=/usr/bin:/bin:/usr/sbin:/sbin` (no Homebrew, no asdf, no oh-my-zsh injections)
  - Explicit `HOME=$HOME` (passthrough; `MOLE_CONFIG_DIR` overrides where mole writes, not where `$HOME` points)
  - Explicit `LANG=en_US.UTF-8` (deterministic locale for parsing output)
- **Module location:** `Packages/MoleBarPackage/Sources/MoleBarCore/`. The package is already wired as a SwiftPM dep on the `MoleBar` app target (Plan 01-02). The empty `Placeholder.swift` can be deleted by the first real symbol we add.
- **Swift toolchain:** Swift 6 strict concurrency (locked via `SWIFT_VERSION = "6.0"` in xcodegen/project.pbxproj). All MoleClient APIs must satisfy strict-concurrency checking. `@MainActor` on UI-touching code only — `MoleBarCore` itself is `@MainActor`-free (it's an actor).
- **Deployment target:** macOS 14 floor. `MoleClient` may use `Observation` framework, but as `MoleBarCore` is UI-agnostic, prefer plain Swift types.
- **Logging:** `os.Logger(subsystem: "app.molebar.MoleBar", category: "cli")` for all `MoleClient` operations; additional categories per concern (`scheduler`, `updater`, `permissions`, `ui`) are owned by the modules that introduce them.
- **No external dependencies** in `MoleBarCore`. The module imports only `Foundation`, `os` (for Logger), and Swift stdlib. Deliberate — keeps zero supply-chain attack surface on the security-sensitive subprocess + network-invariant code.
</carried_forward>

<decisions>

## D-19: MoleClient API surface — per-subcommand typed methods

`MoleClient` exposes one public method per Mole subcommand we wrap. Streaming subcommands return `AsyncThrowingStream<TypedElement, Error>`; one-shot subcommands return `async throws -> TypedResult`. There is **no public `MoleEvent` unifying enum** — each method's stream/return type is the actual decoded payload type.

```swift
public actor MoleClient {
    public func runVersion() async throws -> MoleVersion
    public func streamStats() -> AsyncThrowingStream<StatsSnapshot, Error>
    public func runClean(dryRun: Bool) async throws -> CleanReport
    public func runAnalyze(path: URL) async throws -> AnalysisResult
    // ... grows by one method per future subcommand wrapper
}
```

**Why:** Type-safe at every call site. `MoleBarStores`'s `StatsStore.observe()` sees `for try await snap in client.streamStats() { self.cpu = snap.cpu }` with no variant unwrapping. Worth the marginal API-surface growth.

**Internal implementation note for the planner:** Internally MoleClient may have a single private `run(_ subcommand: SubcommandSpec)` that returns raw stdout lines + exit code; each public typed method is a thin filter that decodes lines into the right type. This is implementation detail — the planner picks the shape.

## D-20: Schema-versioning model — forward-compatible single types + lenient decoding

CORE-03 ("versioned Codable models with explicit failure modes") is implemented as **one Codable struct per output shape**, not one struct per supported Mole version. Forward-compatible decoding: optional fields for anything that may appear in newer Mole versions, plus an `extra: [String: AnyCodable]` catch-all to preserve unknown JSON keys for diagnostics.

```swift
public struct StatsSnapshot: Codable, Sendable {
    public let cpu: Double
    public let memory: MemoryStats
    public let network: NetworkStats?           // optional = forward-compat
    public let extra: [String: AnyCodable]      // unknown-keys catch-all
    // explicit init(from:) preserves unknown keys into `extra`
}
```

**Why:** Mole's JSON evolves additively in practice. Pinned-per-version types (StatsSnapshot_V1_36, StatsSnapshot_V1_37) double maintenance for marginal benefit. CORE-07's nightly drift CI catches breaking changes upstream before they reach a user. Decode failures surface as `MoleError.decodeFailed(payload:, key:, underlying:)` (see D-22) — never silent, never crash.

**Implementation note:** `AnyCodable` is hand-rolled in `MoleBarCore` (~30 LOC, no external dep) — the planner picks one of the well-known patterns (e.g., enum-of-known-JSON-types with `Codable` conformance).

## D-21: CORE-07 nightly drift response — fail loud + auto-open issue

The nightly CI job runs `MoleBarCore`'s parser test suite against the latest `tw93/mole` `main` branch. On any decode failure or test regression, the job:

1. Fails the workflow run (red X in Actions tab + email).
2. Auto-opens (or appends to an existing open) GitHub issue titled `Schema drift detected vs tw93/mole@<sha>`. Body contains: failing payload, expected schema, diff vs the pinned version, link to the upstream commit range that introduced the change.

**Why:** Two-channel notification (red CI + open issue) is hard to miss without being noisy. Auto-PR with regenerated fixtures was rejected — too aggressive; risks landing upstream behavior changes that subtly alter mole's output without human review.

**Implementation note:** Use the `gh` CLI (already on `macos-15` runners) or a maintained action like `peter-evans/create-issue-from-file`. Implementation detail for the planner.

## D-22: MoleError — flat enum with associated values

```swift
public enum MoleError: Error {
    case binaryNotFound(searched: [URL])
    case processFailed(exit: Int32, stderr: String)
    case decodeFailed(payload: Data, key: String, underlying: any Error)
    case cancelled
    case timeout(after: TimeInterval)
    case envSetupFailed(reason: String)
}
```

**Why:** Idiomatic Swift, exhaustive switch at call sites, ~6 cases now and grows on demand. Per-method error types (`MoleStreamError`, `MoleDecodeError`) were rejected — too much surface area for the diagnostic gain. Struct-with-Kind was rejected — less idiomatic, no real win over enum.

## D-23: Cancellation timing — 250 ms SIGTERM grace before SIGKILL

When a `Task` consuming a `MoleClient` stream/method is cancelled, the actor:

1. Sends `SIGTERM` to the spawned mole process group (see D-25).
2. Waits **up to 250 ms** for graceful shutdown.
3. Sends `SIGKILL` to the process group if the child hasn't reaped.
4. Yields the final `MoleError.cancelled` to the stream consumer (see D-24).

**Why:** Success-criterion #1 caps end-to-end cancellation at 1 second. 250 ms gives 4× headroom for slow CI runners or thrash. Mole subcommands are inherently fast-shutdown (no flush of huge state) — 250 ms is sufficient for clean teardown of any buffered stdout writes.

## D-24: Stream-on-cancel — throw `MoleError.cancelled`, then `finish()`

When the `MoleClient` stream is cancelled (consumer Task cancellation OR explicit `terminationHandler`-fired teardown), the `AsyncThrowingStream`:

1. Emits no further data values.
2. Throws `MoleError.cancelled` from the consumer's `for try await ... in stream`.
3. Calls `continuation.finish()` so the stream is officially closed.

**Why:** Symmetrical with one-shot `async throws` methods that throw on cancel. Distinguishable from natural stream-end (a successful completion just calls `finish()` with no error). Surfacing the underlying POSIX signal (`MoleError.processFailed(SIGTERM, ...)`) was rejected — couples the public API to signal numbers.

## D-25: Process-group cleanup — `setpgid` + signal `-PID`

The spawned mole process is placed in its own process group at fork-time (Foundation.Process supports this via launch attributes / `processIdentifier` post-launch). On cancellation, `MoleClient` sends `SIGTERM` (then `SIGKILL` per D-23) to the **negative PID** — POSIX shorthand for "the entire process group" — so any grandchildren spawned by mole's Shell wrapper (the Go helpers at `bin/analyze-go`, `bin/status-go`) are reaped too.

**Why:** Inspecting `mole-bundle/mole`, the Shell wrapper invokes the Go helpers as subprocesses. Plain `Process.terminate()` only SIGTERMs the wrapper PID, leaving the Go helpers as zombies. Process-group signaling catches them all. POSIX-portable, no third-party dep.

**Implementation note for the planner:** the exact Foundation.Process API path on macOS 14 (does `Process` honor `setpgid`? do we need to drop down to `posix_spawn` with `POSIX_SPAWN_SETPGROUP`?) is a research question. If Foundation.Process doesn't expose process-group control, the planner picks one of: (a) `posix_spawn` C-level wrapper, (b) a pre-exec helper script that runs `setpgid` then `exec mole`, (c) waiting for `swift-subprocess` 1.0 (later, not v1).

## D-26: Network-traffic invariant verification — two-layer (build-time + runtime)

CORE-02 / OSS-02 ("zero outbound network calls from MoleBar at startup or during stats streaming") is verified by **two complementary mechanisms**, both in CI:

**Layer 1 — Build-time import ban (`scripts/check-no-network.sh`):**
```bash
#!/usr/bin/env bash
set -euo pipefail
SOURCES="Packages/MoleBarPackage/Sources/MoleBarCore"
FORBIDDEN='import (Network|CFNetwork)|URLSession|NWConnection|NWPath|NWBrowser|NSURLConnection'
if grep -rE "$FORBIDDEN" "$SOURCES"; then
  echo "ERROR: forbidden network symbol in MoleBarCore (OSS-02)" >&2
  exit 1
fi
```

The script runs in `build.yml` as a step gating the build, AND as a local pre-commit hook (advisory). A future contributor adding `URLSession.shared.data(...)` in `MoleBarCore` triggers an actionable build failure.

**Layer 2 — Runtime XCTest (`NoNetworkTests`):**
```swift
final class NoNetworkTests: XCTestCase {
    override class func setUp() {
        URLProtocol.registerClass(BlockAllProtocol.self)
        // BlockAllProtocol.init throws fatalError on any URL request
    }
    func testMoleClientMakesZeroRequests() async throws {
        let client = MoleClient(helpersDir: testBundleHelpersDir)
        _ = try? await client.runVersion()
        for try await _ in client.streamStats().prefix(3) { /* drain */ }
        // BlockAllProtocol fatalError'd if any request fired
    }
}
```

Plus an `NWPathMonitor` snapshot at test-start vs test-end — fails if any monitored path (`.wifi`, `.cellular`, `.wired`) showed activity attributable to MoleBarCore's PID during the test window.

**Why two layers:** Build-time grep catches imports (fast feedback; runs on every PR + every commit). Runtime XCTest catches transitive uses, dynamic/runtime dispatch, or symbols imported via typealiases that grep misses. Manual Little Snitch is still the human-driven gate before each release (per the Phase 1 / Phase 1.5 pre-flight checklist) — but Little Snitch alone can't catch a regression introduced today and shipped tomorrow.

## D-27 (small): LICENSE-MOLE.txt sourcing — static commit, refresh on mole version bump

`LICENSE-MOLE.txt` (CORE-08) is a **static file committed to the repo at `MoleBar/Resources/LICENSE-MOLE.txt`** (xcodegen wires it into `Contents/Resources/`). It's the verbatim contents of `tw93/mole`'s upstream `LICENSE` file at the pinned version (`mole-version.txt` from Phase 1).

When `mole-version.txt` bumps, the developer also refreshes `LICENSE-MOLE.txt` in the same PR. `scripts/bundle-mole.sh` may optionally print a reminder if `LICENSE-MOLE.txt` is older than the cloned upstream tree.

**Why:** Static commit is auditable in `git log` and visible in any clone. CI-injected was rejected — the LICENSE rarely changes (Mole is MIT, same as us, so the file is essentially an attribution placeholder); CI-injection adds complexity for marginal benefit.

</decisions>

<deferred>

Items raised during discussion but **not in scope for Phase 2.** Capture for future phases:

- **Subprocess wrapper benchmark** (Phase 2 spike per STATE.md "Blockers/Concerns"): `Foundation.Process` vs `jamf/Subprocess`. Decided against: PROJECT.md already commits to `Foundation.Process`; the spike was informational. If a real performance issue surfaces in Phase 5+ (cleaning pipeline launches many short-lived mole invocations), revisit then with measured data, not speculative comparison.
- **Migration to `swift-subprocess` 1.0**: post-1.0 v1.x maintenance work. Not a Phase 2 deliverable. Watch the SF-0037 review (concluded April 2026 per PROJECT.md sources) and migrate in a v1.x point release.
- **`mole stats --json --watch` flag verification**: research dependency for this phase, not a deferral. Listed under `<research_dependencies>` below.
- **Sparkle's appcast URL on the OSS-02 allowlist**: success-criterion #5 says "only the explicitly-allowed Sparkle appcast URL appears". That allowlist lives in the **MoleBar app target's Info.plist** (Sparkle's domain), not in `MoleBarCore`. `MoleBarCore` itself contributes zero outbound calls; the Sparkle path is in `MoleBarApp.swift` (Plan 01-02). This is a non-issue for Phase 2.
- **CLI binary auto-updater (`MoleBinaryUpdater`)**: Phase 8 work. `MoleClient.resolveBinary()` only checks both candidate paths and picks one — it does not download or write.
- **Per-subcommand cancellation policies**: e.g., should `runClean(dryRun: false)` (a destructive op) honor cancellation differently than `streamStats()`? Phase 5's responsibility — by then we'll have real destructive ops; Phase 2 only needs to ship a uniform cancel mechanism.

</deferred>

<canonical_refs>

Downstream agents (researcher, planner, executor) MUST read these. Full relative paths from repo root:

**Project + roadmap:**
- `.planning/PROJECT.md` (CLAUDE.md mirror) — tech stack, constraints, "what NOT to use", subprocess wrapper decision
- `.planning/REQUIREMENTS.md` — CORE-01..08 + OSS-02 + OSS-03 acceptance language
- `.planning/ROADMAP.md` — Phase 2 success criteria (5 items)
- `.planning/STATE.md` — Phase 1 status; "Blockers/Concerns" lists Phase 2 spike items

**Phase 1 carry-forward (must read for context):**
- `.planning/phases/01-distribution-foundations/01-CONTEXT.md` — Phase 1 D-decisions (D-14 amendment is critical for resolver path; D-17 for resolver precedence)
- `.planning/phases/01-distribution-foundations/01-03-SUMMARY.md` — A9 absolute-path observations table; informs `MoleClient.runAction` env-setup
- `.planning/phases/01-distribution-foundations/01-02-SUMMARY.md` — Sparkle SPM artifact path; Swift 6 strict-concurrency lessons (`@MainActor` annotation deviation)
- `.planning/phases/01-distribution-foundations/01-RESEARCH.md` — research context that planner may need to reference for Mole binary specifics

**Code (must read before planning):**
- `Packages/MoleBarPackage/Package.swift` — current SwiftPM workspace shape; MoleBarCore is empty
- `Packages/MoleBarPackage/Sources/MoleBarCore/Placeholder.swift` — to be deleted by the first real symbol
- `MoleBar/MoleBarApp.swift` — currently does NOT import MoleBarCore (Phase 1 stub); Phase 2 will not yet require the app to import either, since MoleBarCore is exercised only via XCTests in Phase 2 (UI integration is Phase 3+)
- `mole-bundle/mole` (runtime artifact, gitignored) — inspect with `./scripts/bundle-mole.sh && less mole-bundle/mole` to see the actual upstream Shell wrapper that A9 observations were captured from

**External (planner may webfetch):**
- https://github.com/sparkle-project/Sparkle (no Phase 2 dep, but referenced by carry-forward)
- https://github.com/swiftlang/swift-subprocess (informational; SF-0037 review thread)
- https://github.com/jamf/Subprocess (informational; we deliberately did NOT pick this for v1)
- Foundation.Process documentation (Apple developer docs) — specifically `processGroupID`, launch attributes, terminationHandler

</canonical_refs>

<research_dependencies>

Items the researcher MUST verify before the planner commits to specific implementation details:

1. **`mole stats --json --watch` (or equivalent streaming flag) existence.** STATE.md "Blockers/Concerns" flags this as a Phase 2 spike. Without a streaming flag, `streamStats()` would have to poll mole on a fixed interval (different design). Verify against `mole-bundle/mole --help` and the upstream `tw93/mole` README at the pinned tag (V1.36.2).

2. **Foundation.Process process-group control on macOS 14+.** Does `Process` expose a `processGroupID` setter or `setpgid`-like attribute? If not, what's the cleanest path: (a) drop to `posix_spawn` with `POSIX_SPAWN_SETPGROUP` via a small C bridge, (b) a pre-exec wrapper script that runs `setpgid 0 0` and `exec`s mole, (c) wait for swift-subprocess 1.0. The choice affects D-25's implementation but not its semantics.

3. **Mole's env-var support for non-default paths.** Does `tw93/mole` honor `MOLE_CONFIG_DIR`, `MOLE_CACHE_DIR`, `MOLE_DISABLE_AUTO_UPDATE`? Inspect the Shell wrapper and any documented env-var contracts. If unsupported, the env-mask strategy may need alternatives (e.g., setting `XDG_CONFIG_HOME`, or running mole inside a temporary `HOME` overlay).

4. **`AnyCodable` implementation choice.** Hand-rolled (~30 LOC) is the default to avoid a third-party dep. If a maintained zero-dep snippet exists in Apple's sample code or Swift Forums, prefer it over rolling our own.

5. **Phase 2 streaming-subcommand scope.** Phase 2 ships the `MoleClient` actor + foundation, not all subcommands. Researcher proposes which subcommands to wrap in this phase to prove the pattern (recommend: `runVersion()` as a one-shot, plus one streaming method — `streamStats()` if `mole stats --watch` exists, else a poll-based `streamStats(interval:)` stub the planner explicitly flags as "non-streaming until Phase 5 confirms a real streaming source"). Other subcommands land in their feature phases.

</research_dependencies>

<code_context>

Reusable assets and patterns from earlier phases:

- **Empty target shape:** `Packages/MoleBarPackage/Sources/MoleBarCore/Placeholder.swift` exists with a `public enum MoleBarCore { static let phase1Placeholder = "phase-1" }`. Delete this when the first real symbol lands.
- **App target wiring:** `MoleBar.xcodeproj` already lists `MoleBarPackage`'s `MoleBarCore` product as a dependency (Plan 01-02). No project-level changes needed in Phase 2.
- **Swift 6 concurrency lesson (Plan 01-02 Deviation 1):** any code that observes a `@MainActor`-isolated property via `\.keyPath` must be `@MainActor`-annotated itself. `MoleBarCore` is server-side / actor-isolated, so this won't bite directly — but Phase 3's view-models will hit it again. Documented for Phase 3.
- **Logging pattern:** `Logger(subsystem: "app.molebar.MoleBar", category: "<area>")`. `MoleBarCore` uses category `"cli"`.
- **Bundled-mole runtime tree (gitignored):** `./scripts/bundle-mole.sh` produces `mole-bundle/` in 16 MB. Test fixtures in Phase 2 can use this tree directly via `mole-bundle/mole` for integration tests.
- **A9 observations table** (in `01-03-SUMMARY.md`): exact file:line references in `mole-bundle/mole` for absolute-path env handling. Planner reuses this.
- **Existing test infrastructure:** `MoleBarTests/MoleBarTests.swift` has a single placeholder `testTargetCompiles()`. Phase 2 fills this with the real test suite (process-group cancellation stress test, decoder fixtures, no-network XCTest, env-poisoning integration test).

</code_context>

<next_steps>

1. **`/clear`** to start a clean planner session.
2. **`/gsd-plan-phase 2`** — researcher will work through `<research_dependencies>` (items 1–5), then planner will write `02-XX-PLAN.md` files breaking the work into atomic tasks with the decisions above as locked inputs.
3. The planner is expected to break Phase 2 into roughly: PLAN-01 (subprocess wrapper foundation + env handling + path resolver), PLAN-02 (Codable model + MoleError + AnyCodable), PLAN-03 (cancellation + process-group + cancel-stress test), PLAN-04 (network-invariant build-time + runtime checks), PLAN-05 (CORE-07 nightly upstream-drift CI workflow), PLAN-06 (LICENSE-MOLE.txt + Resources wiring + final integration tests). Exact split is the planner's call.

Available alternatives:
- `--chain` for interactive discuss → auto plan+execute (skip — Phase 2 has real research questions worth pausing on)
- `/gsd-research-phase 2` then `/gsd-plan-phase 2 --skip-research` if you want to inspect research output before planning
- Edit this file before continuing — anything ambiguous?

</next_steps>
