# Wiggle trick: amplitude + wag count — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the «Вилять» (wiggle) trick adjustable by amplitude (|y| per step) + wag count, with a live simulation preview — iOS-only, no firmware change.

**Architecture:** The wiggle is an in-place yaw oscillation with no geometry. A wag = 2 steps (`+amp`, `−amp`) at a fixed 250 ms tempo; `wags` wags → `2·wags` steps. A pure `Tricks.wiggleTrick(amplitude:wags:)` factory builds the timeline; two `UserDefaults`-backed params drive the editor, the streamed maneuver, and the `TrickSim` preview. Unlike the donut/spin/figure-8, building the wiggle needs no `vmax`/`track`, so `DriveView` builds it synchronously.

**Tech Stack:** Swift 6 / SwiftUI, pure `Tricks`/`TrickSim` modules host-tested with `swiftc`, UI compile-checked with `xcodebuild` against the iPhone 17 simulator + the aiohttp mock car.

**Branch:** `feat/wiggle-params` (already created off `main`). All tasks commit here.

---

### Task 1: `Tricks.wiggleTrick` + constants (pure)

**Files:**
- Modify: `ios/ESP32Car/Tricks.swift` (add after the figure-8 section)
- Test: `ios/ESP32CarTests/TrickSimTests.swift` (append XCTest cases) + a temporary `swiftc` driver `/tmp/main.swift`

- [ ] **Step 1: Write the failing host-driver test**

Create `/tmp/main.swift` (the driver file MUST be named `main.swift` — Swift only allows top-level code there):

```swift
import Foundation

func approx(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool { abs(a - b) < eps }

// structure: 2 steps per wag, alternating +amp/-amp, t=0, ms=250, keeps wiggle id
let w = Tricks.wiggleTrick(amplitude: 0.8, wags: 10)
assert(w.steps.count == 20, "step count \(w.steps.count)")
assert(approx(w.steps[0].y, 0.8), "y0 \(w.steps[0].y)")
assert(approx(w.steps[1].y, -0.8), "y1 \(w.steps[1].y)")
assert(w.steps.allSatisfy { $0.t == 0 }, "all t==0")
assert(w.steps.allSatisfy { $0.ms == 250 }, "all ms==250")
assert(w.id == Tricks.wiggle.id, "id")

// default round-trip: 0.8/10 reproduces the original fixed wiggle (Tricks.wiggle constant)
let base = Tricks.wiggle
assert(w.steps.count == base.steps.count, "count matches base")
for (a, b) in zip(w.steps, base.steps) {
    assert(approx(a.y, b.y) && a.ms == b.ms && a.t == b.t, "step mismatch")
}

// clamps: amplitude above 1.0 / below 0.2; wags floored at 1
let hi = Tricks.wiggleTrick(amplitude: 5.0, wags: 3)
assert(approx(hi.steps[0].y, 1.0), "amp clamp hi \(hi.steps[0].y)")
let lo = Tricks.wiggleTrick(amplitude: 0.0, wags: 3)
assert(approx(lo.steps[0].y, 0.2), "amp clamp lo \(lo.steps[0].y)")
let z = Tricks.wiggleTrick(amplitude: 0.8, wags: 0)
assert(z.steps.count == 2, "wags floored to 1 → 2 steps")

print("OK wiggle")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd ios/ESP32Car && swiftc Tricks.swift TrickSim.swift ControlModel.swift /tmp/main.swift -o /tmp/wc && /tmp/wc`
Expected: FAIL — compile error `value of type 'Tricks.Type' has no member 'wiggleTrick'`.

- [ ] **Step 3: Implement the constants + `wiggleTrick`**

In `ios/ESP32Car/Tricks.swift`, after the figure-8 `figure8Trick(...)` function and before `// MARK: per-action durations`, add:

```swift
    // MARK: wiggle (pure, host-tested) — in-place yaw oscillation, NO geometry. amplitude = |y| per
    // step; a wag = 2 steps (+amp, −amp); fixed 250 ms tempo. `wags` wags → 2·wags steps.
    static let wiggleAmpMin = 0.2, wiggleAmpMax = 1.0, wiggleAmpDefault = 0.8
    static let wiggleWagsMin = 1, wiggleWagsMax = 20, wiggleWagsDefault = 10
    static let wiggleStepMs = 250

    /// The wiggle maneuver: `wags` full left-right wags at `amplitude`, fixed 250 ms/step. `2·wags` steps
    /// alternating {t:0, y:+amp} / {t:0, y:-amp}. amplitude clamped to [0.2, 1.0], wags floored at 1.
    /// Keeps the wiggle id/name/icon.
    static func wiggleTrick(amplitude: Double, wags: Int) -> Trick {
        let a = Swift.min(wiggleAmpMax, Swift.max(wiggleAmpMin, amplitude))
        let n = Swift.max(wiggleWagsMin, wags)
        let steps = (0..<(2 * n)).map { TrickStep(t: 0, y: $0 % 2 == 0 ? a : -a, ms: wiggleStepMs) }
        return Trick(id: wiggle.id, nameKey: wiggle.nameKey, icon: wiggle.icon, steps: steps)
    }
```

