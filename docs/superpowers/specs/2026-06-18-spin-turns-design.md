# Spin trick: turns + duration (derived speed)

**Date:** 2026-06-18
**Branch:** new feature branch off `main`
**Scope:** iOS-only. No firmware change.

## Problem

The «Разворот» (spin) trick is a fixed in-place pivot: a single step `{t:0, y:1, ms:5000}`. By analogy with
the recently-shipped adjustable donut (diameter slider + circle-count stepper), the spin should expose
editable parameters with a live preview.

## Goal

Replace the spin's fixed duration with two editable parameters — **number of turns** (целых, 1 turn = 360°)
and **total duration** (s) — and derive the **spin speed** so the maneuver does N full rotations in T seconds.
The preview simulation and the streamed maneuver both use the derived speed. iOS-only.

## Model

The spin command is `t = 0, y = spinY` (pivot in place). For `y ≤ 1` the wheel speeds are `vL = y·vmax`,
`vR = −y·vmax`, so the heading rate is `ω = (vR − vL)/track = 2·y·vmax/track`. To sweep `N` full turns
(`N·2π` rad) in `T` seconds, the required rate is `ω = N·2π/T`, giving:

```
spinY = N·π·track / (T·vmaxMS)      clamped to (0, 1]
```

`vmaxMS = π·D·rpm/60` (wheel diameter + rated motor rpm) and `track` come from the same sources as the
donut: `/wheel` + `MotorPresets` for vmax, `/dims` for track, with the existing fallbacks
(`Tricks.donutNominalVmaxMS = 0.578`, `Tricks.donutTrackFallbackM = 0.13`). The streamed/simulated step is
`{t: 0, y: spinY, ms: T·1000}`.

**Contrast with the donut:** the donut takes diameter + circles and *derives the duration* (motors at full
power); the spin takes turns + duration and *derives the speed* — so the same N turns can be a slow, stately
spin (long T) or a brisk one (short T).

**Feasibility / clamp:** if `T` is too short for `N` turns at full power (`spinY > 1`), the speed clamps to 1 —
the maneuver spins at maximum and completes fewer than `N` turns within `T`. The **simulation shows the actual
result** (the «оборотов» stat + «За T с — X.X оборота» caption), exactly like the donut: the sim is the
feedback loop. In the common range `spinY < 1` and the sim shows exactly `N`.

## Components (mirror the donut)

### `Tricks.swift` (pure, host-tested) — additive

```swift
static let spinTurnsMin = 1, spinTurnsMax = 6, spinTurnsDefault = 2
static let spinDurMinMs = 1000, spinDurMaxMs = 10000, spinDurDefaultMs = 3000

/// Derived yaw magnitude (0,1] for N full in-place turns in `durationMs` at speed `vmaxMS` / `trackM`.
/// 0 if inputs are degenerate. spinY = N·π·track / (T·vmax), clamped.
static func spinSpeed(turns: Int, durationMs: Int, vmaxMS: Double, trackM: Double) -> Double

/// The spin maneuver: one step {t:0, y: spinSpeed(...), ms: durationMs}. Keeps the spin id/name/icon.
static func spinTrick(turns: Int, durationMs: Int, vmaxMS: Double, trackM: Double) -> Trick
```

The existing `Tricks.spin` constant stays (used for id/name/icon and the trick list).

### `TrickSettings.swift` — persist the two params

```swift
static func spinTurns() -> Int            // clamped 1–6, default 2
static func setSpinTurns(_ n: Int)
static func resetSpinTurns()
static func spinDurMs() -> Int            // clamped 1000–10000, default 3000
static func setSpinDurMs(_ ms: Int)
static func resetSpinDurMs()
```

Keys `trick.spin.turns` and `trick.spin.durMs`. The spin no longer uses the generic per-action durations.

### `TrickSimView.swift` — spin-aware preview

A new optional input pair `spinTurns: Int? = nil`, `spinDurMs: Int? = nil` (alongside the existing
`donutDiameterCm`/`donutCircles`). In `steps`, when the trick is `Tricks.spin`, both spin params are set, and
`vmaxMS` is available, build the single step via `Tricks.spinTrick(turns:durationMs:vmaxMS:trackM:)` (track from
the already-fetched `/dims`). The simulation renders an in-place rotation (centre velocity ≈ 0, `turnRad`
accumulates), so the «оборотов» stat reads the achieved turn count and the caption shows the duration.

### `TrickEditorView.swift` — spin editor branch

Like the donut branch: for `trick.id == Tricks.spin.id`, a `ScrollView` with `TrickSimView(...)` (passing
`spinTurns`/`spinDurMs`) + a card holding two rows:
- **«Развороты»** — a − / N / + stepper (1–6), persisting via `TrickSettings.setSpinTurns`.
- **«Продолжительность»** — a slider (1.0–10.0 s, step 0.5), persisting via `TrickSettings.setSpinDurMs`.
No «Всего» footer (the duration shows in the sim caption). Non-spin/non-donut tricks keep `controls`.

### `DriveView.swift` — stream the spin from the stored params

In `startTrick`, for the spin: fetch `vmax` (`donutVmaxMS()`) and `track` (`donutTrackM()`), build
`Tricks.spinTrick(turns: TrickSettings.spinTurns(), durationMs: TrickSettings.spinDurMs(), vmaxMS:, trackM:)`,
and stream it (with the same `Task.isCancelled` guard already in place). Other tricks unchanged.

### Localization

`L.spinTurns` → `"trick.spinTurns" = "Развороты";`, `L.spinDuration` → `"trick.spinDuration" = "Продолжительность";`.
(Reuse `L.trickSec`/`L.cmUnit`-style helpers as needed for the value formatting.)

## Testing

Host tests (`swiftc`) in `TrickSimTests`:
- `spinSpeed` formula: e.g. `spinSpeed(turns: 1, durationMs: 5000, vmaxMS: 0.578, trackM: 0.13) ≈ 0.141`;
  scales linearly (2 turns → 2× speed; 2× duration → ½ speed).
- Clamp: an infeasible combo (many turns, short duration) clamps to 1.0; degenerate (vmax≤0 or duration≤0) → 0.
- Round-trip via the simulation: `spinTrick(...)` simulated → `turnRad/2π ≈ min(turns, feasible)` and the
  centre path length ≈ 0 (in-place).
- `spinTrick` keeps `Tricks.spin.id`, one step.

Build: `xcodebuild` succeeds; screenshot the spin editor showing the spin animation + «Развороты» stepper +
«Продолжительность» slider, with the caption reading the turn count.

## Out of scope

- Spin direction (CW/CCW) — stays the current single direction.
- A turn radius / arc spin — that is the donut.
- Other tricks, firmware.
