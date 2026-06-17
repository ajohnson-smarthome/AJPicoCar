# Donut Circle-Count Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the donut trick's editable duration with an integer **circle count** (1–10, step 1, default 2) entered via a − / N / + stepper; the count back-solves the streamed step duration so the simulation preview and the real maneuver both do exactly that many circles.

**Architecture:** A pure inverse `Tricks.donutDurationMs(circles:y:vmaxMS:)` turns a circle count into a step duration (ms) given the inner-wheel term `y` and the linear speed `vmaxMS`; `Tricks.donutTrick(diameterCm:circles:vmaxMS:)` builds the timed donut. The count persists per-donut in `UserDefaults` via `TrickSettings`. `TrickSimView` gains a `donutCircles:` param and overrides the donut step's ms with its own `vmax` (so the sim renders exactly N circles); `TrickEditorView` swaps the duration slider for a circle stepper; `DriveView` fetches `/wheel` to compute `vmax` (nominal fallback) and streams the timed donut. iOS-only — no firmware change.

**Tech Stack:** SwiftUI (Swift 6), `swiftc` host tests, `enum L` localization.

**Spec:** `docs/superpowers/specs/2026-06-17-donut-circles-design.md`

**Branch:** `feat/trick-sim` (continuation of the donut-diameter feature).

---

## File Structure

- `ios/ESP32Car/Tricks.swift` — **modify** (pure): add circle-count consts, `donutNominalVmaxMS`, `donutDurationMs(circles:y:vmaxMS:)`, `donutTrick(diameterCm:circles:vmaxMS:)`.
- `ios/ESP32CarTests/TrickSimTests.swift` — **modify**: add round-trip + guard tests.
- `ios/ESP32Car/TrickSettings.swift` — **modify**: persist the donut circle count.
- `ios/ESP32Car/L.swift`, `Resources/ru.lproj/Localizable.strings` — **modify**: «Круги».
- `ios/ESP32Car/TrickSimView.swift` — **modify**: optional `donutCircles:`; extract `vmaxMS`; override the donut step ms.
- `ios/ESP32Car/TrickEditorView.swift` — **modify**: circle stepper replaces the duration slider for the donut; drop the «Всего» footer for the donut.
- `ios/ESP32Car/DriveView.swift` — **modify**: compute `vmax` from `/wheel` and stream `donutTrick(diameterCm:circles:vmaxMS:)`.

---

### Task 1: Circle-count geometry in `Tricks` (pure) + host tests

**Files:**
- Modify: `ios/ESP32Car/Tricks.swift`, `ios/ESP32CarTests/TrickSimTests.swift`

- [ ] **Step 1: Write the host-test driver `/tmp/circles.swift`**

```swift
import Foundation
func approx(_ a: Double, _ b: Double, _ tol: Double, _ w: String) { assert(abs(a - b) <= tol, "\(w): \(a) vs \(b)") }

// Round-trip: build a timed donut, simulate it, the swept revolutions ≈ the requested count.
// Independent of vmax — the same speed cancels out of the visible circle count.
for v in [0.4, 0.578, 0.9] {
    for diaCm in [30.0, 50.0, 120.0] {
        for n in [1, 2, 5] {
            let trick = Tricks.donutTrick(diameterCm: diaCm, circles: n, vmaxMS: v)
            let r = TrickSim.simulate(steps: trick.steps, vmaxMS: v, trackM: Tricks.donutTrackM,
                                      carLenM: 0.25, carWidM: 0.15)
            approx(r.turnRad / (2 * Double.pi), Double(n), 0.05, "rev d\(diaCm) n\(n) v\(v)")
        }
    }
}
// Default case ≈ 6849 ms (50 cm, nominal vmax, 2 circles).
let y50 = Tricks.donutSides(diameterCm: 50).y
let ms = Tricks.donutDurationMs(circles: 2, y: y50, vmaxMS: Tricks.donutNominalVmaxMS)
assert(ms > 6500 && ms < 7200, "default ms = \(ms)")
// Guards.
assert(Tricks.donutDurationMs(circles: 2, y: 0.2, vmaxMS: 0) == 0, "vmax0")
assert(Tricks.donutDurationMs(circles: 2, y: 0, vmaxMS: 0.5) == 0, "y0")
assert(Tricks.donutDurationMs(circles: 0, y: 0.2, vmaxMS: 0.5)
       == Tricks.donutDurationMs(circles: 1, y: 0.2, vmaxMS: 0.5), "min1")
// donutTrick keeps id/icon, one step.
let t = Tricks.donutTrick(diameterCm: 50, circles: 2, vmaxMS: 0.578)
assert(t.id == Tricks.donut.id && t.steps.count == 1, "donutTrick")
print("donut circles: all passed")
```

