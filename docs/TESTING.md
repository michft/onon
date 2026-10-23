# Testing and code changes

Adapted from the **Hit every surface**, **Test data**, **Verifying**, and
**Taste** sections of Even G2's `AGENTS.md`. This file defines Onon's testing
and change policy, available commands, physical acceptance checks, and dated
validation results. Select checks for the change; the full MVP checklist is
not a requirement for every change.

## Change the behavior at its owning boundary

- Keep complexity at adapter boundaries and domain logic pure where practical,
  in its owning module. HTTP handlers, UI components, and platform adapters
  should delegate to it instead of duplicating behavior.
- Keep changes narrow. Prefer inferred types and avoid `any`. Comments should
  explain a constraint or invariant, not narrate steps, restate names, or record
  change history.
- Preserve the product distinctions in [CONTEXT.md](CONTEXT.md), especially
  immutable Raw Recordings versus editable Trail Overlays. Never weaken
  immutability constraints to make a test or UI change pass.
- Check whether existing documentation becomes inaccurate. Update the affected
  guidance; do not add an implementation narrative for every change.

## Cover every affected surface

Before calling a behavior change done, identify which of these apply:

- **Entry points:** all controls and routes that reach the behavior, not just
  the button or screen used while developing it.
- **Clients:** the web workspace and native iPhone recorder. A shared feature
  needs an explicit decision for each affected client.
- **Contracts:** API schemas, persisted data, and client/server compatibility.
  Keep the API contract in project context and its consumers aligned.
- **Reverse states:** pause/resume, undo/redo, pairing/revocation, and
  interruption/recovery where the feature supports them.
- **Connection modes:** local access, remote access, offline operation,
  reconnect, repeated sync, and more than one device where relevant.
- **Output:** Screen, Blue-Light Print, and Greyscale Print Profiles, including
  actual paper output when the change affects print acceptance.

Report which surfaces were checked and which still need acceptance. A unit
test, browser capture, simulator run, and physical-device run prove different
things; do not substitute one for another.

## Run focused checks

- During iteration, run the smallest existing test file or named test that
  exercises the changed behavior. Extend existing tests before adding suites.
- Before delivery, run relevant package checks and affected-platform builds.
  Do not run repository-wide suites or typechecks unless the user requests
  them. Documentation-only changes need link/content checks, not app builds.
- Use the repo's `pnpm` scripts and installed tools. Do not introduce `vp`,
  `npx tsc`, or Even G2-specific lint rules and test helpers into Onon.

Examples from repository root:

```sh
pnpm --filter @onon/api test test/trail-edits.test.ts
pnpm --filter @onon/web test src/api.test.ts
pnpm --filter @onon/api typecheck
pnpm --filter @onon/web typecheck
```

