# Figure-8 trick: loop diameter + eights count — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the «Восьмёрка» (figure-8) trick adjustable by loop diameter (cm) + number of eights, reusing the donut's geometry helpers, with a live simulation preview — iOS-only, no firmware change.

**Architecture:** A figure-8 = two tangent full circles in opposite turn directions. Each lobe is one donut loop, so the `(t, y)` command comes from `Tricks.donutSides` and each lobe's duration from `Tricks.donutDurationMs(circles: 1, …)`; the second lobe just flips the sign of `y`. The maneuver runs at full motor power (duration derived). Two `UserDefaults`-backed params drive the editor + the streamed timeline + the `TrickSim` preview.

**Tech Stack:** Swift 6 / SwiftUI, pure `Tricks`/`TrickSim` modules host-tested with `swiftc`, UI compile-checked with `xcodebuild` against the iPhone 17 simulator + the aiohttp mock car.

**Branch:** `feat/figure8-params` (already created off `main`). All tasks commit here.

---

### Task 1: `Tricks.figure8Trick` + constants (pure)

**Files:**
- Modify: `ios/ESP32Car/Tricks.swift` (add after the spin section, ~line 97)
- Test: `ios/ESP32CarTests/TrickSimTests.swift` (append XCTest cases) + a temporary `swiftc` driver `/tmp/fig8_main.swift`

- [ ] **Step 1: Write the failing host-driver test**

Create `/tmp/fig8_main.swift`:

```swift
import Foundation

func approx(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool { abs(a - b) < eps }

let T = 0.13
let sides = Tricks.donutSides(diameterCm: 60, trackM: T)

// geometry: 2 lobes per eight, mirrored y, constant positive t, keeps figure8 id
let g = Tricks.figure8Trick(diameterCm: 60, eights: 3, vmaxMS: 0.578, trackM: T)
assert(g.steps.count == 6, "step count \(g.steps.count)")
assert(approx(g.steps[0].t, sides.t), "t0")
assert(approx(g.steps[0].y, sides.y), "y0")
assert(approx(g.steps[1].y, -sides.y), "y1 mirror")
assert(approx(g.steps[0].t, g.steps[1].t), "t constant")
assert(g.steps[0].t > 0, "t positive")
assert(g.id == Tricks.figure8.id, "id")

// degenerate speed → ms 0, no crash
let d = Tricks.figure8Trick(diameterCm: 50, eights: 2, vmaxMS: 0, trackM: T)
assert(d.steps.count == 4 && d.steps.allSatisfy { $0.ms == 0 }, "degenerate")

// round-trip through the simulation: turns ≈ 2·eights, the 8 returns near its start
let V = Tricks.donutNominalVmaxMS
for eights in [1, 2] {
    let tr = Tricks.figure8Trick(diameterCm: 60, eights: eights, vmaxMS: V, trackM: T)
    let r = TrickSim.simulate(steps: tr.steps, vmaxMS: V, trackM: T, carLenM: 0.25, carWidM: 0.15)
    let turns = r.turnRad / (2 * Double.pi)
    assert(abs(turns - Double(2 * eights)) < 0.2, "turns \(turns) for eights \(eights)")
    let last = r.poses.last!
    assert(hypot(last.x, last.y) < 0.6 * 0.5, "figure-8 closes (\(last.x), \(last.y))")
}
print("OK fig8")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd ios/ESP32Car && swiftc Tricks.swift TrickSim.swift /tmp/fig8_main.swift -o /tmp/fig8check && /tmp/fig8check`
Expected: FAIL — compile error `value of type 'Tricks.Type' has no member 'figure8Trick'`.

- [ ] **Step 3: Implement the constants + `figure8Trick`**

In `ios/ESP32Car/Tricks.swift`, after the spin `spinTrick(...)` function (around line 97, before `// MARK: per-action durations`), add:

