# Adjustable Donut Diameter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a «Диаметр круга» slider (cm) to the donut editor; the chosen diameter back-solves the differential-drive side ratio → the donut's `(t, y)` command, which both the simulation and the real streamed maneuver use.

**Architecture:** A pure inverse solver `Tricks.donutSides(diameterCm:)` (and `Tricks.donutTrick(diameterCm:)`) turns a target circle diameter into the donut step, using a shared track constant `Tricks.donutTrackM` (also used by the simulation). The diameter persists per-donut in `UserDefaults` via `TrickSettings`. `TrickEditorView` gains a diameter slider and feeds `donutTrick(diameter)` into `TrickSimView` for live preview; `DriveView` streams the donut built from the stored diameter. iOS-only — no firmware change.

**Tech Stack:** SwiftUI (Swift 6), `swiftc` host tests, `enum L` localization.

**Spec:** `docs/superpowers/specs/2026-06-17-donut-diameter-design.md`

**Branch:** `feat/trick-sim` (continuation of the donut-simulation feature; spec committed there).

---

## File Structure

- `ios/ESP32Car/Tricks.swift` — **modify** (pure): add `donutTrackM`, diameter bounds, `donutSides(diameterCm:)`, `donutTrick(diameterCm:)`.
- `ios/ESP32CarTests/TrickSimTests.swift` — **modify**: add solver tests.
- `ios/ESP32Car/TrickSettings.swift` — **modify**: persist the donut diameter.
- `ios/ESP32Car/L.swift`, `Resources/ru.lproj/Localizable.strings` — **modify**: «Диаметр круга».
- `ios/ESP32Car/TrickSimView.swift` — **modify**: use `Tricks.donutTrackM` (single track source).
- `ios/ESP32Car/TrickEditorView.swift` — **modify**: diameter slider + feed `donutTrick(diameter)` to the sim.
- `ios/ESP32Car/DriveView.swift` — **modify**: stream the donut built from the stored diameter.

Note: the spec tentatively named the solver `TrickSim.donutSides`; this plan puts it in `Tricks` instead (avoids a `Tricks ↔ TrickSim` conceptual cycle, since `TrickSim` already depends on `Tricks` for `TrickStep`). Same math, host-tested.

---

### Task 1: Donut geometry solver in `Tricks` (pure) + host tests

**Files:**
- Modify: `ios/ESP32Car/Tricks.swift`, `ios/ESP32CarTests/TrickSimTests.swift`

- [ ] **Step 1: Write the host-test driver `/tmp/main.swift`**

```swift
import Foundation
func approx(_ a: Double, _ b: Double, _ tol: Double, _ w: String) { assert(abs(a - b) <= tol, "\(w): \(a) vs \(b)") }
// default 50 cm → ≈ (0.79, 0.21)
let d = Tricks.donutSides(diameterCm: 50)
approx(d.t, 0.794, 0.01, "t50"); approx(d.y, 0.206, 0.01, "y50")
// round-trip: (t,y) → normalized sides → radius ≈ diameter/2
for diaCm in [30.0, 60.0, 120.0] {
    let s = Tricks.donutSides(diameterCm: diaCm)
    let sides = ControlModel.sides(t: s.t, y: s.y)
    let R = Tricks.donutTrackM * (sides.left + sides.right) / (2 * (sides.left - sides.right))
    approx(R, diaCm / 100 / 2, 0.005, "R\(diaCm)")
}
// tight diameter clamps r to 0 → t=y=0.5
let tight = Tricks.donutSides(diameterCm: 5)
approx(tight.t, 0.5, 1e-9, "tightT"); approx(tight.y, 0.5, 1e-9, "tightY")
// donutTrick keeps id/total, one step
let dt = Tricks.donutTrick(diameterCm: 50)
assert(dt.id == Tricks.donut.id && dt.steps.count == 1 && dt.totalMs == 5000, "donutTrick")
print("donut geometry: all passed")
```

- [ ] **Step 2: Run it to verify it fails (no solver yet)**

