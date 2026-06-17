# Wiggle trick: amplitude + wag count

**Date:** 2026-06-18
**Branch:** `feat/wiggle-params` off `main`
**Scope:** iOS-only. No firmware change.

## Problem

The «Вилять» (wiggle) trick is a fixed in-place yaw oscillation: 20 steps alternating `y = ±0.8`, each
`{t:0, ms:250}` — the car twitches left/right on the spot. By analogy with the adjustable donut, spin, and
figure-8, the wiggle should expose editable parameters with a live preview.

## Goal

Replace the wiggle's fixed steps with two editable parameters — **amplitude** (how hard each wag turns,
`y`) and **wag count** (how many full left-right wags) — at a fixed tempo. iOS-only.

## Model

The wiggle is in-place (`t = 0`); it has **no geometry** (it doesn't trace a circle), so nothing is
derived from a closed form — the parameters map directly to the step list.

- A **wag** = one full left-right cycle = two steps: `{t:0, y:+amp, ms:250}` then `{t:0, y:-amp, ms:250}`.
- `wags` wags → `2·wags` steps. Tempo is fixed at `wiggleStepMs = 250` ms/step.
- `amplitude` is the `|y|` of each step.

The current default (20 steps at `y=±0.8`) corresponds exactly to `amplitude = 0.8, wags = 10`.

**Contrast with the other tricks:** donut/figure-8 derive duration from geometry at full power; spin derives
speed from turns + duration; the wiggle has no geometry, so both knobs are direct and no `vmax`/`track` is
needed to build the maneuver.

## Components (mirror the figure-8)

### `Tricks.swift` (pure, host-tested) — additive

```swift
// Wiggle: in-place yaw oscillation. amplitude = |y| per step; a wag = 2 steps (+amp, −amp); fixed tempo.
static let wiggleAmpMin = 0.2, wiggleAmpMax = 1.0, wiggleAmpDefault = 0.8
static let wiggleWagsMin = 1, wiggleWagsMax = 20, wiggleWagsDefault = 10
static let wiggleStepMs = 250

/// The wiggle maneuver: `wags` full left-right wags at the given `amplitude`, fixed 250 ms/step.
/// `2·wags` steps alternating {t:0, y:+amp} / {t:0, y:-amp}. amplitude clamped to [0.2,1.0],
/// wags floored at 1. Keeps the wiggle id/name/icon.
static func wiggleTrick(amplitude: Double, wags: Int) -> Trick {
    let a = Swift.min(wiggleAmpMax, Swift.max(wiggleAmpMin, amplitude))
    let n = Swift.max(wiggleWagsMin, wags)
    let steps = (0..<(2 * n)).map { TrickStep(t: 0, y: $0 % 2 == 0 ? a : -a, ms: wiggleStepMs) }
    return Trick(id: wiggle.id, nameKey: wiggle.nameKey, icon: wiggle.icon, steps: steps)
}
```

The existing `Tricks.wiggle` constant stays (used for id/name/icon and the trick list).

### `TrickSettings.swift` — persist the two params

```swift
static func wiggleAmp() -> Double         // clamped 0.2–1.0, default 0.8
static func setWiggleAmp(_ a: Double)
static func resetWiggleAmp()
static func wiggleWags() -> Int           // clamped 1–20, default 10
static func setWiggleWags(_ n: Int)
static func resetWiggleWags()
```

Keys `trick.wiggle.amp` (Double) and `trick.wiggle.wags` (Int). The wiggle no longer uses the generic
per-action durations.

### `TrickSimView.swift` — wiggle-aware preview

A new optional input pair `wiggleAmp: Double? = nil`, `wiggleWags: Int? = nil` (alongside the existing
donut/spin/figure-8 inputs). In `steps`, when the trick is `Tricks.wiggle`, both params are set, build the
timeline via `Tricks.wiggleTrick(amplitude:wags:)`. (No `vmaxMS` guard is needed to *build* the steps, but
the simulation itself still needs `vmaxMS` to render — same as the other tricks; with no motor it shows the
"pick motor" placeholder.) The simulation renders the in-place rock (centre path ≈ 0); the swept-ghost loop
is already skipped for in-place maneuvers (`pathLenM ≤ 0.05`), so the car reads clearly, like the spin.

### `TrickEditorView.swift` — wiggle editor branch

For `trick.id == Tricks.wiggle.id`, a `ScrollView` with `TrickSimView(...)` (passing `wiggleAmp`/`wiggleWags`)
+ a card holding two rows:
- **«Амплитуда»** — a slider (0.2–1.0, step 0.1), persisting via `TrickSettings.setWiggleAmp`, shown as a
  one-decimal value (reuse the existing slider-row style; the value label reads e.g. `0.8`).
- **«Вильков»** — a − / N / + stepper (1–20), persisting via `TrickSettings.setWiggleWags`.

No «Всего» footer. Non-wiggle/donut/spin/figure-8 tricks keep `controls`.

### `DriveView.swift` — stream the wiggle from the stored params

In `startTrick`, for the wiggle: build `Tricks.wiggleTrick(amplitude: TrickSettings.wiggleAmp(),
wags: TrickSettings.wiggleWags())` synchronously (no `vmax`/`track` fetch needed) and stream it. Other
tricks unchanged.

### Localization

- `L.wiggleAmp` → `"trick.wiggleAmp" = "Амплитуда";`
- `L.wiggleCount` → `"trick.wiggleCount" = "Вильков";`

## Testing

Host tests (`swiftc`) in `TrickSimTests` (driver named `main.swift`):
- `wiggleTrick` structure: `steps.count == 2·wags`; `steps[0].y == +amp`, `steps[1].y == -amp` (alternating);
  every step has `t == 0` and `ms == 250`; `id == Tricks.wiggle.id`.
- Clamps: `amplitude` above 1.0 / below 0.2 clamps into range; `wags` below 1 floors to 1.
- Default round-trip: `wiggleTrick(amplitude: 0.8, wags: 10)` reproduces the original fixed wiggle (20 steps,
  `y = ±0.8`, 250 ms each).

Build: `xcodebuild` succeeds; screenshot the wiggle editor showing the rocking car + «Амплитуда» slider +
«Вильков» stepper.

## Out of scope

- Tempo (ms/step) as a parameter — fixed at 250 ms.
- First-wag direction — stays the current single orientation.
- Other tricks, firmware.
