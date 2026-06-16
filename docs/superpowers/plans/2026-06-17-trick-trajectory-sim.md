# Trick Trajectory Simulation (v1 — Donut) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** For the donut trick, show a top-down animated trajectory simulation (left) beside the duration controls (right) in `TrickEditorView`, with the swept body area, a dimensioned bounding box (cm), and stats (distance, revolutions) computed from motor RPM + wheel diameter.

**Architecture:** A pure differential-drive integrator `TrickSim` (host-tested) turns a trick's `{t,y,ms}` timeline + `vmax` (from rated RPM × wheel diameter) + car dimensions into pose samples + path length + total rotation + swept bounding box. `TrickSimView` (Canvas + TimelineView) draws and animates it; `TrickEditorView` shows it in a split layout for the donut only (other tricks unchanged). iOS-only — reuses `/wheel` (`WheelClient`) and `MotorPresets`; no firmware change.

**Tech Stack:** SwiftUI (Swift 6, Canvas, TimelineView), `swiftc` host tests, `enum L` localization.

**Spec:** `docs/superpowers/specs/2026-06-17-trick-trajectory-sim-design.md`

**Branch:** `feat/trick-sim` (already created, spec committed there).

---

## File Structure

- `ios/ESP32Car/TrickSim.swift` — **new, pure**: `TrickSim.simulate(...) -> Result` (poses, pathLenM, turnRad, bbox).
- `ios/ESP32CarTests/TrickSimTests.swift` — **new**: XCTest mirror of the host checks.
- `ios/ESP32Car/TrickSimView.swift` — **new**: Canvas animation + 3 stat chips + verdict + "pick motor" placeholder.
- `ios/ESP32Car/TrickEditorView.swift` — **modify**: extract `controls`; donut → split (sim left, controls right).
- `ios/ESP32Car/L.swift`, `ios/ESP32Car/Resources/ru.lproj/Localizable.strings` — **modify**: sim labels.

Reuses (no change): `ControlModel.sides(t:y:)`, `WheelClient.Params`, `MotorPresets.match/.rpm`, `Tricks.withDurations/.baseDurations/.distinctActions`.

---

### Task 1: `TrickSim` model + host tests

**Files:**
- Create: `ios/ESP32Car/TrickSim.swift`, `ios/ESP32CarTests/TrickSimTests.swift`

- [ ] **Step 1: Write the host-test driver `/tmp/main.swift`**

```swift
import Foundation
func approx(_ a: Double, _ b: Double, _ tol: Double, _ what: String) {
    assert(abs(a - b) <= tol, "\(what): \(a) vs \(b) (tol \(tol))")
}
// Straight line: t=1,y=0 for 1 s at vmax=1 → ~1 m, no rotation; swept box ~ (1+carLen) x carWid
let straight = TrickSim.simulate(steps: [TrickStep(t: 1, y: 0, ms: 1000)],
                                 vmaxMS: 1, trackM: 0.15, carLenM: 0.25, carWidM: 0.15)
approx(straight.pathLenM, 1.0, 0.02, "straight path")
approx(straight.turnRad, 0.0, 0.01, "straight turn")
approx(straight.areaWM, 1.25, 0.03, "straight areaW")
approx(straight.areaHM, 0.15, 0.01, "straight areaH")
// Spin in place: t=0,y=1 → no translation, lots of rotation
let spin = TrickSim.simulate(steps: [TrickStep(t: 0, y: 1, ms: 1000)],
                             vmaxMS: 1, trackM: 0.15, carLenM: 0.25, carWidM: 0.15)
approx(spin.pathLenM, 0.0, 0.01, "spin path")
approx(spin.turnRad, 2.0 / 0.15, 0.2, "spin turn")   // |vR-vL|/track = 2/0.15 rad/s * 1 s
// Donut: t=0.7,y=1 → sides (1.0, -0.176) → curved path + rotation, both > 0
let donut = TrickSim.simulate(steps: [TrickStep(t: 0.7, y: 1, ms: 1000)],
                              vmaxMS: 1, trackM: 0.15, carLenM: 0.25, carWidM: 0.15)
assert(donut.pathLenM > 0.3 && donut.pathLenM < 0.5, "donut path \(donut.pathLenM)")
assert(donut.turnRad > 6 && donut.turnRad < 9, "donut turn \(donut.turnRad)")
assert(donut.poses.count > 5, "donut poses")
print("TrickSim: all passed")
```