- [ ] **Step 4: Run the host driver to verify it passes**

Run: `cd ios/ESP32Car && swiftc Tricks.swift TrickSim.swift ControlModel.swift /tmp/main.swift -o /tmp/wc && /tmp/wc`
Expected: PASS — prints `OK wiggle`.

- [ ] **Step 5: Mirror the assertions as permanent XCTest cases**

Append to `ios/ESP32CarTests/TrickSimTests.swift`, just before the closing `}` of `final class TrickSimTests`:

```swift
    func testWiggleStructure() {
        let w = Tricks.wiggleTrick(amplitude: 0.8, wags: 10)
        XCTAssertEqual(w.steps.count, 20)                      // 2 steps × 10 wags
        XCTAssertEqual(w.steps[0].y, 0.8, accuracy: 1e-9)
        XCTAssertEqual(w.steps[1].y, -0.8, accuracy: 1e-9)     // alternating
        XCTAssertTrue(w.steps.allSatisfy { $0.t == 0 })
        XCTAssertTrue(w.steps.allSatisfy { $0.ms == 250 })
        XCTAssertEqual(w.id, Tricks.wiggle.id)
    }

    func testWiggleDefaultMatchesBase() {
        let w = Tricks.wiggleTrick(amplitude: 0.8, wags: 10)
        let base = Tricks.wiggle
        XCTAssertEqual(w.steps.count, base.steps.count)
        for (a, b) in zip(w.steps, base.steps) {
            XCTAssertEqual(a.y, b.y, accuracy: 1e-9)
            XCTAssertEqual(a.ms, b.ms)
            XCTAssertEqual(a.t, b.t, accuracy: 1e-9)
        }
    }

    func testWiggleClamps() {
        XCTAssertEqual(Tricks.wiggleTrick(amplitude: 5.0, wags: 3).steps[0].y, 1.0, accuracy: 1e-9)
        XCTAssertEqual(Tricks.wiggleTrick(amplitude: 0.0, wags: 3).steps[0].y, 0.2, accuracy: 1e-9)
        XCTAssertEqual(Tricks.wiggleTrick(amplitude: 0.8, wags: 0).steps.count, 2)   // wags floored to 1
    }
```

- [ ] **Step 6: Re-run the host driver (regression) and commit**

Run: `cd ios/ESP32Car && swiftc Tricks.swift TrickSim.swift ControlModel.swift /tmp/main.swift -o /tmp/wc && /tmp/wc` (expect `OK wiggle`), then:

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/Tricks.swift ios/ESP32CarTests/TrickSimTests.swift
git commit -m "feat(ios): Tricks.wiggleTrick — amplitude + wag count (host-tested)"
```

---

### Task 2: Persist the two params in `TrickSettings`

**Files:**
- Modify: `ios/ESP32Car/TrickSettings.swift` (add before the final closing `}` of `enum TrickSettings`)

- [ ] **Step 1: Add the wiggle accessors**

In `ios/ESP32Car/TrickSettings.swift`, immediately before the final closing `}` of `enum TrickSettings`, add:

```swift
    private static let wiggleAmpKey = "trick.wiggle.amp"
    private static func clampWiggleAmp(_ a: Double) -> Double {
        Swift.min(Tricks.wiggleAmpMax, Swift.max(Tricks.wiggleAmpMin, a))
    }
    static func wiggleAmp() -> Double {
        clampWiggleAmp(UserDefaults.standard.object(forKey: wiggleAmpKey) as? Double ?? Tricks.wiggleAmpDefault)
    }
    static func setWiggleAmp(_ a: Double) {
        UserDefaults.standard.set(clampWiggleAmp(a), forKey: wiggleAmpKey)
    }
    static func resetWiggleAmp() {
        UserDefaults.standard.removeObject(forKey: wiggleAmpKey)
    }

    private static let wiggleWagsKey = "trick.wiggle.wags"
    private static func clampWiggleWags(_ n: Int) -> Int {
        Swift.min(Tricks.wiggleWagsMax, Swift.max(Tricks.wiggleWagsMin, n))
    }
    static func wiggleWags() -> Int {
        clampWiggleWags(UserDefaults.standard.object(forKey: wiggleWagsKey) as? Int ?? Tricks.wiggleWagsDefault)
    }
    static func setWiggleWags(_ n: Int) {
        UserDefaults.standard.set(clampWiggleWags(n), forKey: wiggleWagsKey)
    }
    static func resetWiggleWags() {
        UserDefaults.standard.removeObject(forKey: wiggleWagsKey)
    }
