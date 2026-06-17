# Spin Trick: Turns + Duration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the «Разворот» (spin) trick's fixed duration with a **turns** stepper (1 turn = 360°) + a **duration** slider; the spin **speed** is derived so the car does N in-place turns in T seconds, with a live simulation preview.

**Architecture:** A pure `Tricks.spinSpeed(turns:durationMs:vmaxMS:trackM:)` derives the yaw magnitude (`spinY = N·π·track/(T·vmax)`, clamped to (0,1]); `Tricks.spinTrick(...)` builds the one-step maneuver `{t:0, y:spinY, ms:T}`. The two params persist in `TrickSettings`; `TrickEditorView` shows a turns stepper + duration slider feeding `TrickSimView`'s live preview; `DriveView` streams the spin built from the stored params. iOS-only — directly mirrors the adjustable donut.

**Tech Stack:** SwiftUI (Swift 6), `swiftc` host tests, `enum L` localization.

**Spec:** `docs/superpowers/specs/2026-06-18-spin-turns-design.md`

**Branch:** `feat/spin-turns`

---

## File Structure

- `ios/ESP32Car/Tricks.swift` — **modify** (pure): add `spinTurns*`/`spinDur*` consts, `spinSpeed`, `spinTrick`.
- `ios/ESP32CarTests/TrickSimTests.swift` — **modify**: spin solver + round-trip tests.
- `ios/ESP32Car/TrickSettings.swift` — **modify**: persist spin turns + duration.
- `ios/ESP32Car/L.swift`, `Resources/ru.lproj/Localizable.strings` — **modify**: «Развороты», «Продолжительность».
- `ios/ESP32Car/TrickSimView.swift` — **modify**: `spinTurns`/`spinDurMs` params; build the spin step.
- `ios/ESP32Car/TrickEditorView.swift` — **modify**: spin editor branch (turns stepper + duration slider).
- `ios/ESP32Car/DriveView.swift` — **modify**: stream the spin from the stored params.

---

### Task 1: Spin solver in `Tricks` (pure) + host tests

**Files:**
- Modify: `ios/ESP32Car/Tricks.swift`, `ios/ESP32CarTests/TrickSimTests.swift`

- [ ] **Step 1: Write the host-test driver `/tmp/main.swift`** (swiftc requires the top-level driver be named `main.swift`)

```swift
import Foundation
func approx(_ a: Double, _ b: Double, _ tol: Double, _ w: String) { assert(abs(a - b) <= tol, "\(w): \(a) vs \(b)") }
let T = Tricks.donutTrackFallbackM, V = Tricks.donutNominalVmaxMS   // 0.13, 0.578
// default formula: 1 turn in 5 s ≈ 0.141
approx(Tricks.spinSpeed(turns: 1, durationMs: 5000, vmaxMS: V, trackM: T), 0.141, 0.005, "y1")
// linear: 2 turns → 2× ; 2× duration → ½×
approx(Tricks.spinSpeed(turns: 2, durationMs: 5000, vmaxMS: V, trackM: T),
       2 * Tricks.spinSpeed(turns: 1, durationMs: 5000, vmaxMS: V, trackM: T), 1e-9, "lin-turns")
approx(Tricks.spinSpeed(turns: 1, durationMs: 10000, vmaxMS: V, trackM: T),
       0.5 * Tricks.spinSpeed(turns: 1, durationMs: 5000, vmaxMS: V, trackM: T), 1e-9, "lin-dur")
// clamp to 1.0 when infeasible (6 turns in 1 s at default speed); degenerate → 0
assert(Tricks.spinSpeed(turns: 6, durationMs: 1000, vmaxMS: V, trackM: T) == 1.0, "clamp1")
assert(Tricks.spinSpeed(turns: 1, durationMs: 0, vmaxMS: V, trackM: T) == 0, "dur0")
assert(Tricks.spinSpeed(turns: 1, durationMs: 5000, vmaxMS: 0, trackM: T) == 0, "vmax0")
// round-trip: simulate the spin → swept revolutions ≈ requested (feasible), centre stays put
for n in [1, 2, 3] {
    let trick = Tricks.spinTrick(turns: n, durationMs: 5000, vmaxMS: V, trackM: T)
    let r = TrickSim.simulate(steps: trick.steps, vmaxMS: V, trackM: T, carLenM: 0.25, carWidM: 0.15)
    approx(r.turnRad / (2 * Double.pi), Double(n), 0.05, "rev\(n)")
    approx(r.pathLenM, 0.0, 0.01, "inplace\(n)")
}
// spinTrick keeps the spin id, one step
let st = Tricks.spinTrick(turns: 2, durationMs: 3000, vmaxMS: V, trackM: T)
assert(st.id == Tricks.spin.id && st.steps.count == 1 && st.steps[0].ms == 3000, "spinTrick")
print("spin: all passed")
```