- [ ] **Step 2: Run it to verify it fails (no TrickSim yet)**

Run: `cd /Users/adamjohnson/VSCode/esp32-p4-car && swiftc ios/ESP32Car/ControlModel.swift ios/ESP32Car/Tricks.swift ios/ESP32Car/TrickSim.swift /tmp/main.swift -o /tmp/ts`
Expected: FAIL — `error: no such file or directory: 'ios/ESP32Car/TrickSim.swift'`.

- [ ] **Step 3: Write `ios/ESP32Car/TrickSim.swift`**

```swift
import Foundation

/// Open-loop differential-drive ("tank") kinematics for a trick timeline.
/// Idealized (no wheel slip) — a real maneuver skids wider; this is a planning estimate.
struct TrickSim {
    struct Pose { let x: Double; let y: Double; let theta: Double }   // metres, radians
    struct Result {
        let poses: [Pose]        // car-centre samples for drawing/animation
        let pathLenM: Double     // arc length of the centre path
        let turnRad: Double       // accumulated |heading change| → revolutions = turnRad / 2π
        let minX: Double; let minY: Double; let maxX: Double; let maxY: Double  // swept-body bbox
        var areaWM: Double { maxX - minX }
        var areaHM: Double { maxY - minY }
    }

    /// vmaxMS = π·D·rpm/60 (m/s). trackM = lateral wheel separation. car dims in metres.
    static func simulate(steps: [TrickStep], vmaxMS: Double, trackM: Double,
                         carLenM: Double, carWidM: Double, dtMS: Int = 10) -> Result {
        var x = 0.0, y = 0.0, th = 0.0
        var pathLen = 0.0, turn = 0.0
        var minX = 0.0, minY = 0.0, maxX = 0.0, maxY = 0.0
        var poses: [Pose] = []

        // Expand the swept bbox by the car's 4 corners at a pose.
        func expand(_ px: Double, _ py: Double, _ pth: Double) {
            let hl = carLenM / 2, hw = carWidM / 2
            let c = cos(pth), s = sin(pth)
            for sx in [hl, -hl] {
                for sy in [hw, -hw] {
                    let cx = px + sx * c - sy * s
                    let cy = py + sx * s + sy * c
                    minX = Swift.min(minX, cx); maxX = Swift.max(maxX, cx)
                    minY = Swift.min(minY, cy); maxY = Swift.max(maxY, cy)
                }
            }
        }

        let dt = Double(dtMS) / 1000
        let sampleEvery = Swift.max(1, 30 / Swift.max(1, dtMS))   // ~30 ms between drawn poses
        poses.append(Pose(x: x, y: y, theta: th))
        expand(x, y, th)
        var tick = 0
        for step in steps {
            let (l, r) = ControlModel.sides(t: step.t, y: step.y)
            let vL = l * vmaxMS, vR = r * vmaxMS
            let v = (vL + vR) / 2
            let w = (vR - vL) / trackM
            let n = Swift.max(1, Int((Double(step.ms) / 1000) / dt + 0.5))
            for _ in 0..<n {
                th += w * dt
                let dx = v * cos(th) * dt, dy = v * sin(th) * dt
                x += dx; y += dy
                pathLen += abs(v) * dt
                turn += abs(w) * dt
                expand(x, y, th)
                tick += 1
                if tick % sampleEvery == 0 { poses.append(Pose(x: x, y: y, theta: th)) }
            }
        }
        if let last = poses.last, last.x != x || last.y != y || last.theta != th {
            poses.append(Pose(x: x, y: y, theta: th))
        }
        return Result(poses: poses, pathLenM: pathLen, turnRad: turn,
                      minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }
}
```

- [ ] **Step 4: Run the host check to verify it passes**

Run: `cd /Users/adamjohnson/VSCode/esp32-p4-car && swiftc ios/ESP32Car/ControlModel.swift ios/ESP32Car/Tricks.swift ios/ESP32Car/TrickSim.swift /tmp/main.swift -o /tmp/ts && /tmp/ts`
Expected: `TrickSim: all passed`

- [ ] **Step 5: Write the XCTest mirror `ios/ESP32CarTests/TrickSimTests.swift`**

