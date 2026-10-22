# Testing and code changes

Adapted from the **Hit every surface**, **Test data**, **Verifying**, and
**Taste** sections of Even G2's `AGENTS.md`. This file defines Onon's testing
and change policy, available commands, physical acceptance checks, and dated
validation results. Select checks for the change; the full MVP checklist is
not a requirement for every change.

## Change the behavior at its owning boundary

- Keep domain logic in its owning module. HTTP handlers, UI components, and
  platform adapters should delegate to it instead of duplicating behavior.
- Keep changes narrow. Prefer inferred types and avoid `any`. Comments should
  explain a constraint or invariant, not narrate the implementation.
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
  Keep the [API contract](API_CONTRACT.md) and its consumers aligned.
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
DerivedData as described in the [workspace guide](WORKTREE.md).
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
- Follow [workspace ownership](WORKTREE.md) for local containers,
  ports, servers, simulators, and physical devices. Do not start or stop shared
  infrastructure without authorization. Stop only processes you started,
  using the PID captured at startup, never a name or path pattern.

## Report the evidence

State the exact checks run, their results, the revision they cover, and any
remaining browser, native, device, or physical acceptance gaps. Record a
before/after result for a fix. Do not claim a build, install, launch, passing
test, or merge-ready PR without the corresponding evidence.

## Recorder publication validation — 2026-10-23

- `pnpm typecheck` and `pnpm test` passed: API 6 tests, web 6 tests.
- API TypeScript and web production builds passed. Vite reports its existing
  large-chunk advisory.
- iOS simulator build and all 26 unit tests passed on iPhone 17 Pro Max,
  iOS 26.5. Regression coverage includes pause/finish races, sample and pause
  write failures, successful Pause/Resume/Finish transitions followed by read failures,
  stopped Finish retry after write failure or a concurrent refresh,
  explicit pairing approval, local-origin restrictions, and redirect rejection.
- All five state-transition recovery regressions failed against the previous Resume
  implementation, then passed after reconciling persisted state and retaining explicit Finish retry identity.
- iOS Release build for generic physical iPhone architecture passed with code
  signing disabled; this is build evidence, not device installation or field
  acceptance.
- Shell syntax checks and all three map-style JSON parses passed.
- Simulator screenshots in `docs/images/` show the bundled map, recording
  diagnostics, waypoint menu, destination approval, and stopped Finish retry.
  GPS fixes and the temporary Finish-write fault were simulated; the fault was
  removed after verifying successful retry.
- Shared containers were not restarted or rebuilt. Physical GPS/background
  capture, real-laptop pairing/upload, and paper checks were not repeated.

## Completed machine validation — 2026-07-21

- Apple ARM64 container image pulls and application image build passed.
- Sydney map build passed: bounds `151.00,-34.04,151.33,-33.70`, zoom 0–14,
  451 vector tiles, with version manifest and active symlink.
- Live pairing, idempotent upload, Trail Overlay editing, raw-data immutability,
  map manifest, and three-profile PDF export passed.
- PostgreSQL managed-volume restart persistence, backup, staged restore, and
  fresh-database bootstrap passed.
- Browser rendering passed for screen, blue-light paper, and greyscale paper;
  local styles, tiles, and fonts returned 200 with no console errors/warnings.
- Three generated PDFs were confirmed as single-page A4 portrait/landscape and
  rendered to PNG for visual inspection after the final legend change.
- API tests: 6. Web tests: 4. iOS tests: 6.

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
jq empty infra/tileserver/config.json infra/tileserver/smoke-config.json infra/tileserver/styles/*.json
```

iOS:

```sh
xcodebuild -project apps/ios/Onon.xcodeproj -scheme Onon \
  -derivedDataPath .local/DerivedData \
  -destination 'id=<simulator UDID>' test
```

Select an installed simulator UDID with `xcrun simctl list devices available`;
follow [workspace ownership](WORKTREE.md) before using shared devices.
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