- [ ] **Step 2: Run it to verify it FAILS (no solver yet)**

Run: `cd /Users/adamjohnson/VSCode/esp32-p4-car && swiftc ios/ESP32Car/ControlModel.swift ios/ESP32Car/TrickSim.swift ios/ESP32Car/Tricks.swift /tmp/main.swift -o /tmp/sp`
Expected: FAIL — `spinSpeed`/`spinTrick`/`spinTurns*` undefined.

- [ ] **Step 3: Add the solver to `ios/ESP32Car/Tricks.swift`**

Inside `enum Tricks`, immediately AFTER the `donutTrick(diameterCm:circles:vmaxMS:trackM:)` function (its last line is `steps: [TrickStep(t: t, y: y, ms: ms)])` then `}`), add:
```swift

    // MARK: spin turns + duration (pure, host-tested) — in-place pivot. Speed is back-solved so the
    // car does `turns` full 360° rotations in `durationMs`: ω = 2·y·vmax/track, turns·2π = ω·T ⇒
    // y = turns·π·track / (T·vmax), clamped to (0, 1] (can't spin faster than full power).
    static let spinTurnsMin = 1, spinTurnsMax = 6, spinTurnsDefault = 2
    static let spinDurMinMs = 1000, spinDurMaxMs = 10000, spinDurDefaultMs = 3000

    /// Derived yaw magnitude for `turns` full in-place turns in `durationMs`, at speed `vmaxMS` / `trackM`.
    /// 0 if speed/duration is degenerate; clamped to at most 1.0 (full power).
    static func spinSpeed(turns: Int, durationMs: Int, vmaxMS: Double, trackM: Double) -> Double {
        guard vmaxMS > 0, durationMs > 0 else { return 0 }
        let n = Double(Swift.max(spinTurnsMin, turns))
        let t = Double(durationMs) / 1000
        let y = n * Double.pi * trackM / (t * vmaxMS)
        return Swift.min(1.0, Swift.max(0.0, y))
    }

    /// The spin maneuver: one in-place step {t:0, y: spinSpeed(...), ms: durationMs}. Keeps spin's id/name/icon.
    static func spinTrick(turns: Int, durationMs: Int, vmaxMS: Double, trackM: Double) -> Trick {
        let y = spinSpeed(turns: turns, durationMs: durationMs, vmaxMS: vmaxMS, trackM: trackM)
        return Trick(id: spin.id, nameKey: spin.nameKey, icon: spin.icon,
                     steps: [TrickStep(t: 0, y: y, ms: durationMs)])
    }
```

- [ ] **Step 4: Run the host check to verify it PASSES**

Run: `cd /Users/adamjohnson/VSCode/esp32-p4-car && swiftc ios/ESP32Car/ControlModel.swift ios/ESP32Car/TrickSim.swift ios/ESP32Car/Tricks.swift /tmp/main.swift -o /tmp/sp && /tmp/sp`
Expected: `spin: all passed`

- [ ] **Step 5: Add XCTest cases to `ios/ESP32CarTests/TrickSimTests.swift`**

