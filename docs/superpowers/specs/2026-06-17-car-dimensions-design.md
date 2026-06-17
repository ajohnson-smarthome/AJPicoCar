# Car Dimensions («Размеры машинки»)

**Date:** 2026-06-17
**Branch:** new feature branch off `main`
**Scope:** firmware (new `/dims` endpoint) + iOS (new screen, wizard step, donut/sim track integration).

## Problem

The differential-drive math assumes a fixed **track** (lateral distance between left/right wheel
centres) hardcoded as `Tricks.donutTrackM = 0.13` (130 mm). It drives turn rate
(`ω = (vR − vL)/track`), the donut diameter solver (`donutSides`), and the donut duration
(`donutDurationMs`). If a user's real car has a different track, turn radius, the solved donut, and
the simulation are all off. There is also no place to record the car's physical dimensions.

## Goal

Add a **«Размеры машинки»** screen where the user enters the two distances **between wheel
centres** — **колея** (track, lateral) and **база** (wheelbase, longitudinal). The values are stored
on the car (firmware `/dims`, mirroring `/wheel`). The screen is a **mandatory step 1** of the
initial-setup wizard (before «Колесо и моторы») and a Settings row above «Колесо и моторы». The
measured **track** replaces the hardcoded constant in the donut/simulation math; **wheelbase** is
stored and drawn on the screen's own diagram only (it does not affect tank-drive kinematics).

## What each value drives

- **Track (колея)** — the differential-drive parameter. Feeds `TrickSim.simulate(trackM:)` and the
  pure donut geometry (`donutSides`, `donutDurationMs`). Smaller track → tighter turns.