```swift
import XCTest
@testable import ESP32Car

final class TrickSimTests: XCTestCase {
    func testStraightLine() {
        let r = TrickSim.simulate(steps: [TrickStep(t: 1, y: 0, ms: 1000)],
                                  vmaxMS: 1, trackM: 0.15, carLenM: 0.25, carWidM: 0.15)
        XCTAssertEqual(r.pathLenM, 1.0, accuracy: 0.02)
        XCTAssertEqual(r.turnRad, 0.0, accuracy: 0.01)
        XCTAssertEqual(r.areaWM, 1.25, accuracy: 0.03)
        XCTAssertEqual(r.areaHM, 0.15, accuracy: 0.01)
    }
    func testSpinInPlace() {
        let r = TrickSim.simulate(steps: [TrickStep(t: 0, y: 1, ms: 1000)],
                                  vmaxMS: 1, trackM: 0.15, carLenM: 0.25, carWidM: 0.15)
        XCTAssertEqual(r.pathLenM, 0.0, accuracy: 0.01)
        XCTAssertEqual(r.turnRad, 2.0 / 0.15, accuracy: 0.2)
    }
    func testDonutCurves() {
        let r = TrickSim.simulate(steps: [TrickStep(t: 0.7, y: 1, ms: 1000)],
                                  vmaxMS: 1, trackM: 0.15, carLenM: 0.25, carWidM: 0.15)
        XCTAssertTrue(r.pathLenM > 0.3 && r.pathLenM < 0.5)
        XCTAssertTrue(r.turnRad > 6 && r.turnRad < 9)
        XCTAssertGreaterThan(r.poses.count, 5)
    }
}
```

- [ ] **Step 6: Commit**

```bash
git add ios/ESP32Car/TrickSim.swift ios/ESP32CarTests/TrickSimTests.swift
git commit -m "feat(ios): TrickSim — differential-drive trajectory integrator (host-tested)"
```

---

### Task 2: Localization keys

**Files:**
- Modify: `ios/ESP32Car/Resources/ru.lproj/Localizable.strings`, `ios/ESP32Car/L.swift`

- [ ] **Step 1: Add strings to `Localizable.strings`** (append near the other entries)

```
"sim.path"      = "Путь";
"sim.turns"     = "Оборотов";
"sim.area"      = "Область";
"sim.verdict"   = "За %.1f с — %.1f оборота";
"sim.pickMotor" = "Выберите модель мотора для расчёта";
"unit.m"        = "м";
"unit.cm"       = "см";
```

- [ ] **Step 2: Add accessors to `L.swift`** (inside `enum L`, near the other unit/sim entries)

```swift
    static var simPath: String { s("sim.path") }
    static var simTurns: String { s("sim.turns") }
    static var simArea: String { s("sim.area") }
    static func simVerdict(_ sec: Double, _ turns: Double) -> String { s("sim.verdict", sec, turns) }
    static var simPickMotor: String { s("sim.pickMotor") }
    static var mUnit: String { s("unit.m") }
    static var cmUnit: String { s("unit.cm") }
```

- [ ] **Step 3: Commit**

```bash
git add ios/ESP32Car/L.swift ios/ESP32Car/Resources/ru.lproj/Localizable.strings
git commit -m "feat(ios): localization for the trick simulation stats"
```

---

### Task 3: `TrickSimView` (Canvas animation + stats)

**Files:**
- Create: `ios/ESP32Car/TrickSimView.swift`

- [ ] **Step 1: Write `ios/ESP32Car/TrickSimView.swift`**