```swift
    // MARK: figure-8 geometry (pure, host-tested) — two tangent loops, each a full donut circle, the
    // second mirrored (−y). Reuses donutSides + donutDurationMs. `eights` repetitions of {left, right}.
    static let fig8DiaMinCm = 20, fig8DiaMaxCm = 150, fig8DiaDefaultCm = 50
    static let fig8EightsMin = 1, fig8EightsMax = 10, fig8EightsDefault = 1

    /// The figure-8 maneuver: `eights` repetitions of a left loop then its mirror right loop, each a full
    /// circle of the given diameter at speed `vmaxMS`. (t, y) from `donutSides`; per-lobe ms from
    /// `donutDurationMs(circles: 1)`. Keeps the figure8 id/name/icon. Degenerate speed → ms 0 (no crash).
    static func figure8Trick(diameterCm: Double, eights: Int, vmaxMS: Double, trackM: Double) -> Trick {
        let (t, y) = donutSides(diameterCm: diameterCm, trackM: trackM)
        let lobeMs = donutDurationMs(circles: 1, y: y, vmaxMS: vmaxMS, trackM: trackM)
        let n = Swift.max(fig8EightsMin, eights)
        let steps = (0..<n).flatMap { _ in
            [TrickStep(t: t, y: y, ms: lobeMs), TrickStep(t: t, y: -y, ms: lobeMs)]
        }
        return Trick(id: figure8.id, nameKey: figure8.nameKey, icon: figure8.icon, steps: steps)
    }
```

- [ ] **Step 4: Run the host driver to verify it passes**

Run: `cd ios/ESP32Car && swiftc Tricks.swift TrickSim.swift /tmp/fig8_main.swift -o /tmp/fig8check && /tmp/fig8check`
Expected: PASS — prints `OK fig8`.

- [ ] **Step 5: Mirror the assertions as permanent XCTest cases**

Append to `ios/ESP32CarTests/TrickSimTests.swift`, just before the closing `}` of `final class TrickSimTests`:

```swift
    func testFigure8Geometry() {
        let T = 0.13
        let sides = Tricks.donutSides(diameterCm: 60, trackM: T)
        let g = Tricks.figure8Trick(diameterCm: 60, eights: 3, vmaxMS: 0.578, trackM: T)
        XCTAssertEqual(g.steps.count, 6)                       // 2 lobes × 3 eights
        XCTAssertEqual(g.steps[0].t, sides.t, accuracy: 1e-9)
        XCTAssertEqual(g.steps[0].y, sides.y, accuracy: 1e-9)
        XCTAssertEqual(g.steps[1].y, -sides.y, accuracy: 1e-9) // mirror lobe
        XCTAssertEqual(g.steps[0].t, g.steps[1].t, accuracy: 1e-9)
        XCTAssertGreaterThan(g.steps[0].t, 0)
        XCTAssertEqual(g.id, Tricks.figure8.id)
    }

    func testFigure8Degenerate() {
        let g = Tricks.figure8Trick(diameterCm: 50, eights: 2, vmaxMS: 0, trackM: 0.13)
        XCTAssertEqual(g.steps.count, 4)
        XCTAssertTrue(g.steps.allSatisfy { $0.ms == 0 })
    }

    func testFigure8RoundTrip() {
        let V = Tricks.donutNominalVmaxMS, T = 0.13
        for eights in [1, 2] {
            let g = Tricks.figure8Trick(diameterCm: 60, eights: eights, vmaxMS: V, trackM: T)
            let r = TrickSim.simulate(steps: g.steps, vmaxMS: V, trackM: T, carLenM: 0.25, carWidM: 0.15)
            XCTAssertEqual(r.turnRad / (2 * .pi), Double(2 * eights), accuracy: 0.2)
            let last = r.poses.last!
            XCTAssertLessThan(hypot(last.x, last.y), 0.6 * 0.5)   // figure-8 returns near its start
        }
    }
```

- [ ] **Step 6: Re-run the host driver (regression) and commit**