```

- [ ] **Step 2: Type-check it compiles against `Tricks`**

Run: `cd ios/ESP32Car && swiftc -typecheck TrickSettings.swift Tricks.swift`
Expected: PASS — no output (exit 0).

- [ ] **Step 3: Commit**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/TrickSettings.swift
git commit -m "feat(ios): persist wiggle amplitude + wag count in TrickSettings"
```

---

### Task 3: Localization strings

**Files:**
- Modify: `ios/ESP32Car/L.swift` (after `fig8Loops`)
- Modify: `ios/ESP32Car/Resources/ru.lproj/Localizable.strings` (after the `trick.fig8Loops` line)

- [ ] **Step 1: Add the `L` accessors**

In `ios/ESP32Car/L.swift`, after the line `static var fig8Loops: String { s("trick.fig8Loops") }`, add:

```swift
    static var wiggleAmp: String { s("trick.wiggleAmp") }
    static var wiggleCount: String { s("trick.wiggleCount") }
```

- [ ] **Step 2: Add the Russian strings**

In `ios/ESP32Car/Resources/ru.lproj/Localizable.strings`, after the line `"trick.fig8Loops"     = "Восьмёрок";`, add:

```
"trick.wiggleAmp"     = "Амплитуда";
"trick.wiggleCount"   = "Вильков";
```

- [ ] **Step 3: Type-check `L.swift` compiles**

Run: `cd ios/ESP32Car && swiftc -typecheck L.swift`
Expected: PASS — no output (exit 0).

- [ ] **Step 4: Commit**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/L.swift ios/ESP32Car/Resources/ru.lproj/Localizable.strings
git commit -m "feat(ios): localization for the wiggle amplitude + count labels"
```

---

### Task 4: `TrickSimView` builds the wiggle from the two params

**Files:**
- Modify: `ios/ESP32Car/TrickSimView.swift` (props after `fig8Eights`, `steps` branch)

- [ ] **Step 1: Add the two optional inputs**

In `ios/ESP32Car/TrickSimView.swift`, after the line `var fig8Eights: Int? = nil`, add:

```swift
    var wiggleAmp: Double? = nil
    var wiggleWags: Int? = nil
```

- [ ] **Step 2: Add the wiggle branch in `steps`**

In the computed `private var steps: [TrickStep]`, after the existing figure-8 branch (the `if trick.id == Tricks.figure8.id { … }` block) and BEFORE the `let d = durs.isEmpty …` fallback, add:

```swift
        if trick.id == Tricks.wiggle.id, let amp = wiggleAmp, let n = wiggleWags {
            return Tricks.wiggleTrick(amplitude: amp, wags: n).steps
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
git commit -m "feat(ios): TrickSimView builds the wiggle from amplitude + count"
```

---

### Task 5: `TrickEditorView` wiggle editor branch

**Files:**
- Modify: `ios/ESP32Car/TrickEditorView.swift` (`@State`, `onAppear`, body branch, new rows)

- [ ] **Step 1: Add the `@State` for the two params**

In `ios/ESP32Car/TrickEditorView.swift`, after the line `@State private var fig8Eights = Tricks.fig8EightsDefault`, add:

```swift
    @State private var wiggleAmp = Tricks.wiggleAmpDefault
    @State private var wiggleWags = Tricks.wiggleWagsDefault
```

- [ ] **Step 2: Load them in `onAppear`**

In `.onAppear { … }`, after the line `fig8Eights = TrickSettings.fig8Eights()`, add:

```swift
            wiggleAmp = TrickSettings.wiggleAmp()
            wiggleWags = TrickSettings.wiggleWags()
```

- [ ] **Step 3: Add the wiggle branch to the body**

In `var body`, the trick-type chain currently ends with the figure-8 branch then `} else { controls }`. Insert the wiggle branch before the terminal `else`. Replace exactly:

```swift
                } else {
                    controls
                }