```swift
import SwiftUI

/// Top-down animated trajectory simulation for a trick. Loads wheel params (/wheel), derives the
/// motor's rated RPM from MotorPresets, runs TrickSim, and draws the path + swept body + dimensioned
/// bounding box + the moving car, with distance/revolutions/area stats. iOS-only.
struct TrickSimView: View {
    let trick: Trick
    let durs: [Int]
    let palette: Palette
    @State private var wheel: WheelClient.Params?
    private var p: Palette { palette }

    // Car geometry — v1 constants (metres). TODO: move to settings next to the motor params.
    private static let carLenM = 0.25, carWidM = 0.15, trackM = 0.13

    private var steps: [TrickStep] {
        let d = durs.isEmpty ? Tricks.baseDurations(trick) : durs
        return Tricks.withDurations(trick, d).steps
    }
    private var totalSec: Double { Double(steps.reduce(0) { $0 + $1.ms }) / 1000 }

    private var rpm: Int? {
        guard let w = wheel else { return nil }
        return MotorPresets.match(ppr: w.ppr, gearX100: w.gearX100, quad: w.quad)?.rpm
    }
    private var sim: TrickSim.Result? {
        guard let w = wheel, let rpm else { return nil }
        let vmax = Double.pi * (Double(w.diameterMm) / 1000) * Double(rpm) / 60
        return TrickSim.simulate(steps: steps, vmaxMS: vmax, trackM: Self.trackM,
                                 carLenM: Self.carLenM, carWidM: Self.carWidM)
    }

    var body: some View {
        VStack(spacing: 10) {
            if let r = sim {
                TimelineView(.animation) { tl in
                    Canvas { ctx, size in
                        draw(&ctx, size, r, time: tl.date.timeIntervalSinceReferenceDate)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                stats(r)
            } else {
                Spacer()
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .font(.system(size: 28)).foregroundStyle(p.muted)
                Text(L.simPickMotor).font(.system(size: 13)).foregroundStyle(p.muted)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
                Spacer()
            }
        }
        .padding(12)
        .task { wheel = await WheelClient().get() }
    }

    // MARK: stats
    private func stats(_ r: TrickSim.Result) -> some View {
        let turns = r.turnRad / (2 * .pi)
        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                chip(L.simPath, String(format: "%.1f %@", r.pathLenM, L.mUnit))
                chip(L.simTurns, String(format: "%.1f", turns))
                chip(L.simArea, String(format: "%d×%d %@", Int((r.areaWM * 100).rounded()),
                                       Int((r.areaHM * 100).rounded()), L.cmUnit))
            }
            Text(L.simVerdict(totalSec, turns)).font(.system(size: 12)).foregroundStyle(p.muted)
        }
    }
    private func chip(_ key: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 16, weight: .bold)).foregroundStyle(p.accent).monospacedDigit()
            Text(key).font(.system(size: 9, weight: .semibold)).foregroundStyle(p.muted)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 7)
        .background(p.panel).clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(p.metal.opacity(0.4), lineWidth: 1))
    }

    // MARK: drawing
    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ r: TrickSim.Result, time: Double) {
        let pad: CGFloat = 30   // room for dimension labels
        let bw = max(r.areaWM, 1e-3), bh = max(r.areaHM, 1e-3)
        let cx = (r.minX + r.maxX) / 2, cy = (r.minY + r.maxY) / 2
        let scale = min((size.width - 2 * pad) / bw, (size.height - 2 * pad) / bh)
        func toS(_ wx: Double, _ wy: Double) -> CGPoint {
            CGPoint(x: size.width / 2 + (wx - cx) * scale, y: size.height / 2 - (wy - cy) * scale)
        }
        let carL = Self.carLenM * scale, carW = Self.carWidM * scale

        // car body path at a pose (rounded rect, forward = +x in body frame)
        func carPath(_ pose: TrickSim.Pose) -> Path {
            let c = toS(pose.x, pose.y)
            let t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: -pose.theta)
            return Path(roundedRect: CGRect(x: -carL / 2, y: -carW / 2, width: carL, height: carW),
                        cornerRadius: 3).applying(t)
        }

        // 1) swept area: faint body ghosts along the path
        for pose in r.poses {
            ctx.fill(carPath(pose), with: .color(p.accent.opacity(0.06)))
        }
        // 2) centre trajectory (dashed green)
        var path = Path()
        for (i, pose) in r.poses.enumerated() {
            let s = toS(pose.x, pose.y)
            if i == 0 { path.move(to: s) } else { path.addLine(to: s) }
        }
        ctx.stroke(path, with: .color(p.accent.opacity(0.7)),
                   style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 5]))
        // 3) bounding box + cm dimension labels
        let tl = toS(r.minX, r.maxY), br = toS(r.maxX, r.minY)
        let box = CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y)
        ctx.stroke(Path(box), with: .color(p.muted.opacity(0.5)),
                   style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        let wCm = Int((r.areaWM * 100).rounded()), hCm = Int((r.areaHM * 100).rounded())
        ctx.draw(Text("\(wCm) \(L.cmUnit)").font(.system(size: 11, weight: .semibold))
                    .foregroundColor(p.muted), at: CGPoint(x: box.midX, y: box.minY - 12))
        ctx.draw(Text("\(hCm) \(L.cmUnit)").font(.system(size: 11, weight: .semibold))
                    .foregroundColor(p.muted), at: CGPoint(x: box.minX - 16, y: box.midY))
        // 4) the moving car at the current phase
        if r.poses.count > 1, totalSec > 0 {
            let phase = (time.truncatingRemainder(dividingBy: totalSec)) / totalSec
            let idx = min(r.poses.count - 1, max(0, Int(phase * Double(r.poses.count - 1))))
            let pose = r.poses[idx]
            let cp = carPath(pose)
            ctx.fill(cp, with: .color(p.panel))
            ctx.stroke(cp, with: .color(p.accent), lineWidth: 2)
            // windshield mark at the front
            let fc = toS(pose.x, pose.y)
            let ft = CGAffineTransform(translationX: fc.x, y: fc.y).rotated(by: -pose.theta)
            ctx.fill(Path(roundedRect: CGRect(x: carL / 2 - carW * 0.35, y: -carW * 0.3,
                                              width: carW * 0.3, height: carW * 0.6),
                          cornerRadius: 2).applying(ft), with: .color(p.accent.opacity(0.5)))
        }
    }
}
```