- **Wheelbase (база)** — does NOT affect tank-drive turn radius. Stored + shown on the dimensions
  diagram only. (No change to the simulation's drawn car body — `carLenM`/`carWidM` stay fixed.)

## The `0.13` fallback

`0.13` stops being an authoritative constant. The pure donut functions take `trackM` as a
**required parameter** (no hidden default). One named constant `Tricks.donutTrackFallbackM = 0.13`
remains, used **only at the fetch sites** (`await DimsClient().get()?.trackM ?? Tricks.donutTrackFallbackM`)
as the assumed track while `/dims` is unavailable (pre-fetch, offline, no mock). It equals the
firmware default (track 130 mm → 0.13 m), so default behaviour is identical to today.

## Components

### Firmware (mirror of `wheel` / `wheel_api`)

`main/dims.{c,h}`:
```c
#define DIMS_TRACK_MIN_MM      60
#define DIMS_TRACK_MAX_MM      300
#define DIMS_WHEELBASE_MIN_MM  90
#define DIMS_WHEELBASE_MAX_MM  360
typedef struct { uint16_t track_mm; uint16_t wheelbase_mm; } dims_params_t;
void dims_init(void);                  // load NVS or defaults (track 130, wheelbase 210)
void dims_get(dims_params_t *out);
void dims_set(const dims_params_t *in);// validate/clamp + store in RAM (the API persists to NVS)
```

`main/dims_api.{c,h}`: `dims_api_start()` registers `GET /dims` → `{"track_mm":130,"wheelbase_mm":210}`
and `POST /dims` (two space-separated ints `"130 210"`, NVS-persisted), on the shared httpd. In
`app_main`: `dims_init()` right after `wheel_init()`; `dims_api_start()` right after
`wheel_api_start()`. Handler count 15 → **17/20** (GET+POST). Requires a board re-flash.

### iOS

- `ios/ESP32Car/DimsClient.swift` — `struct Params { var trackMm: Int; var wheelbaseMm: Int }`,
  `get() async -> Params?`, `set(_:) async -> Bool` (GET JSON / POST two space ints). Mirror of
  `WheelClient`.
- `ios/ESP32Car/CarDimensionsView.swift` — split-layout screen (own header, nav bar hidden, like
  `WheelParamsView`). Left: the animated diagram. Right: two stepper rows — «Колея» (поперёк) and
  «База» (вдоль), mm, step 5, − / value / +. `var wizard: Bool = false`. Wizard header shows the
  step indicator; «Далее» pushes `WheelParamsView(wizard: true)`. Non-wizard header shows a back
  chevron. Loads `/dims` on `.task`; saves on stepper change with `lastSaved` de-dup (like
  `WheelParamsView`).
- `ios/ESP32Car/CarDimsDiagram.swift` — a `Canvas` (or `TimelineView`-free static `Canvas`) drawing
  the **reference car** (the `DriveDiagram` silhouette: body proportions `36×74`, corner radius
  ≈ 0.3·width, dark `12×20` wheels with a chevron tread poking out laterally, windshield strip at the
  front) sized from `track`/`wheelbase`, plus the two dimension lines + «Колея N мм» / «База N мм»
  labels between the wheel centres. Wheels/body animate when a value changes
  (`.animation(.easeInOut(duration: 0.28), value: track)` etc.). At the defaults (130/210) the car
  matches the reference silhouette.

### Localization

- `dims.title` = «Размеры машинки», `dims.track` = «Колея», `dims.base` = «База»,
  `dims.trackHint` = «поперёк», `dims.baseHint` = «вдоль». `L.mmUnit` already exists.
- The wizard step indicator becomes generic: rename `wheel.step`/`L.wheelStep` →
  `wizard.step`/`L.wizardStep` (string unchanged: «Шаг %d из %d»), used by both
  `CarDimensionsView` (`L.wizardStep(1, 3)`) and `WheelParamsView` (now `L.wizardStep(2, 3)`).

### Wizard + Settings wiring

- `DriveView`: the mandatory sheet changes from `NavigationStack { WheelParamsView(wizard: true) }`
  to `NavigationStack { CarDimensionsView(wizard: true) }`. Chain: **Размеры (1/3) → Колесо и моторы
  (2/3) → Калибровка (3/3)**. Same gate (`calibrated == false`). Calibration keeps its own internal
  step labels (no wizard «3/3» badge — matches the current loose pattern).
- `SettingsView`: in section «Настройка машины», add a row **«Размеры машинки»** (SF Symbol `ruler`)
  **above** the «Колесо и моторы» row.

### Donut / simulation track integration (`Tricks`, `TrickSimView`, `DriveView`, `TrickEditorView`)

- `Tricks.swift`: replace the `donutTrackM` constant with `donutTrackFallbackM = 0.13`. The pure
  functions take `trackM` explicitly:
  - `donutSides(diameterCm:trackM:)`
  - `donutDurationMs(circles:y:vmaxMS:trackM:)`
  - `donutTrick(diameterCm:trackM:)` and `donutTrick(diameterCm:circles:vmaxMS:trackM:)`
  Host tests updated to pass `trackM`; add a track-sensitivity test (a smaller track → a different
  side ratio / a tighter solved radius for the same diameter).
- `TrickSimView`: fetch `/dims` into a `@State track: Double` (fallback `donutTrackFallbackM`). Pass
  it to `TrickSim.simulate(trackM:)`. The donut step is built inside the view from
  `donutDiameterCm` + `donutCircles` + `track` + `vmaxMS` (the editor passes the diameter and circle
  **values**, not a pre-built trick; `trick: Tricks.donut` supplies id/name/icon).
- `DriveView.startTrick`: add `donutTrackM() async -> Double` (mirror of `donutVmaxMS()`, fetches
  `/dims`, fallback `donutTrackFallbackM`); build `donutTrick(diameterCm:circles:vmaxMS:trackM:)`.
- `TrickEditorView`: pass `donutDiameterCm: Double(diameterCm)` + `donutCircles: circles` to
  `TrickSimView` instead of `Tricks.donutTrick(diameterCm:)`.

### Mock car

`tools/mock_car/mock_car.py`: add `GET /dims` → `{"track_mm":130,"wheelbase_mm":210}` and `POST
/dims` (echo/store), so the simulator drives the screen and the donut sim computes with a real track.

## Testing

- **iOS pure (swiftc):** update the donut host tests to pass `trackM`; assert track-sensitivity
  (e.g. `donutSides(50, trackM: 0.10).y != donutSides(50, trackM: 0.13).y`, and the round-trip
  radius tracks the supplied `trackM`). `donutDurationMs` scales linearly with `trackM`.
- **iOS build:** `xcodebuild` simulator build succeeds; screenshot `CarDimensionsView` (wizard step 1)
  showing the reference car + «Колея»/«База» steppers, and confirm − / + animates the wheels.
- **Firmware:** compiles; `GET /dims` returns the JSON, `POST /dims` clamps + persists (verified on
  device when a board is flashed — out of band for the simulator workflow).

## Out of scope

- Wheelbase affecting the simulation drawing or kinematics (track-only integration).
- On-board speed/odometry. Editable per-wheel offsets. Imperial units.