```

with:

```swift
                } else if trick.id == Tricks.wiggle.id {
                    // One shared scroll: animation + stats + amplitude + wag count scroll together.
                    ScrollView {
                        VStack(spacing: 16) {
                            TrickSimView(trick: Tricks.wiggle, durs: durs, palette: p,
                                         wiggleAmp: wiggleAmp, wiggleWags: wiggleWags)
                            VStack(spacing: 0) {
                                wiggleAmpRow.padding(.horizontal, 14)
                                Rectangle().fill(p.metal.opacity(0.25)).frame(height: 1)
                                wiggleWagsRow.padding(.horizontal, 14)
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

- [ ] **Step 4: Add the two rows (amplitude slider + wags stepper)**

In `ios/ESP32Car/TrickEditorView.swift`, after the `fig8EightsRow` computed property (before `private func stepButton`), add. The slider's `Binding` and range are extracted to locals to avoid the Swift type-checker timeout (same approach as `durationRow`):

```swift
    @ViewBuilder private var wiggleAmpRow: some View {
        let isDefault = wiggleAmp == Tricks.wiggleAmpDefault
        let ampBinding = Binding<Double>(
            get: { wiggleAmp },
            set: { wiggleAmp = (($0 * 10).rounded()) / 10 }   // 0.1 steps
        )
        let ampRange = Tricks.wiggleAmpMin...Tricks.wiggleAmpMax
        HStack(spacing: 11) {
            Text(L.wiggleAmp).font(.system(size: 13)).foregroundStyle(p.text)
                .frame(width: 150, alignment: .leading)
            Slider(value: ampBinding, in: ampRange, step: 0.1) { editing in
                if !editing { TrickSettings.setWiggleAmp(wiggleAmp) }
            }
            .tint(p.accent)
            Text(String(format: "%.1f", wiggleAmp)).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(p.accent).monospacedDigit().frame(width: 54, alignment: .trailing)
            Button {
                wiggleAmp = Tricks.wiggleAmpDefault; TrickSettings.resetWiggleAmp()
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

    @ViewBuilder private var wiggleWagsRow: some View {
        let isDefault = wiggleWags == Tricks.wiggleWagsDefault
        HStack(spacing: 11) {
            Text(L.wiggleCount).font(.system(size: 13)).foregroundStyle(p.text)
                .frame(width: 150, alignment: .leading)
            Spacer()
            stepButton("minus") {
                wiggleWags = Swift.max(Tricks.wiggleWagsMin, wiggleWags - 1); TrickSettings.setWiggleWags(wiggleWags)
            }.disabled(wiggleWags <= Tricks.wiggleWagsMin)
            Text("\(wiggleWags)").font(.system(size: 15, weight: .semibold))
                .foregroundStyle(p.accent).monospacedDigit().frame(width: 34)
            stepButton("plus") {
                wiggleWags = Swift.min(Tricks.wiggleWagsMax, wiggleWags + 1); TrickSettings.setWiggleWags(wiggleWags)
            }.disabled(wiggleWags >= Tricks.wiggleWagsMax)
            Button {
                wiggleWags = Tricks.wiggleWagsDefault; TrickSettings.resetWiggleWags()
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
git commit -m "feat(ios): wiggle editor — amplitude slider + wag count stepper with live preview"
```

---

### Task 6: Stream the wiggle from the stored params in `DriveView`

**Files:**
- Modify: `ios/ESP32Car/DriveView.swift` (`startTrick`)

- [ ] **Step 1: Add the wiggle branch**

In `ios/ESP32Car/DriveView.swift` `startTrick`, after the figure-8 block (the `} else if base.id == Tricks.figure8.id { … }` block) and BEFORE the final `} else {` (which handles `Tricks.withDurations`), insert:

```swift
            } else if base.id == Tricks.wiggle.id {
                // In-place oscillation — no geometry, build synchronously from amplitude + wag count.
                trick = Tricks.wiggleTrick(amplitude: TrickSettings.wiggleAmp(), wags: TrickSettings.wiggleWags())
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

Ensure the mock car is up (`curl -s 127.0.0.1:8080/status` returns JSON; if not, start it from `tools/mock_car`). Then:

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
xcrun simctl boot "iPhone 17" 2>/dev/null; open -a Simulator
xcrun simctl install booted "$(find /tmp/ddata/Build/Products -name ESP32Car.app | head -1)"
xcrun simctl terminate booted com.adamjohnson.esp32car 2>/dev/null
xcrun simctl launch booted com.adamjohnson.esp32car
sleep 3 && xcrun simctl io booted screenshot /tmp/wiggle_live.png
```
Expected: the app launches (prints a PID) without crashing. Report whether `/tmp/wiggle_live.png` was written. (simctl can't tap; navigating to ✦ → «Трюки» → «Вилять» is done by hand in the Simulator window.)

- [ ] **Step 4: Commit**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/DriveView.swift
git commit -m "feat(ios): stream the wiggle at the user-set amplitude + wag count"
```

---

## Notes for the implementer

- **Do NOT use a git worktree.** Work in-place; every commit MUST land on branch `feat/wiggle-params`. Run `git branch --show-current` before committing — if it is not `feat/wiggle-params`, stop and report.
- The `swiftc` host driver and `-typecheck` commands run from `ios/ESP32Car/`. The `xcodebuild`/`git`/`simctl` commands run from the repo root unless noted.
- `swiftc` builds with assertions ON by default, so `assert(...)` in the host driver fires on failure.
- The host driver file MUST be named `/tmp/main.swift` (Swift only allows top-level statements in `main.swift`).
- Insert each new branch **before** the existing terminal `else` — the wiggle check is mutually exclusive by `trick.id`.