- [ ] **Step 2: Commit** (compiles with the target in Task 5)

```bash
git add ios/ESP32Car/TrickSimView.swift
git commit -m "feat(ios): TrickSimView — Canvas trajectory animation + distance/turns/area stats"
```

---

### Task 4: Donut split in `TrickEditorView`

**Files:**
- Modify: `ios/ESP32Car/TrickEditorView.swift`

- [ ] **Step 1: Extract the existing controls into a `controls` view and branch the body**

Replace the current `body` (the `ZStack { … VStack { header; List {…}; Text(total) } }`) with a version that branches on the donut, and add a `controls` builder. Replace from `var body: some View {` through its closing brace, AND keep `header`, `row`, `actionLabel`, `totalSec`, `actions`, state, etc. unchanged. New `body` + `controls`:

```swift
    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if trick.id == Tricks.donut.id {
                    HStack(spacing: 0) {
                        TrickSimView(trick: trick, durs: durs, palette: p)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Rectangle().fill(p.metal.opacity(0.25)).frame(width: 1)
                        controls.frame(width: 300)
                    }
                } else {
                    controls
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { if durs.isEmpty { durs = TrickSettings.durations(for: trick) } }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            List {
                ForEach(actions.indices, id: \.self) { i in
                    row(i)
                        .listRowBackground(p.panel)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                }
            }
            .scrollContentBackground(.hidden)
            .tint(p.accent)
            Text(L.trickTotal(totalSec))
                .font(.system(size: 12)).foregroundStyle(p.muted).monospacedDigit()
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
    }
```

(The non-donut path renders `controls` exactly as the screen looked before — same List rows + footer total. Only the donut adds the left simulation pane.)

- [ ] **Step 2: Commit**

```bash
git add ios/ESP32Car/TrickEditorView.swift
git commit -m "feat(ios): donut trick editor shows the trajectory simulation (split layout)"
```

---

### Task 5: Build + simulator verification

**Files:** Temporary, reverted — `ios/ESP32Car/GalleryView.swift` (gallery frame to screenshot the donut editor).

- [ ] **Step 1: Re-run the host check (TrickSim still green)**

Run: `cd /Users/adamjohnson/VSCode/esp32-p4-car && swiftc ios/ESP32Car/ControlModel.swift ios/ESP32Car/Tricks.swift ios/ESP32Car/TrickSim.swift /tmp/main.swift -o /tmp/ts && /tmp/ts`
Expected: `TrickSim: all passed` (recreate `/tmp/main.swift` from Task 1 Step 1 if absent).

