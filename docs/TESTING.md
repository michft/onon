# MVP validation

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

From repository root:

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
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
```

Exact simulator names vary by installed Xcode runtime. Package resolution,
simulator build/install/launch, all unit tests, SQLite migrations, background
location declarations, and MapLibre runtime linkage must pass.

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