- [ ] **Step 2: Run it to verify it fails (no solver yet)**

Run: `cd /Users/adamjohnson/VSCode/esp32-p4-car && swiftc ios/ESP32Car/ControlModel.swift ios/ESP32Car/TrickSim.swift ios/ESP32Car/Tricks.swift /tmp/circles.swift -o /tmp/dc`
Expected: FAIL — `error: ... 'donutDurationMs' ... 'donutNominalVmaxMS' ...` (members don't exist yet).

- [ ] **Step 3: Add the solver to `ios/ESP32Car/Tricks.swift`**

Inside `enum Tricks`, immediately after the `donutTrick(diameterCm:)` function (the closing brace on the line with `steps: [TrickStep(t: t, y: y, ms: 5000)])`), add:
```swift

    // MARK: donut circle count (pure, host-tested) — duration back-solved from a target
    // number of full circles. ω = vmax·2y/track, so N circles take t = N·π·track/(vmax·y).
    static let donutCirclesMin = 1, donutCirclesMax = 10, donutCirclesDefault = 2
    /// Nominal linear speed (default motor JGA25-370 ~170 rpm, 65 mm wheel: π·0.065·170/60)
    /// used when /wheel is unavailable, so a circle count still maps to *some* duration.
    static let donutNominalVmaxMS = 0.578

    /// Streamed duration (ms) for `circles` full circles of a donut whose inner-wheel term is
    /// `y` (= (1−r)/2 from `donutSides`), at linear speed `vmaxMS`. Inverse of the simulation's
    /// heading sweep; 0 if speed/shape is degenerate.
    static func donutDurationMs(circles: Int, y: Double, vmaxMS: Double) -> Int {
        guard vmaxMS > 0, y > 0 else { return 0 }
        let n = Double(Swift.max(donutCirclesMin, circles))
        return Int((1000 * n * Double.pi * donutTrackM / (vmaxMS * y)).rounded())
    }

    /// The donut maneuver sized to a diameter AND timed to a circle count, at speed `vmaxMS`.
    /// Same id/name/icon; the single step's (t, y) from `donutSides`, ms from `donutDurationMs`.
    static func donutTrick(diameterCm: Double, circles: Int, vmaxMS: Double) -> Trick {
        let (t, y) = donutSides(diameterCm: diameterCm)
        let ms = donutDurationMs(circles: circles, y: y, vmaxMS: vmaxMS)
        return Trick(id: donut.id, nameKey: donut.nameKey, icon: donut.icon,
                     steps: [TrickStep(t: t, y: y, ms: ms)])
    }
```

- [ ] **Step 4: Run the host check to verify it passes**

Run: `cd /Users/adamjohnson/VSCode/esp32-p4-car && swiftc ios/ESP32Car/ControlModel.swift ios/ESP32Car/TrickSim.swift ios/ESP32Car/Tricks.swift /tmp/circles.swift -o /tmp/dc && /tmp/dc`
Expected: `donut circles: all passed`

- [ ] **Step 5: Add XCTest cases to `ios/ESP32CarTests/TrickSimTests.swift`**

Add these methods inside `final class TrickSimTests`:
```swift
    func testDonutCirclesRoundTrip() {
        for v in [0.4, 0.578, 0.9] {
            for diaCm in [30.0, 50.0, 120.0] {
                for n in [1, 2, 5] {
                    let trick = Tricks.donutTrick(diameterCm: diaCm, circles: n, vmaxMS: v)
                    let r = TrickSim.simulate(steps: trick.steps, vmaxMS: v, trackM: Tricks.donutTrackM,
                                              carLenM: 0.25, carWidM: 0.15)
                    XCTAssertEqual(r.turnRad / (2 * Double.pi), Double(n), accuracy: 0.05)
                }
            }
        }
    }
    func testDonutDurationGuards() {
        let y50 = Tricks.donutSides(diameterCm: 50).y
        XCTAssertEqual(Double(Tricks.donutDurationMs(circles: 2, y: y50, vmaxMS: Tricks.donutNominalVmaxMS)),
                       6849, accuracy: 350)
        XCTAssertEqual(Tricks.donutDurationMs(circles: 2, y: 0.2, vmaxMS: 0), 0)
        XCTAssertEqual(Tricks.donutDurationMs(circles: 2, y: 0, vmaxMS: 0.5), 0)
        XCTAssertEqual(Tricks.donutDurationMs(circles: 0, y: 0.2, vmaxMS: 0.5),
                       Tricks.donutDurationMs(circles: 1, y: 0.2, vmaxMS: 0.5))
    }
    func testDonutTrickCircles() {
        let t = Tricks.donutTrick(diameterCm: 50, circles: 2, vmaxMS: 0.578)
        XCTAssertEqual(t.id, Tricks.donut.id)
        XCTAssertEqual(t.steps.count, 1)
    }
```

- [ ] **Step 6: Commit**

```bash
git add ios/ESP32Car/Tricks.swift ios/ESP32CarTests/TrickSimTests.swift
git commit -m "feat(ios): Tricks.donutDurationMs/donutTrick(circles:) — circle-count timing (host-tested)"
```

---

### Task 2: Persist the donut circle count in `TrickSettings`

**Files:**
- Modify: `ios/ESP32Car/TrickSettings.swift`

- [ ] **Step 1: Add circle-count persistence to `ios/ESP32Car/TrickSettings.swift`**

Add these members inside `enum TrickSettings`, right after `resetDonutDiameter()` (before the closing brace of the enum):
```swift

    private static let donutCirclesKey = "trick.donut.circles"
    private static func clampCircles(_ n: Int) -> Int {
        Swift.min(Tricks.donutCirclesMax, Swift.max(Tricks.donutCirclesMin, n))
    }
    static func donutCircles() -> Int {
        clampCircles(UserDefaults.standard.object(forKey: donutCirclesKey) as? Int ?? Tricks.donutCirclesDefault)
    }
    static func setDonutCircles(_ n: Int) {
        UserDefaults.standard.set(clampCircles(n), forKey: donutCirclesKey)
    }
    static func resetDonutCircles() {
        UserDefaults.standard.removeObject(forKey: donutCirclesKey)
    }
```

- [ ] **Step 2: Commit**

```bash
git add ios/ESP32Car/TrickSettings.swift
git commit -m "feat(ios): persist the donut circle count in TrickSettings"
```

---

### Task 3: Localization

**Files:**
- Modify: `ios/ESP32Car/Resources/ru.lproj/Localizable.strings`, `ios/ESP32Car/L.swift`

- [ ] **Step 1: Add the string** (append right after the `"sim.diameter"` line in `Localizable.strings`)

```
"sim.circles"         = "Круги";
```

- [ ] **Step 2: Add the accessor** to `L.swift`, right after the `simDiameter` accessor

```swift
    static var simCircles: String { s("sim.circles") }
```

- [ ] **Step 3: Commit**

```bash
git add ios/ESP32Car/L.swift ios/ESP32Car/Resources/ru.lproj/Localizable.strings
git commit -m "feat(ios): localization for the donut circle-count control"
```

---

### Task 4: Circle-aware donut simulation in `TrickSimView`

**Files:**
- Modify: `ios/ESP32Car/TrickSimView.swift`

- [ ] **Step 1: Add the optional `donutCircles` param**

Change the stored properties block:
```swift
    let trick: Trick
    let durs: [Int]
    let palette: Palette
    @State private var wheel: WheelClient.Params?
```
to:
```swift
    let trick: Trick
    let durs: [Int]
    let palette: Palette
    var donutCircles: Int? = nil
    @State private var wheel: WheelClient.Params?
```

- [ ] **Step 2: Extract `vmaxMS` and override the donut step ms in `steps`**

Replace the `steps` computed property:
```swift
    private var steps: [TrickStep] {
        let d = durs.isEmpty ? Tricks.baseDurations(trick) : durs
        return Tricks.withDurations(trick, d).steps
    }
```
with (the donut's single step is re-timed from the circle count using this view's own `vmaxMS`, so the sim renders exactly N circles):
```swift
    private var steps: [TrickStep] {
        let d = durs.isEmpty ? Tricks.baseDurations(trick) : durs
        var s = Tricks.withDurations(trick, d).steps
        if let donutCircles, trick.id == Tricks.donut.id, s.count == 1, let v = vmaxMS {
            s[0] = TrickStep(t: s[0].t, y: s[0].y,
                             ms: Tricks.donutDurationMs(circles: donutCircles, y: s[0].y, vmaxMS: v))
        }
        return s
    }
```

- [ ] **Step 3: Add the `vmaxMS` computed property and use it in `sim`**

Replace the `sim` computed property:
```swift
    private var sim: TrickSim.Result? {
        guard let w = wheel, let rpm else { return nil }
        let vmax = Double.pi * (Double(w.diameterMm) / 1000) * Double(rpm) / 60
        return TrickSim.simulate(steps: steps, vmaxMS: vmax, trackM: Tricks.donutTrackM,
                                 carLenM: Self.carLenM, carWidM: Self.carWidM)
    }
```
with:
```swift
    private var vmaxMS: Double? {
        guard let w = wheel, let rpm else { return nil }
        return Double.pi * (Double(w.diameterMm) / 1000) * Double(rpm) / 60
    }
    private var sim: TrickSim.Result? {
        guard let v = vmaxMS else { return nil }
        return TrickSim.simulate(steps: steps, vmaxMS: v, trackM: Tricks.donutTrackM,
                                 carLenM: Self.carLenM, carWidM: Self.carWidM)
    }
```

- [ ] **Step 4: Commit**

```bash
git add ios/ESP32Car/TrickSimView.swift
git commit -m "feat(ios): TrickSimView times the donut from a circle count"
```

---

### Task 5: Circle stepper in `TrickEditorView`

**Files:**
- Modify: `ios/ESP32Car/TrickEditorView.swift`

- [ ] **Step 1: Add circle-count state + load it on appear**

Add a state var right after `@State private var diameterCm = Tricks.donutDiaDefaultCm`:
```swift
    @State private var circles = Tricks.donutCirclesDefault
```
Change the `.onAppear` to also load the stored count:
```swift
        .onAppear {
            if durs.isEmpty { durs = TrickSettings.durations(for: trick) }
            diameterCm = TrickSettings.donutDiameterCm()
            circles = TrickSettings.donutCircles()
        }
```

- [ ] **Step 2: Feed the circle count into the sim and swap the duration rows for the stepper**

Replace the donut branch (the whole `if trick.id == Tricks.donut.id { ScrollView { ... } } else { controls }`) with this version — the sim receives `donutCircles: circles`; the card holds `diameterRow` + `circlesRow` (no per-action duration rows, no «Всего» footer — the duration is shown in the sim caption):
```swift
                if trick.id == Tricks.donut.id {
                    // One shared scroll: animation + stats + diameter + circle count scroll together.
                    ScrollView {
                        VStack(spacing: 16) {
                            TrickSimView(trick: Tricks.donutTrick(diameterCm: Double(diameterCm)),
                                         durs: durs, palette: p, donutCircles: circles)
                            VStack(spacing: 0) {
                                diameterRow.padding(.horizontal, 14)
                                Rectangle().fill(p.metal.opacity(0.25)).frame(height: 1)
                                circlesRow.padding(.horizontal, 14)
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

- [ ] **Step 3: Add the `circlesRow` view** (place it right after the `diameterRow` property)

```swift
    @ViewBuilder private var circlesRow: some View {
        let isDefault = circles == Tricks.donutCirclesDefault
        HStack(spacing: 11) {
            Text(L.simCircles).font(.system(size: 13)).foregroundStyle(p.text)
                .frame(width: 150, alignment: .leading)
            Spacer()
            stepButton("minus") {
                circles = Swift.max(Tricks.donutCirclesMin, circles - 1); TrickSettings.setDonutCircles(circles)
            }.disabled(circles <= Tricks.donutCirclesMin)
            Text("\(circles)").font(.system(size: 15, weight: .semibold))
                .foregroundStyle(p.accent).monospacedDigit().frame(width: 34)
            stepButton("plus") {
                circles = Swift.min(Tricks.donutCirclesMax, circles + 1); TrickSettings.setDonutCircles(circles)
            }.disabled(circles >= Tricks.donutCirclesMax)
            Button {
                circles = Tricks.donutCirclesDefault; TrickSettings.resetDonutCircles()
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

    private func stepButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(p.accent).frame(width: 36, height: 32)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(p.accent.opacity(0.4)))
        }
        .buttonStyle(.plain)
    }
```

- [ ] **Step 4: Commit**

```bash
git add ios/ESP32Car/TrickEditorView.swift
git commit -m "feat(ios): donut editor — circle-count stepper replaces the duration slider"
```

---

### Task 6: Stream the donut at the chosen circle count (`DriveView`)

**Files:**
- Modify: `ios/ESP32Car/DriveView.swift`

- [ ] **Step 1: Build the timed donut inside `startTrick`'s task**

In `ios/ESP32Car/DriveView.swift`, replace the whole `startTrick(_:)` function:
```swift
    private func startTrick(_ base: Trick) {
        trickTask?.cancel()
        // The donut's (t,y) comes from the user-set circle diameter; other tricks use their base.
        let effectiveBase = base.id == Tricks.donut.id
            ? Tricks.donutTrick(diameterCm: Double(TrickSettings.donutDiameterCm())) : base
        let trick = Tricks.withDurations(effectiveBase, TrickSettings.durations(for: effectiveBase))  // per-action durations; totalMs drives the ring
        runningTrick = trick
        trickStartedAt = Date()
        trickTask = Task {
            for step in trick.steps {
                conn.setCommand(ControlModel.frame(t: step.t, y: step.y))
                curT = step.t; curY = step.y                  // drive the on-screen diagram/power bars
                try? await Task.sleep(nanoseconds: UInt64(step.ms) * 1_000_000)
                if Task.isCancelled { return }
            }
            conn.setCommand(ControlModel.frame(t: 0, y: 0))   // natural end → stop
            curT = 0; curY = 0
            runningTrick = nil; trickStartedAt = nil
        }
    }
```
with (the donut is built inside the task because its ms needs `vmax` from `/wheel`, which is async; the ring/diagram setup moves in too, just after the brief fetch):
```swift
    private func startTrick(_ base: Trick) {
        trickTask?.cancel()
        trickTask = Task {
            let trick: Trick
            if base.id == Tricks.donut.id {
                // The donut's (t,y) comes from the diameter; its duration from the circle count,
                // timed at the real motor speed (nominal fallback when /wheel is unavailable).
                let vmax = await donutVmaxMS()
                trick = Tricks.donutTrick(diameterCm: Double(TrickSettings.donutDiameterCm()),
                                          circles: TrickSettings.donutCircles(), vmaxMS: vmax)
            } else {
                trick = Tricks.withDurations(base, TrickSettings.durations(for: base))  // per-action durations
            }
            runningTrick = trick
            trickStartedAt = Date()                            // totalMs drives the ring
            for step in trick.steps {
                conn.setCommand(ControlModel.frame(t: step.t, y: step.y))
                curT = step.t; curY = step.y                  // drive the on-screen diagram/power bars
                try? await Task.sleep(nanoseconds: UInt64(step.ms) * 1_000_000)
                if Task.isCancelled { return }
            }
            conn.setCommand(ControlModel.frame(t: 0, y: 0))   // natural end → stop
            curT = 0; curY = 0
            runningTrick = nil; trickStartedAt = nil
        }
    }

    /// Linear speed (m/s) from the car's wheel/motor params, with a nominal fallback.
    private func donutVmaxMS() async -> Double {
        guard let w = await WheelClient().get(),
              let rpm = MotorPresets.match(ppr: w.ppr, gearX100: w.gearX100, quad: w.quad)?.rpm
        else { return Tricks.donutNominalVmaxMS }
        return Double.pi * (Double(w.diameterMm) / 1000) * Double(rpm) / 60
    }
```

- [ ] **Step 2: Commit**

```bash
git add ios/ESP32Car/DriveView.swift
git commit -m "feat(ios): stream the donut at the user-set circle count"
```

---

### Task 7: Build + simulator verification

**Files:** Temporary, reverted — `ios/ESP32Car/GalleryView.swift`.

- [ ] **Step 1: Re-run the host checks (circles round-trip)**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
swiftc ios/ESP32Car/ControlModel.swift ios/ESP32Car/TrickSim.swift ios/ESP32Car/Tricks.swift /tmp/circles.swift -o /tmp/dc && /tmp/dc
```
(Recreate `/tmp/circles.swift` from Task 1 Step 1 if absent.) Expected: `donut circles: all passed`.

- [ ] **Step 2: Build the iOS target**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate
xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -6
```
Expected: `** BUILD SUCCEEDED **`. Fix any compile error in a feature file minimally and rebuild; report fixes.

- [ ] **Step 3: Screenshot the donut editor (mock running, circle stepper visible)**

Temporarily add a gallery frame + seed index, build, install, launch (the mock serves `/wheel` so the sim computes a real circle count):
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
sleep 4; xcrun simctl io booted screenshot /tmp/circ.png >/dev/null 2>&1
sips --rotate 90 /tmp/circ.png --out /tmp/circ_90.png >/dev/null 2>&1 && echo "screenshot /tmp/circ_90.png"
```
Eyeball `/tmp/circ_90.png` (rotate 270 if upside-down): the donut editor shows the animation, then a card with TWO rows — «Диаметр круга — 50 см» (slider) on top and «Круги  − 2 +» (stepper) below; the sim caption reads «За ~6.9 с — 2.0 оборота». No «Всего» footer.

- [ ] **Step 4: Revert the temporary gallery edits**

Set `@State private var index` back to `0` and remove the `"TrickEditor donut"` frame line. Confirm `git diff --stat ios/ESP32Car/GalleryView.swift` shows NO changes.

- [ ] **Step 5: No commit** (verification only).

---

## Self-Review

**Spec coverage:**
- `donutDurationMs(circles:y:vmaxMS:)` (= N·π·track/(vmax·y), guards) → Task 1. ✅
- `donutTrick(diameterCm:circles:vmaxMS:)` builds the timed donut, keeps id/name/icon → Task 1. ✅
- Consts `donutCirclesMin/Max/Default = 1/10/2`, `donutNominalVmaxMS` → Task 1. ✅
- Persist circle count in TrickSettings (clamp 1–10) → Task 2. ✅
- Same-`vmax` invariant: sim overrides donut ms with its own `vmaxMS` → Task 4; stream computes `vmax` from `/wheel` → Task 6. ✅
- Stepper (− / N / +) replaces the duration slider; donut «Всего» footer dropped → Task 5. ✅
- Localization «Круги», no Cyrillic in Swift → Task 3 (label via `L.simCircles`; digits via `\(circles)`). ✅
- Nominal fallback when `/wheel`/rpm missing → Task 6 (`donutVmaxMS`). ✅
- Host tests (round-trip revolutions, default ms, guards) → Task 1. ✅
- Out of scope (other tricks, firmware, editable track, fractional circles) → untouched. ✅

**Placeholder scan:** none — full code in every code step. ✅

**Type/name consistency:** `donutDurationMs(circles:y:vmaxMS:)`/`donutTrick(diameterCm:circles:vmaxMS:)`/`donutCirclesMin`/`donutCirclesMax`/`donutCirclesDefault`/`donutNominalVmaxMS` defined in Task 1, used in Tasks 4/5/6; `TrickSettings.donutCircles()`/`setDonutCircles(_:)`/`resetDonutCircles()` defined in Task 2, used in Tasks 5/6; `L.simCircles` defined in Task 3, used in Task 5; `TrickSimView` gains `donutCircles: Int? = nil` (Task 4) and is called with it in Task 5; `vmaxMS` computed prop added in Task 4 and used by both `steps` and `sim`; `WheelClient().get()`/`MotorPresets.match(ppr:gearX100:quad:)?.rpm` exist (Task 6); `TrickSim.Result.turnRad`, `Tricks.donutTrackM`, `Tricks.donutSides`, `p.accent`/`p.muted`/`p.text`/`p.line`/`p.metal`/`p.panel` all exist. ✅