Run: `cd ios/ESP32Car && swiftc Tricks.swift TrickSim.swift /tmp/fig8_main.swift -o /tmp/fig8check && /tmp/fig8check`
Expected: PASS — `OK fig8`.

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/Tricks.swift ios/ESP32CarTests/TrickSimTests.swift
git commit -m "feat(ios): Tricks.figure8Trick — diameter+eights via donut helpers (host-tested)"
```

---

### Task 2: Persist the two params in `TrickSettings`

**Files:**
- Modify: `ios/ESP32Car/TrickSettings.swift` (add after the spin-duration block, ~line 83)

- [ ] **Step 1: Add the figure-8 accessors**

In `ios/ESP32Car/TrickSettings.swift`, immediately before the final closing `}` of `enum TrickSettings`, add:

```swift
    private static let fig8DiaKey = "trick.fig8.dia"
    private static func clampFig8Dia(_ cm: Int) -> Int {
        Swift.min(Tricks.fig8DiaMaxCm, Swift.max(Tricks.fig8DiaMinCm, cm))
    }
    static func fig8Dia() -> Int {
        clampFig8Dia(UserDefaults.standard.object(forKey: fig8DiaKey) as? Int ?? Tricks.fig8DiaDefaultCm)
    }
    static func setFig8Dia(_ cm: Int) {
        UserDefaults.standard.set(clampFig8Dia(cm), forKey: fig8DiaKey)
    }
    static func resetFig8Dia() {
        UserDefaults.standard.removeObject(forKey: fig8DiaKey)
    }

    private static let fig8EightsKey = "trick.fig8.eights"
    private static func clampFig8Eights(_ n: Int) -> Int {
        Swift.min(Tricks.fig8EightsMax, Swift.max(Tricks.fig8EightsMin, n))
    }
    static func fig8Eights() -> Int {
        clampFig8Eights(UserDefaults.standard.object(forKey: fig8EightsKey) as? Int ?? Tricks.fig8EightsDefault)
    }
    static func setFig8Eights(_ n: Int) {
        UserDefaults.standard.set(clampFig8Eights(n), forKey: fig8EightsKey)
    }
    static func resetFig8Eights() {
        UserDefaults.standard.removeObject(forKey: fig8EightsKey)
    }
```

- [ ] **Step 2: Type-check it compiles against `Tricks`**

Run: `cd ios/ESP32Car && swiftc -typecheck TrickSettings.swift Tricks.swift`
Expected: PASS — no output (exit 0). A failure would name an undefined `Tricks.fig8*` constant.

- [ ] **Step 3: Commit**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/TrickSettings.swift
git commit -m "feat(ios): persist figure-8 loop diameter + eights in TrickSettings"
```

---

### Task 3: Localization strings

**Files:**
- Modify: `ios/ESP32Car/L.swift` (after `spinDuration`, ~line 117)
- Modify: `ios/ESP32Car/Resources/ru.lproj/Localizable.strings` (after the spin lines, ~line 122)

- [ ] **Step 1: Add the `L` accessors**

In `ios/ESP32Car/L.swift`, after the line `static var spinDuration: String { s("trick.spinDuration") }`, add:

```swift
    static var fig8Diameter: String { s("trick.fig8Diameter") }
    static var fig8Loops: String { s("trick.fig8Loops") }
```

- [ ] **Step 2: Add the Russian strings**

In `ios/ESP32Car/Resources/ru.lproj/Localizable.strings`, after the line `"trick.spinDuration"  = "Продолжительность";`, add:

```
"trick.fig8Diameter"  = "Диаметр петли";
"trick.fig8Loops"     = "Восьмёрок";
```

- [ ] **Step 3: Type-check `L.swift` compiles**

Run: `cd ios/ESP32Car && swiftc -typecheck L.swift`
Expected: PASS — no output (exit 0).

- [ ] **Step 4: Commit**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/L.swift ios/ESP32Car/Resources/ru.lproj/Localizable.strings
git commit -m "feat(ios): localization for the figure-8 loop diameter + eights labels"
```

---

### Task 4: `TrickSimView` builds the figure-8 from the two params

**Files:**
- Modify: `ios/ESP32Car/TrickSimView.swift` (props ~lines 11-14, `steps` ~lines 22-31)

- [ ] **Step 1: Add the two optional inputs**

In `ios/ESP32Car/TrickSimView.swift`, after the line `var spinDurMs: Int? = nil`, add:

```swift
    var fig8Dia: Double? = nil
    var fig8Eights: Int? = nil