Add these methods inside `final class TrickSimTests`:
```swift
    func testSpinSpeedFormula() {
        let T = Tricks.donutTrackFallbackM, V = Tricks.donutNominalVmaxMS
        XCTAssertEqual(Tricks.spinSpeed(turns: 1, durationMs: 5000, vmaxMS: V, trackM: T), 0.141, accuracy: 0.005)
        XCTAssertEqual(Tricks.spinSpeed(turns: 2, durationMs: 5000, vmaxMS: V, trackM: T),
                       2 * Tricks.spinSpeed(turns: 1, durationMs: 5000, vmaxMS: V, trackM: T), accuracy: 1e-9)
        XCTAssertEqual(Tricks.spinSpeed(turns: 1, durationMs: 10000, vmaxMS: V, trackM: T),
                       0.5 * Tricks.spinSpeed(turns: 1, durationMs: 5000, vmaxMS: V, trackM: T), accuracy: 1e-9)
        XCTAssertEqual(Tricks.spinSpeed(turns: 6, durationMs: 1000, vmaxMS: V, trackM: T), 1.0)
        XCTAssertEqual(Tricks.spinSpeed(turns: 1, durationMs: 0, vmaxMS: V, trackM: T), 0)
        XCTAssertEqual(Tricks.spinSpeed(turns: 1, durationMs: 5000, vmaxMS: 0, trackM: T), 0)
    }
    func testSpinRoundTrip() {
        let T = Tricks.donutTrackFallbackM, V = Tricks.donutNominalVmaxMS
        for n in [1, 2, 3] {
            let trick = Tricks.spinTrick(turns: n, durationMs: 5000, vmaxMS: V, trackM: T)
            let r = TrickSim.simulate(steps: trick.steps, vmaxMS: V, trackM: T, carLenM: 0.25, carWidM: 0.15)
            XCTAssertEqual(r.turnRad / (2 * Double.pi), Double(n), accuracy: 0.05)
            XCTAssertEqual(r.pathLenM, 0.0, accuracy: 0.01)
        }
    }
    func testSpinTrick() {
        let t = Tricks.spinTrick(turns: 2, durationMs: 3000, vmaxMS: Tricks.donutNominalVmaxMS,
                                 trackM: Tricks.donutTrackFallbackM)
        XCTAssertEqual(t.id, Tricks.spin.id)
        XCTAssertEqual(t.steps.count, 1)
        XCTAssertEqual(t.steps[0].ms, 3000)
        XCTAssertEqual(t.steps[0].t, 0)
    }
```

- [ ] **Step 6: Commit**

```bash
git add ios/ESP32Car/Tricks.swift ios/ESP32CarTests/TrickSimTests.swift
git commit -m "feat(ios): Tricks.spinSpeed/spinTrick — turns+duration → derived spin speed (host-tested)"
```

---

### Task 2: Persist spin turns + duration in `TrickSettings`

**Files:**
- Modify: `ios/ESP32Car/TrickSettings.swift`

- [ ] **Step 1: Add persistence to `ios/ESP32Car/TrickSettings.swift`**