Run: `cd /Users/adamjohnson/VSCode/esp32-p4-car && swiftc ios/ESP32Car/ControlModel.swift ios/ESP32Car/Tricks.swift /tmp/main.swift -o /tmp/dg`
Expected: FAIL — `error: ... 'donutSides' ... 'donutTrackM' ...` (members don't exist yet).

- [ ] **Step 3: Add the solver to `ios/ESP32Car/Tricks.swift`**

Inside `enum Tricks`, immediately after the `static let all: [Trick] = [...]` line, add:
```swift
    // MARK: donut geometry (pure, host-tested) — radius depends only on the side ratio + track,
    // not on motor speed. Inverse of TrickSim's R = T·(l+r)/(2(l−r)).
    /// Track width (lateral wheel separation), shared with the simulation.
    static let donutTrackM = 0.13
    static let donutDiaMinCm = 20, donutDiaMaxCm = 150, donutDiaDefaultCm = 50

    /// For a target circle diameter, hold the fast wheel at full power and solve the slow wheel's
    /// ratio, returning the (t, y) command. r is clamped to [0, 0.9] so both wheels stay forward
    /// (the maneuver remains a circle, never a pivot or near-straight line).
    static func donutSides(diameterCm: Double) -> (t: Double, y: Double) {
        let R = Swift.max(0.001, diameterCm / 100 / 2)
        let T = donutTrackM
        var r = (2 * R - T) / (2 * R + T)
        r = Swift.min(0.9, Swift.max(0.0, r))
        return ((1 + r) / 2, (1 - r) / 2)
    }

    /// The donut maneuver for a given circle diameter — same id/name/icon, the single step's
    /// (t, y) derived from `donutSides`. Real duration is layered on by `withDurations`.
    static func donutTrick(diameterCm: Double) -> Trick {
        let (t, y) = donutSides(diameterCm: diameterCm)
        return Trick(id: donut.id, nameKey: donut.nameKey, icon: donut.icon,
                     steps: [TrickStep(t: t, y: y, ms: 5000)])
    }
```

- [ ] **Step 4: Run the host check to verify it passes**

Run: `cd /Users/adamjohnson/VSCode/esp32-p4-car && swiftc ios/ESP32Car/ControlModel.swift ios/ESP32Car/Tricks.swift /tmp/main.swift -o /tmp/dg && /tmp/dg`
Expected: `donut geometry: all passed`

- [ ] **Step 5: Add XCTest cases to `ios/ESP32CarTests/TrickSimTests.swift`**

Add these methods inside `final class TrickSimTests`:
```swift
    func testDonutSidesRoundTrip() {
        let d = Tricks.donutSides(diameterCm: 50)
        XCTAssertEqual(d.t, 0.794, accuracy: 0.01)
        XCTAssertEqual(d.y, 0.206, accuracy: 0.01)
        for diaCm in [30.0, 60.0, 120.0] {
            let s = Tricks.donutSides(diameterCm: diaCm)
            let sides = ControlModel.sides(t: s.t, y: s.y)
            let R = Tricks.donutTrackM * (sides.left + sides.right) / (2 * (sides.left - sides.right))
            XCTAssertEqual(R, diaCm / 100 / 2, accuracy: 0.005)
        }
        let tight = Tricks.donutSides(diameterCm: 5)
        XCTAssertEqual(tight.t, 0.5, accuracy: 1e-9)
        XCTAssertEqual(tight.y, 0.5, accuracy: 1e-9)
    }
    func testDonutTrick() {
        let t = Tricks.donutTrick(diameterCm: 50)
        XCTAssertEqual(t.id, Tricks.donut.id)
        XCTAssertEqual(t.steps.count, 1)
        XCTAssertEqual(t.totalMs, 5000)
    }
```

- [ ] **Step 6: Commit**

```bash
git add ios/ESP32Car/Tricks.swift ios/ESP32CarTests/TrickSimTests.swift
git commit -m "feat(ios): Tricks.donutSides/donutTrick — diameter→(t,y) solver (host-tested)"
```

---

### Task 2: Persist the donut diameter in `TrickSettings`

**Files:**
- Modify: `ios/ESP32Car/TrickSettings.swift`

- [ ] **Step 1: Add diameter persistence to `ios/ESP32Car/TrickSettings.swift`**

Add these members inside `enum TrickSettings` (e.g. after `reset(_:action:)`):
```swift
    private static let donutDiaKey = "trick.donut.diaCm"
    private static func clampDia(_ cm: Int) -> Int {
        Swift.min(Tricks.donutDiaMaxCm, Swift.max(Tricks.donutDiaMinCm, cm))
    }
    static func donutDiameterCm() -> Int {
        clampDia(UserDefaults.standard.object(forKey: donutDiaKey) as? Int ?? Tricks.donutDiaDefaultCm)
    }
    static func setDonutDiameter(_ cm: Int) {
        UserDefaults.standard.set(clampDia(cm), forKey: donutDiaKey)
    }
    static func resetDonutDiameter() {
        UserDefaults.standard.removeObject(forKey: donutDiaKey)
    }
```

- [ ] **Step 2: Commit**

```bash
git add ios/ESP32Car/TrickSettings.swift
git commit -m "feat(ios): persist the donut circle diameter in TrickSettings"
```

---

### Task 3: Localization

**Files:**
- Modify: `ios/ESP32Car/Resources/ru.lproj/Localizable.strings`, `ios/ESP32Car/L.swift`

- [ ] **Step 1: Add the string** (append near the other `sim.*` entries in `Localizable.strings`)

```
"sim.diameter"  = "Диаметр круга";
```

- [ ] **Step 2: Add the accessor** to `L.swift` (near the other `sim*` accessors)

```swift
    static var simDiameter: String { s("sim.diameter") }
```

- [ ] **Step 3: Commit**

```bash
git add ios/ESP32Car/L.swift ios/ESP32Car/Resources/ru.lproj/Localizable.strings
git commit -m "feat(ios): localization for the donut diameter control"
```

---

### Task 4: Single track source in `TrickSimView`

**Files:**
- Modify: `ios/ESP32Car/TrickSimView.swift`

- [ ] **Step 1: Use `Tricks.donutTrackM` instead of the local constant**

In `ios/ESP32Car/TrickSimView.swift`, change the car-geometry constants line:
```swift
    private static let carLenM = 0.25, carWidM = 0.15, trackM = 0.13
```
to drop the local `trackM` (the donut geometry owns the track now):
```swift
    private static let carLenM = 0.25, carWidM = 0.15
```
And in the `sim` computed property, change `trackM: Self.trackM` to `trackM: Tricks.donutTrackM`:
```swift
        return TrickSim.simulate(steps: steps, vmaxMS: vmax, trackM: Tricks.donutTrackM,
                                 carLenM: Self.carLenM, carWidM: Self.carWidM)
```

- [ ] **Step 2: Commit**

```bash
git add ios/ESP32Car/TrickSimView.swift
git commit -m "refactor(ios): TrickSimView uses the shared Tricks.donutTrackM"
```

---

### Task 5: Diameter slider in `TrickEditorView` + live sim

**Files:**
- Modify: `ios/ESP32Car/TrickEditorView.swift`

- [ ] **Step 1: Add diameter state + load it on appear**

Add a state var next to `@State private var durs: [Int] = []`:
```swift
    @State private var diameterCm = Tricks.donutDiaDefaultCm
```
Change the `.onAppear` to also load the stored diameter:
```swift
        .onAppear {
            if durs.isEmpty { durs = TrickSettings.durations(for: trick) }
            diameterCm = TrickSettings.donutDiameterCm()
        }
```

- [ ] **Step 2: Feed the diameter-derived donut into the simulation + add the diameter row to the card**

Replace the donut branch's `ScrollView { ... }` (the `if trick.id == Tricks.donut.id { ScrollView { VStack(spacing: 16) { TrickSimView(...) ; VStack(spacing: 0) { ForEach ... } ... ; Text(total) } } }`) with this version — `TrickSimView` now receives `Tricks.donutTrick(Double(diameterCm))`, and the rows card gains `diameterRow` above the duration rows:
```swift
                if trick.id == Tricks.donut.id {
                    // One shared scroll: animation + stats + diameter + duration sliders scroll together.
                    ScrollView {
                        VStack(spacing: 16) {
                            TrickSimView(trick: Tricks.donutTrick(Double(diameterCm)), durs: durs, palette: p)
                            VStack(spacing: 0) {
                                diameterRow.padding(.horizontal, 14)
                                Rectangle().fill(p.metal.opacity(0.25)).frame(height: 1)
                                ForEach(actions.indices, id: \.self) { i in
                                    if i > 0 { Rectangle().fill(p.metal.opacity(0.25)).frame(height: 1) }
                                    row(i).padding(.horizontal, 14)
                                }
                            }
                            .background(p.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(p.metal.opacity(0.4), lineWidth: 1))
                            .padding(.horizontal, 16)
                            Text(L.trickTotal(totalSec))
                                .font(.system(size: 12)).foregroundStyle(p.muted).monospacedDigit()
                        }
                        .padding(.bottom, 16)
                    }
                } else {
                    controls
                }
```

- [ ] **Step 3: Add the `diameterRow` view** (place it right after the `row(_:)` function in `TrickEditorView`)

```swift
    @ViewBuilder private var diameterRow: some View {
        let isDefault = diameterCm == Tricks.donutDiaDefaultCm
        HStack(spacing: 11) {
            Text(L.simDiameter).font(.system(size: 13)).foregroundStyle(p.text)
                .frame(width: 150, alignment: .leading)
            Slider(value: Binding(
                get: { Double(diameterCm) },
                set: { diameterCm = Int(($0 / 5).rounded()) * 5 }
            ), in: Double(Tricks.donutDiaMinCm)...Double(Tricks.donutDiaMaxCm), step: 5) { editing in
                if !editing { TrickSettings.setDonutDiameter(diameterCm) }
            }
            .tint(p.accent)
            Text("\(diameterCm) \(L.cmUnit)").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(p.accent).monospacedDigit().frame(width: 54, alignment: .trailing)
            Button {
                diameterCm = Tricks.donutDiaDefaultCm; TrickSettings.resetDonutDiameter()
            } label: {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 13))
                    .foregroundStyle(isDefault ? p.muted : p.accent)
                    .frame(width: 28, height: 28)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(isDefault ? p.line : p.accent.opacity(0.4)))
            }
            .buttonStyle(.plain).disabled(isDefault)
        }
        .padding(.vertical, 4)
    }
```

- [ ] **Step 4: Commit**

```bash
git add ios/ESP32Car/TrickEditorView.swift
git commit -m "feat(ios): donut editor — diameter slider with live simulation preview"
```

---

### Task 6: Stream the donut at the chosen diameter (`DriveView`)

**Files:**
- Modify: `ios/ESP32Car/DriveView.swift`

- [ ] **Step 1: Build the donut from the stored diameter in `startTrick`**

In `ios/ESP32Car/DriveView.swift`, in `startTrick(_ base:)`, replace the line:
```swift
        let trick = Tricks.withDurations(base, TrickSettings.durations(for: base))  // per-action durations; totalMs drives the ring
```
with:
```swift
        // The donut's (t,y) comes from the user-set circle diameter; other tricks use their base.
        let effectiveBase = base.id == Tricks.donut.id
            ? Tricks.donutTrick(diameterCm: Double(TrickSettings.donutDiameterCm())) : base
        let trick = Tricks.withDurations(effectiveBase, TrickSettings.durations(for: effectiveBase))  // per-action durations; totalMs drives the ring
```

- [ ] **Step 2: Commit**

```bash
git add ios/ESP32Car/DriveView.swift
git commit -m "feat(ios): stream the donut maneuver at the user-set diameter"
```

---

### Task 7: Build + simulator verification

**Files:** Temporary, reverted — `ios/ESP32Car/GalleryView.swift`.

- [ ] **Step 1: Re-run the host checks (geometry + sim)**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
swiftc ios/ESP32Car/ControlModel.swift ios/ESP32Car/Tricks.swift /tmp/main.swift -o /tmp/dg && /tmp/dg
```
(Recreate `/tmp/main.swift` from Task 1 Step 1 if absent.) Expected: `donut geometry: all passed`.

- [ ] **Step 2: Build the iOS target**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate
xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -6
```
Expected: `** BUILD SUCCEEDED **`. Fix any compile error in a feature file minimally and rebuild; report fixes.

- [ ] **Step 3: Screenshot the donut editor (mock running, diameter slider visible)**

Temporarily add a gallery frame + seed index, build, install, launch (the mock serves `/wheel` = JGA25-370 rpm 170 so the sim computes):
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
curl -s http://127.0.0.1:8080/wheel >/dev/null 2>&1 || (cd tools/mock_car && nohup .venv/bin/python -u mock_car.py >/tmp/mock_car.log 2>&1 & sleep 2)
python3 - <<'PY'
p="ios/ESP32Car/GalleryView.swift"; s=open(p).read()
if 'index = 27' not in s: s=s.replace('    @State private var index = 0','    @State private var index = 27')
if 'TrickEditor donut' not in s:
    s=s.replace('            ("Recover",                 AnyView(NavigationStack { RecoverView(palette: p) })),\n        ]',
                '            ("Recover",                 AnyView(NavigationStack { RecoverView(palette: p) })),\n            ("TrickEditor donut",       AnyView(NavigationStack { TrickEditorView(trick: Tricks.donut, palette: p) })),\n        ]')
open(p,"w").write(s); print("patched")
PY
cd ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -2
APP=$(find /tmp/ddata/Build/Products -name ESP32Car.app | head -1)
xcrun simctl boot "iPhone 17" 2>/dev/null; open -a Simulator
xcrun simctl install booted "$APP"; xcrun simctl terminate booted com.adamjohnson.esp32car 2>/dev/null
xcrun simctl launch booted com.adamjohnson.esp32car --args -gallery >/dev/null
sleep 4; xcrun simctl io booted screenshot /tmp/dia.png >/dev/null 2>&1
sips --rotate 90 /tmp/dia.png --out /tmp/dia_90.png >/dev/null 2>&1 && echo "screenshot /tmp/dia_90.png"
```
Eyeball `/tmp/dia_90.png` (rotate 270 if upside-down): the donut editor shows the animation (a ~52 cm circle at the default 50 cm diameter), then a card with TWO sliders — «Диаметр круга — 50 см» on top and «Вперёд-вправо» (duration) below — plus «Всего», all in one scroll.

- [ ] **Step 4: Revert the temporary gallery edits**

Set `@State private var index` back to `0` and remove the `"TrickEditor donut"` frame line. Confirm `git diff --stat ios/ESP32Car/GalleryView.swift` shows NO changes.

- [ ] **Step 5: No commit** (verification only).

---

## Self-Review

**Spec coverage:**
- Inverse solver `donutSides` (r=(2R−T)/(2R+T), clamp [0,0.9], fast wheel full) → Task 1. ✅
- `donutTrick(diameterCm:)` builds the donut step, keeps id/name/icon → Task 1. ✅
- Shared track `Tricks.donutTrackM` (sim + solver) → Task 1 (def) + Task 4 (sim uses it). ✅
- Range 20–150, step 5, default 50 → Task 1 consts + Task 5 slider. ✅
- Persist diameter in TrickSettings → Task 2. ✅
- Both sim AND stream derive donut from stored diameter → Task 5 (sim via `donutTrick`) + Task 6 (`DriveView.startTrick`). ✅
- Diameter slider in the donut editor, live preview, reset → Task 5. ✅
- Localization, no Cyrillic in Swift → Task 3 (label via `L`; `×`/digits/`%@`/`cm` via existing `L.cmUnit`). ✅
- Host tests (round-trip, default, clamp) → Task 1. ✅
- Out of scope (other tricks, editable track, firmware) → untouched. ✅

**Placeholder scan:** none — full code in every code step. ✅

**Type/name consistency:** `Tricks.donutTrackM`/`donutDiaMinCm`/`donutDiaMaxCm`/`donutDiaDefaultCm`/`donutSides(diameterCm:)`/`donutTrick(diameterCm:)` defined in Task 1 and used in Tasks 2/4/5/6; `TrickSettings.donutDiameterCm()`/`setDonutDiameter(_:)`/`resetDonutDiameter()` defined in Task 2, used in Tasks 5/6; `L.simDiameter` defined in Task 3, used in Task 5; `L.cmUnit` already exists; `TrickSimView(trick:durs:palette:)` unchanged signature, called with `Tricks.donutTrick(...)` in Task 5; `ControlModel.sides`, `p.line`, `p.metal`, `p.accent`, `p.muted`, `p.text` all exist. ✅