For iOS checks, select an installed simulator by UDID and use workspace-local
DerivedData according to the workspace guide.
Use [physical acceptance](#physical-acceptance) for background
recording, offline field use, print scale, LED, and printer verification.

## Match proof to the bug

- Logic, data, state, and protocol bugs need the smallest regression test that
  fails for the original defect before the fix, then passes afterward.
- Backend behavior changes ship with focused tests. A backend-only fix with
  no visible surface also needs a short runtime transcript when runtime
  verification is part of the task.
- Purely visual bugs, such as spacing, color, alignment, or layout shifts,
  use before/after captures. Do not add UI tests solely for cosmetic details.
  State or interaction bugs still need behavioral regression coverage.
- Test meaningful logic or observable behavior. Do not assert static markup,
  callback wiring, or implementation details that merely repeat the code.

## Keep tests deterministic

- Await an observable completion signal, such as a resolved operation, a
  persisted result, or an event. Do not add sleeps or hand-written polling
  loops to wait for asynchronous work.
- Control clocks and timers when time is part of the behavior. Assert on
  events, values, and counts rather than wall-clock elapsed time.
- Do not increase per-test timeouts or add retries to conceal a race. Fix the
  synchronization or fixture. A skipped test needs a tracked reason.
- Use existing test and rendering helpers where available. Clean up mounted
  UI, timers, spies, mocks, and resources even when a test fails; reset shared
  mock state so tests do not depend on execution order.
- Browser assertions should wait for observable UI state. Do not synchronize
  tests through animation frames or transition-end events.

## Isolate realistic test data and shared resources

- Exercise realistic states and failure cases; an empty database is not enough
  for a feature that depends on existing recordings, pairing, or overlays.
- Use an isolated fixture or a copy of the necessary data. Never point tests
  at the live database, symlink mutable live data into fixtures, or copy test
  mutations back into the live store. Treat Raw Recordings as immutable.
- Bring secrets or settings into a fixture only when the flow requires them;
  keep them out of commits, captures, and reports.
- Follow the workspace guide for shared-resource ownership and process cleanup.

## Report the evidence

State the exact checks run, their results, the revision they cover, and any
remaining browser, native, device, or physical acceptance gaps. Record a
before/after result for a fix. Do not claim a build, install, launch, passing
test, or merge-ready PR without the corresponding evidence.

## Recorder publication validation — 2026-10-23 (Australia/Sydney)

- `pnpm typecheck` and `pnpm test` passed: API 6 tests, web 6 tests.
- API TypeScript and web production builds passed. Vite reports its existing
  large-chunk advisory.
- iOS simulator build and all 31 unit tests passed on iPhone 17 Pro Max,
  iOS 26.5. Regression coverage includes pause/finish races, sample and pause
  write failures, successful Pause/Resume/Finish transitions followed by read failures,
  stopped Finish retry after write failure or a concurrent refresh,
  suspended Resume superseded by Pause or successful/failed Finish,
  background refresh ordering, superseded sample-recovery alerts, and startup
  recovery protected from early sync, transition refresh retried after concurrent sync,
  explicit pairing approval, local-origin restrictions, and redirect rejection.
- Ten recovery regressions failed before their corresponding fixes, then
  passed after reconciling persisted state, ordering refresh publication and
  retaining explicit Finish retry identity.
- iOS Release build for generic physical iPhone architecture passed with code
  signing disabled; this is build evidence, not device installation or field
  acceptance.
- Shell syntax checks, all three map-style JSON parses, and six cache-selection
  checks passed; empty PBF files are skipped without rejecting empty OCI markers.
- Simulator screenshots in `docs/images/` show the bundled map, recording
  diagnostics, waypoint menu, destination approval, restored Server/QR navigation,
  and stopped Finish retry. Scanner presentation was checked; physical QR
  decoding remains unverified because the simulator has no camera.
  GPS fixes and the temporary Finish-write fault were simulated; the fault was
  removed after verifying successful retry.
- Shared containers were not restarted or rebuilt. Physical GPS/background
  capture, real-laptop pairing/upload, and paper checks were not repeated.

## Completed machine validation — 2026-07-21

These are historical results, not evidence for the current revision.

- Apple ARM64 container image pulls and application image build passed.
  PostgreSQL 17, TileServer GL 5.6, Planetiler 0.10.1, and Web/API ran as ARM64
  Apple containers.
- Sydney map build passed: bounds `151.00,-34.04,151.33,-33.70`, zoom 0–14,
  451 vector tiles, 22 MB, with a version manifest and atomic active symlink.
- Live pairing, token exchange, idempotent upload, immutable raw samples,
  Trail Overlay derivation, bad-section removal, undo/redo, waypoint add/move,
  Direction Arrow add/move/flip, manifest delivery, and PDF export passed.
- The 20 GB Apple-managed PostgreSQL volume retained data through restart;
  backup, staged restore, and clean bootstrap passed.
- All three web profiles rendered from local vector tiles in a real browser.
  Local styles, tiles, and fonts returned 200 with no console errors/warnings.
- Three generated PDFs were confirmed as single-page A4 portrait/landscape and
  rendered to PNG for visual inspection after the final legend change. All
  profiles included Trail, circle-dot Waypoint, Direction Arrow, legend, scale
  bar, north arrow, and attribution.
- Swift packages resolved; the SwiftUI app built, installed, and launched in
  the simulator. SQLite migration and paused-recording write protection passed;
  background-location declarations and MapLibre runtime linkage were verified.
  API tests: 6. Web tests: 4. iOS tests: 6.
- Machine fixtures were removed, leaving the application database clean at the
  time. Physical iPhone lock/sleep, airplane-mode field use, and paper/LED
  acceptance remained pending.

## Automated and machine checks

The full MVP checklist below is available when repository-wide validation is
requested. For ordinary changes, follow the focused-check policy above and
select only the relevant commands. Run commands from repository root:

```sh
pnpm install --frozen-lockfile
pnpm typecheck
pnpm test
pnpm --filter @onon/web build
pnpm --filter @onon/api build
bash -n scripts/*.sh
bash scripts/test-refresh-cache.sh
jq empty infra/tileserver/config.json infra/tileserver/smoke-config.json infra/tileserver/styles/*.json
```

iOS:

```sh
scripts/prepare-ios-map.sh
xcodebuild -project apps/ios/Onon.xcodeproj -scheme Onon \
  -derivedDataPath .local/DerivedData \
  -destination 'id=<simulator UDID>' test
```

Select an installed simulator UDID with `xcrun simctl list devices available`;
follow the workspace guide before using shared devices.
Package resolution, simulator build/install/launch, all unit tests, SQLite
migrations, background location declarations, and MapLibre runtime linkage
must pass.

Apple Container Phase 0 covers ARM64 image availability, Planetiler startup,
managed PostgreSQL-volume persistence through container recreation, vector tile
serving, all three styles, and a `2480x3508` A4 raster render.

## Physical acceptance

These require target hardware/materials and cannot be proved by simulator:

- Install through Xcode on target iPhone.
- Record outdoors for at least ten minutes with iPhone locked.
- Pause, resume, force-close/reopen recovery, and finish confirmation.
- Download overview/detail areas, record in airplane mode, then sync later.
- Retry same sync and confirm one Raw Recording exists.
- Print A4 at each recommended scale; measure scale and crop.
- Review blue-light profile under target LED light.
- Print greyscale profile on target greyscale printer and confirm classes remain distinct.

Record printer, paper, LED, iPhone/iOS, and observed failures before changing
fixed profiles or background-location policy.

## Implementation conventions

- Keep client mutations behind the owning API client and authorization on the
  server. UI availability is not an authorization check. Extend rejection and
  permission tests when changing a protected operation.
- Server features belong in domain modules or services. A transport handler
  decodes input, calls the owning behavior, and maps results or errors; avoid
  embedding business rules in HTTP routes.
- Reusable UI components own their look. Use existing variants or extend them
  for a reusable concept; keep feature-specific appearance in that feature.
  Layout belongs on the parent rather than in unrelated component overrides.
- Follow existing tracing and logging conventions, keeping useful operation
  names stable. Do not add framework-specific helpers solely to imitate another
  repository.
- Respect frame time and battery use. Avoid continuously repainting animations
  or unnecessary map redraws; a stale status or dropped frame is a product bug.

PRs that change layout, UI, or product flow include images or videos. Organize
PRs around requested merge groups; stack dependent groups rather than opening
one PR per finding by default.

## Protomaps trial checks

Run `pnpm --filter @onon/web typecheck`, `pnpm --filter @onon/web test -- src/protomaps-style.test.ts` and `bash -n scripts/{download,start}-protomaps-trial.sh`. The starter performs the trial production build. The regression test evaluates MapLibre filters for streets, both carriageways, paths, tunnels, ferries and labels.

The viewer's Content Security Policy restricts map connections and images to local resources. Verify a fresh browser load, then pan, zoom and switch CBD/harbour/park scenes with no failed requests. This proves independence from external services while the local servers run. It does not prove airplane-mode operation on iPhone or browser caching after the servers stop.
