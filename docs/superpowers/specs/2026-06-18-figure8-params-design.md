# Figure-8 trick: loop diameter + number of eights (donut-analog)

**Date:** 2026-06-18
**Branch:** `feat/figure8-params` off `main`
**Scope:** iOS-only. No firmware change.

## Problem

The «Восьмёрка» (figure-8) trick is two fixed arcs: `{t:0.6, y:0.6, ms:2500}` then `{t:0.6, y:-0.6,
ms:2500}`. By analogy with the recently-shipped adjustable donut (diameter + circle count) and spin
(turns + duration), the figure-8 should expose editable geometry with a live preview.

## Goal

Replace the figure-8's fixed arcs with two editable parameters — **loop diameter** (cm) and **number of
eights** (count) — and derive the streamed timeline at full motor power, exactly like the donut. The
preview simulation and the streamed maneuver both use the derived timeline. iOS-only.

## Model

A figure-8 = two tangent circles traversed in opposite turn directions. Each lobe is a **full circle**,
identical to one donut loop:

- `(t, y) = Tricks.donutSides(diameterCm:trackM:)` — the inverse side-ratio solver gives the arc command
  (fast wheel full, slow wheel ratio set so the turn radius = diameter/2).
- `lobeMs = Tricks.donutDurationMs(circles: 1, y: y, vmaxMS:, trackM:)` — duration of one full circle.
- The timeline: for each of `eights` repetitions, two steps `[{t, y, lobeMs}, {t, −y, lobeMs}]` — the
  left loop, then the mirror right loop. Speed is **not** an input — motors run at full power and the
  duration is derived (like the donut). So a bigger loop or more eights = a longer maneuver.

`vmaxMS = π·D·rpm/60` (wheel diameter + rated motor rpm) and `track` come from the same sources as the
donut: `/wheel` + `MotorPresets` for vmax, `/dims` for track, with the existing fallbacks
(`Tricks.donutNominalVmaxMS = 0.578`, `Tricks.donutTrackFallbackM = 0.13`).

**Contrast with the donut:** the donut is one loop direction repeated `circles` times; the figure-8 is a
left loop + right loop pair repeated `eights` times. Both derive duration at full power and reuse the
same `donutSides`/`donutDurationMs` helpers.

## Components (mirror the donut)

### `Tricks.swift` (pure, host-tested) — additive

```swift
// Figure-8: loop diameter + eights count. Each lobe is a full donut circle; the second lobe flips y.
static let fig8DiaMinCm = 20, fig8DiaMaxCm = 150, fig8DiaDefaultCm = 50
static let fig8EightsMin = 1, fig8EightsMax = 10, fig8EightsDefault = 1

/// The figure-8 maneuver: `eights` repetitions of {left loop, right loop}, each a full circle of the
/// given diameter at speed `vmaxMS`. (t, y) from `donutSides`; per-lobe ms from `donutDurationMs(circles:1)`.
/// Keeps the figure8 id/name/icon. Degenerate speed/shape → a single zero-length step (no crash).
static func figure8Trick(diameterCm: Double, eights: Int, vmaxMS: Double, trackM: Double) -> Trick
```

Implementation: compute `(t, y) = donutSides(...)`, `lobeMs = donutDurationMs(circles: 1, y: y, ...)`,
then `steps = (0..<max(fig8EightsMin, eights)).flatMap { _ in [TrickStep(t: t, y: y, ms: lobeMs),
TrickStep(t: t, y: -y, ms: lobeMs)] }`. The existing `Tricks.figure8` constant stays (id/name/icon + list).

### `TrickSettings.swift` — persist the two params

```swift
static func fig8Dia() -> Int             // clamped 20–150, default 50
static func setFig8Dia(_ cm: Int)
static func resetFig8Dia()
static func fig8Eights() -> Int          // clamped 1–10, default 1
static func setFig8Eights(_ n: Int)
static func resetFig8Eights()
```

Keys `trick.fig8.dia` and `trick.fig8.eights`. The figure-8 no longer uses the generic per-action durations.

### `TrickSimView.swift` — figure-8-aware preview

A new optional input pair `fig8Dia: Double? = nil`, `fig8Eights: Int? = nil` (alongside the existing
donut/spin inputs). In `steps`, when the trick is `Tricks.figure8`, both params are set, and `vmaxMS` is
available, build the timeline via `Tricks.figure8Trick(diameterCm:eights:vmaxMS:trackM:)` (track from the
already-fetched `/dims`). The simulation renders a proper "8" (the centre path crosses itself); the
«оборотов» stat reads `turnRad/2π ≈ 2·eights` (each lobe is one full turn, accumulated as |heading|).

### `TrickEditorView.swift` — figure-8 editor branch

Like the donut branch: for `trick.id == Tricks.figure8.id`, a `ScrollView` with `TrickSimView(...)`
(passing `fig8Dia`/`fig8Eights`) + a card holding two stepper rows:
- **«Диаметр петли»** — a − / N cm / + stepper (20–150, step matches the donut's diameter stepper),
  persisting via `TrickSettings.setFig8Dia`.
- **«Восьмёрок»** — a − / N / + stepper (1–10), persisting via `TrickSettings.setFig8Eights`.

No «Всего» footer (the duration shows in the sim caption). Non-donut/non-spin/non-figure8 tricks keep
`controls`.

### `DriveView.swift` — stream the figure-8 from the stored params

In `startTrick`, for the figure-8: fetch `vmax` (`donutVmaxMS()`) and `track` (`donutTrackM()`), build
`Tricks.figure8Trick(diameterCm: Double(TrickSettings.fig8Dia()), eights: TrickSettings.fig8Eights(),
vmaxMS:, trackM:)`, and stream it (with the same `Task.isCancelled` guard already in place). Other tricks
unchanged.

### Localization

Two dedicated keys (the donut's `sim.diameter` reads «Диаметр круга», so the figure-8 gets its own
«Диаметр петли»):
- `L.fig8Diameter` → `"trick.fig8Diameter" = "Диаметр петли";`
- `L.fig8Loops` → `"trick.fig8Loops" = "Восьмёрок";`

## Testing

Host tests (`swiftc`) in `TrickSimTests` (driver named `main.swift`):
- `figure8Trick` geometry: `(t, y)` of the first step equals `donutSides(diameterCm:trackM:)`; the step
  count is `2·eights`; consecutive lobes alternate the sign of `y` (`steps[0].y == −steps[1].y`), and `t`
  is constant and positive.
- `figure8Trick` keeps `Tricks.figure8.id`.
- Degenerate: `vmaxMS ≤ 0` → steps with `ms == 0` (no crash, no divide-by-zero).
- Round-trip via the simulation: `figure8Trick(...)` simulated → `turnRad/2π ≈ 2·eights` (within a small
  tolerance) and the centre path returns near its start (figure-8 closes: bbox spans ≈ two loops, net
  displacement small).

Build: `xcodebuild` succeeds; screenshot the figure-8 editor showing the "8" animation + «Диаметр петли»
stepper + «Восьмёрок» stepper, with the caption reading the duration/turn count.

## Out of scope

- First-loop direction (CW vs CCW) — stays the current single orientation.
- Asymmetric lobes (different diameters per loop).
- Other tricks, firmware.