```

- [ ] **Step 2: Add the figure-8 branch in `steps`**

In the computed `private var steps: [TrickStep]`, after the existing spin branch (the `if trick.id == Tricks.spin.id { … }` block) and before the `let d = durs.isEmpty …` fallback, add:

```swift
        if trick.id == Tricks.figure8.id, let dia = fig8Dia, let n = fig8Eights, let v = vmaxMS {
            return Tricks.figure8Trick(diameterCm: dia, eights: n, vmaxMS: v, trackM: track).steps
        }
```

- [ ] **Step 3: Build to verify it compiles**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate \
  && xcodebuild build -scheme ESP32Car \
     -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/TrickSimView.swift
git commit -m "feat(ios): TrickSimView builds the figure-8 from diameter + eights"
```

---

### Task 5: `TrickEditorView` figure-8 editor branch

**Files:**
- Modify: `ios/ESP32Car/TrickEditorView.swift` (`@State` ~line 12, body branch ~line 60, `onAppear` ~line 71, new rows after `durationRow` ~line 245)

- [ ] **Step 1: Add the `@State` for the two params**

In `ios/ESP32Car/TrickEditorView.swift`, after the line `@State private var spinDurMs = Tricks.spinDurDefaultMs`, add:

```swift
    @State private var fig8Dia = Tricks.fig8DiaDefaultCm
    @State private var fig8Eights = Tricks.fig8EightsDefault
```

- [ ] **Step 2: Load them in `onAppear`**

In `.onAppear { … }`, after the line `spinDurMs = TrickSettings.spinDurMs()`, add:

```swift
            fig8Dia = TrickSettings.fig8Dia()
            fig8Eights = TrickSettings.fig8Eights()
```

- [ ] **Step 3: Add the figure-8 branch to the body**

In `var body`, change the final `} else {` (the one wrapping `controls`, currently at ~line 60) so the figure-8 branch precedes it. Replace:

```swift
                } else {
                    controls
                }
```

with:

```swift
                } else if trick.id == Tricks.figure8.id {
                    // One shared scroll: animation + stats + loop diameter + eights count scroll together.
                    ScrollView {
                        VStack(spacing: 16) {
                            TrickSimView(trick: Tricks.figure8, durs: durs, palette: p,
                                         fig8Dia: Double(fig8Dia), fig8Eights: fig8Eights)
                            VStack(spacing: 0) {
                                fig8DiaRow.padding(.horizontal, 14)
                                Rectangle().fill(p.metal.opacity(0.25)).frame(height: 1)
                                fig8EightsRow.padding(.horizontal, 14)
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

- [ ] **Step 4: Add the two stepper rows**

In `ios/ESP32Car/TrickEditorView.swift`, after the `durationRow` computed property (ends ~line 245, before `private func stepButton`), add:

```swift
    @ViewBuilder private var fig8DiaRow: some View {
        let isDefault = fig8Dia == Tricks.fig8DiaDefaultCm
        HStack(spacing: 11) {
            Text(L.fig8Diameter).font(.system(size: 13)).foregroundStyle(p.text)
                .frame(width: 150, alignment: .leading)
            Spacer()
            stepButton("minus") {
                fig8Dia = Swift.max(Tricks.fig8DiaMinCm, fig8Dia - 10); TrickSettings.setFig8Dia(fig8Dia)
            }.disabled(fig8Dia <= Tricks.fig8DiaMinCm)
            Text("\(fig8Dia) \(L.cmUnit)").font(.system(size: 15, weight: .semibold))
                .foregroundStyle(p.accent).monospacedDigit().frame(width: 56)
            stepButton("plus") {
                fig8Dia = Swift.min(Tricks.fig8DiaMaxCm, fig8Dia + 10); TrickSettings.setFig8Dia(fig8Dia)
            }.disabled(fig8Dia >= Tricks.fig8DiaMaxCm)
            Button {
                fig8Dia = Tricks.fig8DiaDefaultCm; TrickSettings.resetFig8Dia()
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

    @ViewBuilder private var fig8EightsRow: some View {
        let isDefault = fig8Eights == Tricks.fig8EightsDefault
        HStack(spacing: 11) {
            Text(L.fig8Loops).font(.system(size: 13)).foregroundStyle(p.text)
                .frame(width: 150, alignment: .leading)
            Spacer()
            stepButton("minus") {
                fig8Eights = Swift.max(Tricks.fig8EightsMin, fig8Eights - 1); TrickSettings.setFig8Eights(fig8Eights)
            }.disabled(fig8Eights <= Tricks.fig8EightsMin)
            Text("\(fig8Eights)").font(.system(size: 15, weight: .semibold))
                .foregroundStyle(p.accent).monospacedDigit().frame(width: 34)
            stepButton("plus") {
                fig8Eights = Swift.min(Tricks.fig8EightsMax, fig8Eights + 1); TrickSettings.setFig8Eights(fig8Eights)
            }.disabled(fig8Eights >= Tricks.fig8EightsMax)
            Button {
                fig8Eights = Tricks.fig8EightsDefault; TrickSettings.resetFig8Eights()
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
```

- [ ] **Step 5: Build to verify it compiles**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate \
  && xcodebuild build -scheme ESP32Car \
     -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/TrickEditorView.swift
git commit -m "feat(ios): figure-8 editor — loop diameter + eights steppers with live preview"
```

---

### Task 6: Stream the figure-8 from the stored params in `DriveView`

**Files:**
- Modify: `ios/ESP32Car/DriveView.swift` (`startTrick`, the donut `else if` block ends ~line 77)

- [ ] **Step 1: Add the figure-8 branch**

In `ios/ESP32Car/DriveView.swift` `startTrick`, after the donut block (the `} else if base.id == Tricks.donut.id { … }` ending at the `trick = Tricks.donutTrick(...)` line ~77) and before the final `} else {`, insert:

```swift
            } else if base.id == Tricks.figure8.id {
                // Two tangent loops sized by diameter; per-lobe duration from the circle solver at real speed.
                let vmax = await donutVmaxMS()
                if Task.isCancelled { return }
                let track = await donutTrackM()
                if Task.isCancelled { return }
                trick = Tricks.figure8Trick(diameterCm: Double(TrickSettings.fig8Dia()),
                                            eights: TrickSettings.fig8Eights(), vmaxMS: vmax, trackM: track)
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate \
  && xcodebuild build -scheme ESP32Car \
     -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Smoke-test in the simulator (mock car running)**

Ensure the mock car is up (`tools/mock_car`), then install + launch the app and screenshot:

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
xcrun simctl boot "iPhone 17" 2>/dev/null; open -a Simulator
xcrun simctl install booted "$(find /tmp/ddata/Build/Products -name ESP32Car.app | head -1)"
xcrun simctl launch booted com.adamjohnson.esp32car
sleep 3 && xcrun simctl io booted screenshot /tmp/fig8_live.png
```
Expected: the app launches to Drive (mock reports calibrated, high fw build). Navigate ✦ → «Трюки» → «Восьмёрка» to confirm the editor shows the "8" animation + «Диаметр петли» / «Восьмёрок» steppers. (Screenshots are portrait-rotated; rotate to inspect.)

- [ ] **Step 4: Commit**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/DriveView.swift
git commit -m "feat(ios): stream the figure-8 at the user-set loop diameter + eights"
```

---

## Notes for the implementer

- **Do NOT use a git worktree.** Work in-place on the current checkout; every commit MUST land on branch `feat/figure8-params`. Run `git branch --show-current` before committing — if it is not `feat/figure8-params`, stop and report.
- The `swiftc` host driver and `-typecheck` commands are run from `ios/ESP32Car/` (the source files live there). The `xcodebuild`/`git`/`simctl` commands are run from the repo root unless noted.
- `swiftc` builds with assertions ON by default (no `-O`), so `assert(...)` in the host driver fires on failure.
- Insert each new branch **before** the existing terminal `else` so the donut/spin branches keep working — the figure-8 check is mutually exclusive by `trick.id`.
