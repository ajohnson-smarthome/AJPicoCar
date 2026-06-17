# Donut: Number of Circles (instead of duration)

**Date:** 2026-06-17
**Branch:** `feat/trick-sim` (continuation of the donut-diameter feature)
**Scope:** iOS-only. No firmware change.

## Problem

The donut trick is currently timed: the editor exposes a **duration** slider (the
generic per-action slider) and the streamed step carries a fixed `ms`. But for a
*donut* the natural parameter is **how many circles** the car does, not how many
seconds it spins. Number of circles and duration are rigidly linked through the
diameter (which sets the side ratio) and the motor speed, so duration can be
replaced by a circle count and the duration back-computed.

## Goal

Replace the donut's editable duration with an integer **circle count** (1–10, step 1,
default 2), entered via a stepper (− / N / +). The chosen count back-solves the
streamed step duration; both the simulation preview and the real streamed maneuver
derive their duration from the same circle count.

## Math

For the donut, `donutSides(diameterCm:)` fixes the side ratio:
- outer (left) wheel full: `left = 1`
- inner (right) wheel: `right = r`, with `y = (1 − r) / 2`

Heading rate (differential drive): `ω = vmax·(left − right)/track = vmax·2y/track`.
To sweep `N` full circles (`N·2π` radians):

```
t      = N·2π·track / (vmax·2y) = N·π·track / (vmax·y)
ms     = 1000 · N · π · donutTrackM / (vmaxMS · y)
vmaxMS = π · D · rpm / 60        (D = wheel diameter m, rpm = rated motor RPM)
```

`y ∈ [0.05, 0.5]` (since `r ∈ [0, 0.9]`), so it is never zero. Guard `vmax > 0`.

Sanity check (50 cm diameter, default motor 170 rpm / 65 mm wheel):
`r ≈ 0.587`, `y ≈ 0.206`, `vmax ≈ 0.578 m/s`, `N = 2` → `ms ≈ 6860` (≈3.4 s/circle).
Consistent with today's "1.5 circles in 5.0 s".

## Key invariant

The simulation and the real stream **must compute `ms` with the same `vmax`**. Then
the simulation always renders exactly `N` circles, regardless of which motor is
configured — the diameter sets the shape, the circle count sets the sweep, and `vmax`
cancels out of the visible result. This is an open-loop system: on real hardware the
actual circle count drifts with battery voltage, exactly as the previous time-based
donut did. No new inaccuracy is introduced; the framing is just more intuitive.

## Components

### `Tricks.swift` (pure, host-tested) — additive

```swift
static let donutCirclesMin = 1, donutCirclesMax = 10, donutCirclesDefault = 2
/// Nominal speed fallback (default motor JGA25-370 ~170 rpm, 65 mm wheel) when /wheel
/// is unavailable, so a circle count still maps to *some* duration.
static let donutNominalVmaxMS = 0.578

/// Streamed duration (ms) for `circles` full circles of a donut whose inner-wheel
/// term is `y`, at linear speed `vmaxMS`. Pure inverse of the simulation's sweep.
static func donutDurationMs(circles: Int, y: Double, vmaxMS: Double) -> Int

/// The donut maneuver sized to a diameter AND timed to a circle count.
static func donutTrick(diameterCm: Double, circles: Int, vmaxMS: Double) -> Trick
```

Existing `donutSides(diameterCm:)`, `donutTrick(diameterCm:)`, `donutTrackM`,
`donutDia*` are untouched (the no-circles `donutTrick(diameterCm:)` stays as the
editor's "base" trick fed to the simulation, whose `ms` the sim overrides).

### `TrickSettings.swift` — persist circle count

```swift
static func donutCircles() -> Int          // clamped 1–10, default 2
static func setDonutCircles(_ n: Int)
static func resetDonutCircles()
```

Key `trick.donut.circles`. The donut no longer reads/writes the generic per-action
durations.

### `TrickSimView.swift` — circle-aware donut sim

- New optional parameter `donutCircles: Int? = nil` (default keeps all other tricks
  unchanged).
- Extract `vmaxMS` into a computed property (currently inline in `sim`).
- In `steps`, when `donutCircles != nil`, the trick is the donut, the step count is 1,
  and `vmaxMS` is available, override the single step's `ms` with
  `Tricks.donutDurationMs(circles:y:vmaxMS:)`. When `vmaxMS` is nil (wheel not yet
  loaded / no motor match) the base `ms` is used and the stats already read "—".
- The sim caption ("За X с — N оборотов") already surfaces both the duration and the
  circle count, so no separate total is needed for the donut.

### `TrickEditorView.swift` — stepper replaces duration slider (donut only)

- New `@State private var circles = Tricks.donutCirclesDefault`; load
  `TrickSettings.donutCircles()` in `.onAppear`.
- Feed `donutCircles: circles` into `TrickSimView`.
- Donut card = `diameterRow` (slider, unchanged) + separator + **`circlesRow`**
  (a stepper: label «Круги», − button, value, + button, reset). Replaces the
  per-action duration `ForEach(row(i))` block for the donut.
- Drop the «Всего» footer for the donut (duration is shown in the sim caption).
- Non-donut tricks keep the existing `controls` (duration list) untouched.
- `circlesRow` clamps to 1–10 and persists via `TrickSettings.setDonutCircles`;
  reset returns to the default and `resetDonutCircles()`.

### `DriveView.swift` — stream the donut at the chosen circle count

In `startTrick`, for the donut: fetch `/wheel` (`WheelClient().get()`), derive `vmax`
(`MotorPresets.match(...)?.rpm` → `π·D·rpm/60`), falling back to
`Tricks.donutNominalVmaxMS` when params/rpm are missing; build
`Tricks.donutTrick(diameterCm:circles:vmaxMS:)` from the stored diameter + circles and
stream it. Other tricks use their base as today.

## Localization

`L.simCircles` → `"sim.circles" = "Круги";` (the stepper label). The sim's "оборотов"
stat strings already exist.

## Testing

Host tests (`swiftc`) in `TrickSimTests`:
- `donutDurationMs` round-trip: for a few diameters and circle counts, simulate the
  resulting step and assert the swept revolutions ≈ the requested count.
- Default case: `donutDurationMs(circles: 2, y: donutSides(50).y, vmaxMS: 0.578)` ≈ 6860 ms.
- Guards: `vmaxMS ≤ 0` or `y ≤ 0` → 0; `circles` below 1 treated as 1.
- `donutTrick(diameterCm:circles:vmaxMS:)` keeps the donut id/name/icon and one step.

Build: `xcodebuild` simulator build succeeds; screenshot the donut editor showing the
diameter slider + circle stepper, and the sim caption reading the requested count.

## Out of scope

Other tricks, firmware, editable track width, fractional circles.