Add these members inside `enum TrickSettings`, after the `resetDonutCircles()` function (before the enum's closing brace):
```swift

    private static let spinTurnsKey = "trick.spin.turns"
    private static func clampSpinTurns(_ n: Int) -> Int {
        Swift.min(Tricks.spinTurnsMax, Swift.max(Tricks.spinTurnsMin, n))
    }
    static func spinTurns() -> Int {
        clampSpinTurns(UserDefaults.standard.object(forKey: spinTurnsKey) as? Int ?? Tricks.spinTurnsDefault)
    }
    static func setSpinTurns(_ n: Int) {
        UserDefaults.standard.set(clampSpinTurns(n), forKey: spinTurnsKey)
    }
    static func resetSpinTurns() {
        UserDefaults.standard.removeObject(forKey: spinTurnsKey)
    }

    private static let spinDurKey = "trick.spin.durMs"
    private static func clampSpinDur(_ ms: Int) -> Int {
        Swift.min(Tricks.spinDurMaxMs, Swift.max(Tricks.spinDurMinMs, ms))
    }
    static func spinDurMs() -> Int {
        clampSpinDur(UserDefaults.standard.object(forKey: spinDurKey) as? Int ?? Tricks.spinDurDefaultMs)
    }
    static func setSpinDurMs(_ ms: Int) {
        UserDefaults.standard.set(clampSpinDur(ms), forKey: spinDurKey)
    }
    static func resetSpinDurMs() {
        UserDefaults.standard.removeObject(forKey: spinDurKey)
    }
```

- [ ] **Step 2: Commit**

```bash
git add ios/ESP32Car/TrickSettings.swift
git commit -m "feat(ios): persist spin turns + duration in TrickSettings"
```

---

### Task 3: Localization

**Files:**
- Modify: `ios/ESP32Car/Resources/ru.lproj/Localizable.strings`, `ios/ESP32Car/L.swift`

- [ ] **Step 1: Add the strings** (append right after the `"sim.circles"` line in `Localizable.strings`)

```
"trick.spinTurns"     = "Развороты";
"trick.spinDuration"  = "Продолжительность";
```

- [ ] **Step 2: Add the accessors** to `L.swift` (after the `simCircles` accessor)

```swift
    static var spinTurns: String { s("trick.spinTurns") }
    static var spinDuration: String { s("trick.spinDuration") }
```

- [ ] **Step 3: Commit**

```bash
git add ios/ESP32Car/L.swift ios/ESP32Car/Resources/ru.lproj/Localizable.strings
git commit -m "feat(ios): localization for spin turns + duration"
```

---

### Task 4: Spin-aware preview in `TrickSimView`

**Files:**
- Modify: `ios/ESP32Car/TrickSimView.swift`

- [ ] **Step 1: Add the spin params**

Change the stored-properties block:
```swift
    var donutDiameterCm: Double? = nil
    var donutCircles: Int? = nil
    @State private var wheel: WheelClient.Params?
```
to:
```swift
    var donutDiameterCm: Double? = nil
    var donutCircles: Int? = nil
    var spinTurns: Int? = nil
    var spinDurMs: Int? = nil
    @State private var wheel: WheelClient.Params?
```

- [ ] **Step 2: Build the spin step in `steps`**

Replace the `steps` computed property:
```swift
    private var steps: [TrickStep] {
        if trick.id == Tricks.donut.id, let dia = donutDiameterCm, let n = donutCircles, let v = vmaxMS {
            return Tricks.donutTrick(diameterCm: dia, circles: n, vmaxMS: v, trackM: track).steps
        }
        let d = durs.isEmpty ? Tricks.baseDurations(trick) : durs
        return Tricks.withDurations(trick, d).steps
    }
```
with (the spin branch is added between the donut branch and the generic path):
```swift
    private var steps: [TrickStep] {
        if trick.id == Tricks.donut.id, let dia = donutDiameterCm, let n = donutCircles, let v = vmaxMS {
            return Tricks.donutTrick(diameterCm: dia, circles: n, vmaxMS: v, trackM: track).steps
        }
        if trick.id == Tricks.spin.id, let n = spinTurns, let ms = spinDurMs, let v = vmaxMS {
            return Tricks.spinTrick(turns: n, durationMs: ms, vmaxMS: v, trackM: track).steps
        }
        let d = durs.isEmpty ? Tricks.baseDurations(trick) : durs
        return Tricks.withDurations(trick, d).steps
    }
```

- [ ] **Step 3: Commit**

```bash
git add ios/ESP32Car/TrickSimView.swift
git commit -m "feat(ios): TrickSimView builds the spin from turns + duration"
```

---

### Task 5: Spin editor branch in `TrickEditorView`

**Files:**
- Modify: `ios/ESP32Car/TrickEditorView.swift`

- [ ] **Step 1: Add spin state + load it on appear**

Add state vars after `@State private var circles = Tricks.donutCirclesDefault`:
```swift
    @State private var spinTurns = Tricks.spinTurnsDefault
    @State private var spinDurMs = Tricks.spinDurDefaultMs
```
Change `.onAppear` to also load them:
```swift
        .onAppear {
            if durs.isEmpty { durs = TrickSettings.durations(for: trick) }
            diameterCm = TrickSettings.donutDiameterCm()
            circles = TrickSettings.donutCircles()
            spinTurns = TrickSettings.spinTurns()
            spinDurMs = TrickSettings.spinDurMs()
        }
```

- [ ] **Step 2: Add the spin branch to the body**

Find the `if trick.id == Tricks.donut.id { ScrollView { … } } else { controls }` block. Change the `else { controls }` to `else if trick.id == Tricks.spin.id { … } else { controls }` by replacing:
```swift
                } else {
                    controls
                }
```
with:
```swift
                } else if trick.id == Tricks.spin.id {
                    // One shared scroll: animation + stats + turns + duration scroll together.
                    ScrollView {
                        VStack(spacing: 16) {
                            TrickSimView(trick: Tricks.spin, durs: durs, palette: p,
                                         spinTurns: spinTurns, spinDurMs: spinDurMs)
                            VStack(spacing: 0) {
                                turnsRow.padding(.horizontal, 14)
                                Rectangle().fill(p.metal.opacity(0.25)).frame(height: 1)
                                durationRow.padding(.horizontal, 14)
                            }
                            .background(p.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(p.metal.opacity(0.4), lineWidth: 1))
                            .padding(.horizontal, 16)
                        }
                        .padding(.bottom, 16)
                    }
                } else {
                    controls
                }
```

- [ ] **Step 3: Add `turnsRow` + `durationRow`** (place them right after the existing `circlesRow` property)

```swift
    @ViewBuilder private var turnsRow: some View {
        let isDefault = spinTurns == Tricks.spinTurnsDefault
        HStack(spacing: 11) {
            Text(L.spinTurns).font(.system(size: 13)).foregroundStyle(p.text)
                .frame(width: 150, alignment: .leading)
            Spacer()
            stepButton("minus") {
                spinTurns = Swift.max(Tricks.spinTurnsMin, spinTurns - 1); TrickSettings.setSpinTurns(spinTurns)
            }.disabled(spinTurns <= Tricks.spinTurnsMin)
            Text("\(spinTurns)").font(.system(size: 15, weight: .semibold))
                .foregroundStyle(p.accent).monospacedDigit().frame(width: 34)
            stepButton("plus") {
                spinTurns = Swift.min(Tricks.spinTurnsMax, spinTurns + 1); TrickSettings.setSpinTurns(spinTurns)
            }.disabled(spinTurns >= Tricks.spinTurnsMax)
            Button {
                spinTurns = Tricks.spinTurnsDefault; TrickSettings.resetSpinTurns()
            } label: {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 13))
                    .foregroundStyle(isDefault ? p.muted : p.accent)
                    .frame(width: 28, height: 28)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(isDefault ? p.line : p.accent.opacity(0.4)))
            }
            .buttonStyle(.plain).disabled(isDefault).padding(.leading, 4)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var durationRow: some View {
        let isDefault = spinDurMs == Tricks.spinDurDefaultMs
        HStack(spacing: 11) {
            Text(L.spinDuration).font(.system(size: 13)).foregroundStyle(p.text)
                .frame(width: 150, alignment: .leading)
            Slider(value: Binding(
                get: { Double(spinDurMs) / 1000 },
                set: { spinDurMs = Int(($0 * 2).rounded()) * 500 }   // 0.5 s steps
            ), in: Double(Tricks.spinDurMinMs) / 1000...Double(Tricks.spinDurMaxMs) / 1000, step: 0.5) { editing in
                if !editing { TrickSettings.setSpinDurMs(spinDurMs) }
            }
            .tint(p.accent)
            Text(L.trickSec(Double(spinDurMs) / 1000)).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(p.accent).monospacedDigit().frame(width: 54, alignment: .trailing)
            Button {
                spinDurMs = Tricks.spinDurDefaultMs; TrickSettings.resetSpinDurMs()
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

- [ ] **Step 4: Build the iOS target**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate >/dev/null
xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -6
```
Expected: `** BUILD SUCCEEDED **`. Fix any compile error minimally and report it.

- [ ] **Step 5: Commit**

```bash
git add ios/ESP32Car/TrickEditorView.swift
git commit -m "feat(ios): spin editor — turns stepper + duration slider with live preview"
```

---

### Task 6: Stream the spin at the chosen params (`DriveView`)

**Files:**
- Modify: `ios/ESP32Car/DriveView.swift`

- [ ] **Step 1: Add the spin branch in `startTrick`**

In `ios/ESP32Car/DriveView.swift`, in `startTrick(_:)`, the current branch begins:
```swift
            let trick: Trick
            if base.id == Tricks.donut.id {
```
Insert a spin branch BEFORE the donut branch by replacing those two lines with:
```swift
            let trick: Trick
            if base.id == Tricks.spin.id {
                // Turns + duration from settings; speed derived at the real motor speed / track.
                let vmax = await donutVmaxMS()
                if Task.isCancelled { return }
                let track = await donutTrackM()
                if Task.isCancelled { return }
                trick = Tricks.spinTrick(turns: TrickSettings.spinTurns(), durationMs: TrickSettings.spinDurMs(),
                                         vmaxMS: vmax, trackM: track)
            } else if base.id == Tricks.donut.id {
```
(The donut `else if` body and the final `else` are unchanged.)

- [ ] **Step 2: Build the iOS target**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -4
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/ESP32Car/DriveView.swift
git commit -m "feat(ios): stream the spin at the user-set turns + duration"
```

---

### Task 7: Build + simulator verification

**Files:** Temporary, reverted — `ios/ESP32Car/GalleryView.swift`.

- [ ] **Step 1: Re-run the spin host check**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
swiftc ios/ESP32Car/ControlModel.swift ios/ESP32Car/TrickSim.swift ios/ESP32Car/Tricks.swift /tmp/main.swift -o /tmp/sp && /tmp/sp
```
(Recreate `/tmp/main.swift` from Task 1 Step 1 if absent.) Expected: `spin: all passed`.

- [ ] **Step 2: Screenshot the spin editor (mock running, turns/duration controls visible)**

The mock serves `/wheel` + `/dims` so the sim computes a real spin. Temporarily add a gallery frame + seed index, build, install, launch:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
curl -s http://127.0.0.1:8080/wheel >/dev/null 2>&1 || (cd tools/mock_car && nohup .venv/bin/python -u mock_car.py >/tmp/mock_car.log 2>&1 & sleep 2)
python3 - <<'PY'
p="ios/ESP32Car/GalleryView.swift"; s=open(p).read()
if 'index = 27' not in s: s=s.replace('    @State private var index = 0','    @State private var index = 27')
if 'TrickEditor spin' not in s:
    s=s.replace('            ("Recover",                 AnyView(NavigationStack { RecoverView(palette: p) })),\n        ]',
                '            ("Recover",                 AnyView(NavigationStack { RecoverView(palette: p) })),\n            ("TrickEditor spin",        AnyView(NavigationStack { TrickEditorView(trick: Tricks.spin, palette: p) })),\n        ]')
open(p,"w").write(s); print("patched")
PY
cd ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -2
APP=$(find /tmp/ddata/Build/Products -name ESP32Car.app | head -1)
xcrun simctl boot "iPhone 17" 2>/dev/null; open -a Simulator
xcrun simctl install booted "$APP"; xcrun simctl terminate booted com.adamjohnson.esp32car 2>/dev/null
xcrun simctl launch booted com.adamjohnson.esp32car --args -gallery >/dev/null
sleep 4; xcrun simctl io booted screenshot /tmp/spin.png >/dev/null 2>&1
sips --rotate 90 /tmp/spin.png --out /tmp/spin_90.png >/dev/null 2>&1 && echo "screenshot /tmp/spin_90.png"
```
Eyeball `/tmp/spin_90.png` (rotate 270 if upside-down): the spin editor shows the in-place spin animation (↻ + a turn count) and a card with TWO rows — «Развороты — 2» (stepper) on top and «Продолжительность — 3.0 с» (slider) below; the sim caption reads «За 3.0 с — 2.0 оборота» (or the achieved count).

- [ ] **Step 3: Revert the temporary gallery edits**

Set `@State private var index` back to `0` and remove the `"TrickEditor spin"` frame line. Confirm `git diff --stat ios/ESP32Car/GalleryView.swift` shows NO changes.

- [ ] **Step 4: No commit** (verification only).

---

## Self-Review

**Spec coverage:**
- `spinSpeed(turns:durationMs:vmaxMS:trackM:)` (= N·π·track/(T·vmax), clamp (0,1], degenerate→0) → Task 1. ✅
- `spinTrick(...)` one step `{t:0, y:spinY, ms:T}`, keeps spin id/name/icon → Task 1. ✅
- Consts turns 1–6/default 2, duration 1000–10000/default 3000 → Task 1. ✅
- Persist turns + duration in TrickSettings → Task 2. ✅
- Preview: TrickSimView builds the spin (in-place, turnRad = N·2π) → Task 4. ✅
- Editor: turns stepper + duration slider, no «Всего» footer → Task 5. ✅
- Stream the spin from stored params (vmax + track, cancel guard) → Task 6. ✅
- Localization «Развороты»/«Продолжительность», no Cyrillic in Swift → Task 3. ✅
- Host tests: formula, linearity, clamp, degenerate, round-trip-revolutions + in-place → Task 1. ✅
- Feasibility clamp visible in the sim → Task 4 (sim) + Task 7 (eyeball). ✅
- Out of scope (direction, radius, other tricks, firmware) → untouched. ✅

**Placeholder scan:** none — full code in every code step. ✅

**Type/name consistency:** `spinSpeed(turns:durationMs:vmaxMS:trackM:)`/`spinTrick(turns:durationMs:vmaxMS:trackM:)`/
`spinTurnsMin/Max/Default`/`spinDurMinMs/MaxMs/DefaultMs` defined in Task 1, used in Tasks 2/4/5/6;
`TrickSettings.spinTurns()/setSpinTurns(_:)/resetSpinTurns()`/`spinDurMs()/setSpinDurMs(_:)/resetSpinDurMs()`
defined in Task 2, used in Tasks 5/6; `L.spinTurns`/`L.spinDuration` defined in Task 3, used in Task 5;
`L.trickSec` already exists; `TrickSimView` gains `spinTurns: Int? = nil`/`spinDurMs: Int? = nil` (Task 4),
called with them in Task 5; `stepButton`/`p.accent`/`p.muted`/`p.text`/`p.line`/`p.metal`/`p.panel` exist;
`Tricks.spin` exists; `TrickSim.Result.turnRad`/`pathLenM` exist. ✅