- [ ] **Step 2: Build the iOS target**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate
xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -8
```
Expected: `** BUILD SUCCEEDED **`. If a compile error is in one of the new feature files, fix it minimally (faithful to the intent) and rebuild; report any fix. If iPhone 17 is unavailable, pick an available iPhone sim via `xcodebuild -scheme ESP32Car -showdestinations 2>&1 | grep -i iPhone | head`.

- [ ] **Step 3: Temporarily add a donut-editor gallery frame + seed the index**

In `ios/ESP32Car/GalleryView.swift`, inside `makeFrames`'s returned array, add as the LAST entry (before the closing `]`):
```swift
            ("TrickEditor donut",       AnyView(NavigationStack { TrickEditorView(trick: Tricks.donut, palette: p) })),
```
and change `@State private var index = 0` to `@State private var index = 27`. Rebuild + install + launch with the mock car running (it serves `/wheel` = 65/11/2100/4 → matches JGA25-370, rpm 170):
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
curl -s http://127.0.0.1:8080/wheel >/dev/null 2>&1 || (cd tools/mock_car && nohup .venv/bin/python -u mock_car.py >/tmp/mock_car.log 2>&1 & sleep 2)
cd ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -2
APP=$(find /tmp/ddata/Build/Products -name ESP32Car.app | head -1)
xcrun simctl boot "iPhone 17" 2>/dev/null; open -a Simulator
xcrun simctl install booted "$APP"
xcrun simctl terminate booted com.adamjohnson.esp32car 2>/dev/null
xcrun simctl launch booted com.adamjohnson.esp32car --args -gallery >/dev/null
sleep 4
xcrun simctl io booted screenshot /tmp/sim.png >/dev/null 2>&1
sips --rotate 90 /tmp/sim.png --out /tmp/sim_90.png >/dev/null 2>&1 && echo "screenshot /tmp/sim_90.png"
```
Eyeball `/tmp/sim_90.png` (rotate 270 instead if it comes out upside-down): left = animated donut path + faint swept body + dashed bounding box with cm labels + moving car; 3 stat chips (Путь ~1.2 м, Оборотов ~4, Область ~NN×NN см) + verdict; right = one «Вперёд-вправо» slider + «Всего».

- [ ] **Step 4: Revert the temporary gallery edits**

Set `@State private var index` back to `0` and remove the `"TrickEditor donut"` frame line. Confirm: `git diff --stat ios/ESP32Car/GalleryView.swift` shows NO changes.

- [ ] **Step 5: No commit** (verification only; Tasks 1–4 already committed).

---

## Self-Review

**Spec coverage:**
- `TrickSim.simulate` (poses, pathLenM, turnRad, bbox) + differential integration via `ControlModel.sides` → Task 1. ✅
- Car constants 0.25/0.15/0.13 (TODO settings) → Task 3 (`TrickSimView` statics). ✅
- vmax = π·D·rpm/60; diameter from `/wheel`, rpm from `MotorPresets.match`; custom → placeholder → Task 3. ✅
- Host tests (straight/spin/donut) → Task 1. ✅
- Left pane: swept ghosts, dashed path, bbox + cm labels, moving car, auto-scale, TimelineView loop → Task 3 `draw`. ✅
- 3 chips (Путь/Оборотов/Область) + verdict → Task 3 `stats`. ✅
- Donut-only split; other tricks unchanged → Task 4 (branch on `trick.id == Tricks.donut.id`; `controls` reproduces the prior layout). ✅
- Localization, no Cyrillic in Swift → Task 2 (labels via `L`; only format specifiers/`×`/digits inline). ✅
- iOS-only, no firmware/mock change → no firmware tasks. ✅

**Placeholder scan:** none — full code in every code step. ✅

**Type/name consistency:** `TrickSim.Result` fields (`poses`, `pathLenM`, `turnRad`, `minX/minY/maxX/maxY`, computed `areaWM/areaHM`) defined in Task 1 and used in Task 3; `TrickSim.simulate(steps:vmaxMS:trackM:carLenM:carWidM:dtMS:)` signature identical in Task 1 def, Task 1 driver, Task 3 caller; `TrickSimView(trick:durs:palette:)` defined in Task 3 and called in Task 4; `WheelClient.Params` fields `diameterMm/ppr/gearX100/quad` and `MotorPresets.match(ppr:gearX100:quad:)?.rpm` match the existing code; `L.simPath/simTurns/simArea/simVerdict/simPickMotor/mUnit/cmUnit` defined in Task 2 and used in Task 3; `ControlModel.sides(t:y:)` is the existing pure mixer. ✅
