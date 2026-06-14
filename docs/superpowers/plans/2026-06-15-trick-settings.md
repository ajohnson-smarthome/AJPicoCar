# Trick Settings (per-trick duration) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add a «Трюки» settings screen where each trick's duration is tuned by a logarithmic 0.5×–12× multiplier (5 s base), with a per-row reset; the multiplier persists in `UserDefaults` and scales the streamed timeline + the progress ring. No firmware change.

**Architecture:** `Tricks.swift` gets a uniform 5 s base + pure scaling/log-mapping helpers. `TrickSettings` persists a per-trick multiplier in `UserDefaults`. `DriveView.startTrick` builds a *scaled* `Trick` (so `running.totalMs` — hence the ring — reflects the real duration) and streams it. `TricksSettingsView` is a list of 4 rows (slider + seconds + reset), pushed from `SettingsView`.

**Tech Stack:** Swift 6 / SwiftUI; pure `Tricks` helpers host-checked with `swiftc`.

**Build/verify:**
- Pure check: `cd /tmp && swiftc <repo>/ios/ESP32Car/Tricks.swift main.swift -o tcheck && ./tcheck`
- App build: `cd ios && xcodegen generate && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata`

---

### Task 1: `Tricks.swift` — 5 s base + scaling/log helpers + host check (TDD)

**Files:**
- Modify: `ios/ESP32Car/Tricks.swift`
- Modify: `ios/ESP32CarTests/TricksTests.swift`

- [ ] **Step 1: Extend the host check**

Replace `/tmp/main.swift` with:

```swift
import Foundation
func approx(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }
for tr in Tricks.all {
    assert(!tr.steps.isEmpty, "\(tr.nameKey) empty")
    assert(tr.totalMs == 5000, "\(tr.nameKey) base must be 5000ms, got \(tr.totalMs)")
    for s in tr.steps { assert(s.t >= -1 && s.t <= 1 && s.y >= -1 && s.y <= 1 && s.ms > 0, "\(tr.nameKey) step") }
}
assert(Set(Tricks.all.map { $0.id }).count == Tricks.all.count, "ids not unique")
// clampScale
assert(approx(Tricks.clampScale(0.1), 0.5) && approx(Tricks.clampScale(99), 12) && approx(Tricks.clampScale(2), 2))
// scaled: ms scaled, t/y untouched, min 1ms
let sc = Tricks.scaled([TrickStep(t: 0.6, y: -0.6, ms: 1000)], by: 2)
assert(sc.count == 1 && sc[0].ms == 2000 && approx(sc[0].t, 0.6) && approx(sc[0].y, -0.6))
assert(Tricks.scaled([TrickStep(t: 0, y: 0, ms: 1)], by: 0.5)[0].ms == 1)   // never below 1ms
// scaledTrick keeps identity, scales total
let st = Tricks.scaledTrick(Tricks.spin, by: 3)
assert(st.id == Tricks.spin.id && st.totalMs == 15000)
// log mapping: endpoints + round-trip
assert(approx(Tricks.sliderToScale(0), 0.5) && approx(Tricks.sliderToScale(1), 12))
assert(approx(Tricks.scaleToSlider(0.5), 0) && approx(Tricks.scaleToSlider(12), 1))
assert(approx(Tricks.sliderToScale(Tricks.scaleToSlider(3.7)), 3.7))
print("tricks: all passed")
```

- [ ] **Step 2: Run to confirm it fails (helpers/base not present yet)**

Run: `cd /tmp && swiftc /Users/adamjohnson/VSCode/esp32-p4-car/ios/ESP32Car/Tricks.swift main.swift -o tcheck 2>&1 | tail -3`
Expected: compile errors (`clampScale`/`scaled`/… not found) or base-assert failure.

- [ ] **Step 3: Rewrite `Tricks.swift`**

Replace the whole `enum Tricks { ... }` block and keep the `TrickStep`/`Trick` structs above it. New `enum Tricks`:

```swift
/// Open-loop (no gyro) — angles/distances are approximate and surface/battery dependent.
/// Every trick is 5 s at ×1; a per-trick multiplier (0.5–12, log slider) scales the timeline.
enum Tricks {
    static let baseMs = 5000
    static let scaleMin = 0.5
    static let scaleMax = 12.0

    static let spin = Trick(id: 1, nameKey: "tricks.spin", icon: "arrow.clockwise",
                            steps: [TrickStep(t: 0, y: 1, ms: 5000)])
    static let figure8 = Trick(id: 2, nameKey: "tricks.figure8", icon: "infinity",
                               steps: [TrickStep(t: 0.6, y: 0.6, ms: 2500),
                                       TrickStep(t: 0.6, y: -0.6, ms: 2500)])
    static let wiggle = Trick(id: 3, nameKey: "tricks.wiggle", icon: "wind",
                              steps: (0..<20).map { TrickStep(t: 0, y: $0 % 2 == 0 ? 0.8 : -0.8, ms: 250) })
    static let donut = Trick(id: 4, nameKey: "tricks.donut", icon: "circle.dashed",
                             steps: [TrickStep(t: 0.7, y: 1, ms: 5000)])

    static let all: [Trick] = [spin, figure8, wiggle, donut]

    // MARK: pure helpers (host-tested)
    static func clampScale(_ v: Double) -> Double { min(scaleMax, max(scaleMin, v)) }

    static func scaled(_ steps: [TrickStep], by scale: Double) -> [TrickStep] {
        let s = clampScale(scale)
        return steps.map { TrickStep(t: $0.t, y: $0.y, ms: max(1, Int((Double($0.ms) * s).rounded()))) }
    }

    static func scaledTrick(_ trick: Trick, by scale: Double) -> Trick {
        Trick(id: trick.id, nameKey: trick.nameKey, icon: trick.icon, steps: scaled(trick.steps, by: scale))
    }

    /// Log slider position p∈[0,1] ↔ multiplier in [scaleMin, scaleMax].
    static func sliderToScale(_ p: Double) -> Double { scaleMin * pow(scaleMax / scaleMin, min(1, max(0, p))) }
    static func scaleToSlider(_ s: Double) -> Double { log(clampScale(s) / scaleMin) / log(scaleMax / scaleMin) }
}
```

`Tricks.swift` must `import Foundation` (already does) for `pow`/`log`.

- [ ] **Step 4: Run the host check**

Run: `cd /tmp && swiftc /Users/adamjohnson/VSCode/esp32-p4-car/ios/ESP32Car/Tricks.swift main.swift -o tcheck && ./tcheck`
Expected: `tricks: all passed`.

- [ ] **Step 5: Extend the XCTest mirror**

In `ios/ESP32CarTests/TricksTests.swift`, replace the `testAllBounded` cap line and add scaling tests:

```swift
import XCTest
@testable import ESP32Car

final class TricksTests: XCTestCase {
    private func approx(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    func testBaseFiveSeconds() {
        for tr in Tricks.all {
            XCTAssertFalse(tr.steps.isEmpty)
            XCTAssertEqual(tr.totalMs, 5000)
            for s in tr.steps { XCTAssertTrue(s.t >= -1 && s.t <= 1 && s.y >= -1 && s.y <= 1 && s.ms > 0) }
        }
    }
    func testIdsUnique() { XCTAssertEqual(Set(Tricks.all.map { $0.id }).count, Tricks.all.count) }
    func testClamp() {
        XCTAssertTrue(approx(Tricks.clampScale(0.1), 0.5))
        XCTAssertTrue(approx(Tricks.clampScale(99), 12))
        XCTAssertTrue(approx(Tricks.clampScale(2), 2))
    }
    func testScaled() {
        let sc = Tricks.scaled([TrickStep(t: 0.6, y: -0.6, ms: 1000)], by: 2)
        XCTAssertEqual(sc[0].ms, 2000)
        XCTAssertTrue(approx(sc[0].t, 0.6) && approx(sc[0].y, -0.6))
        XCTAssertEqual(Tricks.scaled([TrickStep(t: 0, y: 0, ms: 1)], by: 0.5)[0].ms, 1)
        XCTAssertEqual(Tricks.scaledTrick(Tricks.spin, by: 3).totalMs, 15000)
    }
    func testLogMapping() {
        XCTAssertTrue(approx(Tricks.sliderToScale(0), 0.5))
        XCTAssertTrue(approx(Tricks.sliderToScale(1), 12))
        XCTAssertTrue(approx(Tricks.sliderToScale(Tricks.scaleToSlider(3.7)), 3.7))
    }
}
```

- [ ] **Step 6: Commit**

```bash
git add ios/ESP32Car/Tricks.swift ios/ESP32CarTests/TricksTests.swift
git commit -m "feat(ios): tricks 5s base + scale/log helpers (host-checked)"
```

---

### Task 2: `TrickSettings` — UserDefaults store

**Files:**
- Create: `ios/ESP32Car/TrickSettings.swift`

- [ ] **Step 1: Write the store**

```swift
import Foundation

/// Per-trick duration multiplier, persisted in UserDefaults (tricks are app-side data).
enum TrickSettings {
    private static func key(_ id: Int) -> String { "trick.scale.\(id)" }

    static func scale(_ id: Int) -> Double {
        let v = UserDefaults.standard.object(forKey: key(id)) as? Double
        return Tricks.clampScale(v ?? 1.0)
    }
    static func setScale(_ id: Int, _ value: Double) {
        UserDefaults.standard.set(Tricks.clampScale(value), forKey: key(id))
    }
    static func reset(_ id: Int) { setScale(id, 1.0) }
}
```

- [ ] **Step 2: Commit** (builds together with later tasks)

```bash
git add ios/ESP32Car/TrickSettings.swift
git commit -m "feat(ios): TrickSettings — per-trick multiplier in UserDefaults"
```

---

### Task 3: Apply the multiplier in `DriveView.startTrick`

**Files:**
- Modify: `ios/ESP32Car/DriveView.swift`

- [ ] **Step 1: Build a scaled trick before streaming**

Replace `startTrick`:

```swift
    private func startTrick(_ base: Trick) {
        trickTask?.cancel()
        let trick = Tricks.scaledTrick(base, by: TrickSettings.scale(base.id))  // scaled steps; totalMs drives the ring
        runningTrick = trick
        trickStartedAt = Date()
        trickTask = Task {
            for step in trick.steps {
                conn.setCommand(ControlModel.frame(t: step.t, y: step.y))
                try? await Task.sleep(nanoseconds: UInt64(step.ms) * 1_000_000)
                if Task.isCancelled { return }
            }
            conn.setCommand(ControlModel.frame(t: 0, y: 0))   // natural end → stop
            runningTrick = nil; trickStartedAt = nil
        }
    }
```

(The popover still lists `Tricks.all` base tricks; `onSelect` passes a base trick, which `startTrick` scales. `runningTrick` is the scaled instance, so `TricksControl`'s ring — which uses `running.totalMs` — reflects the real duration.)

- [ ] **Step 2: Build**

Run: `cd ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/ESP32Car/DriveView.swift
git commit -m "feat(ios): apply per-trick duration multiplier when streaming a trick"
```

---

### Task 4: `TricksSettingsView` — the list screen

**Files:**
- Create: `ios/ESP32Car/TricksSettingsView.swift`

- [ ] **Step 1: Write the screen**

```swift
import SwiftUI

/// Settings sub-screen: per-trick duration multiplier (log slider 0.5×–12×) + per-row reset.
/// List-based (like SettingsView), custom header, system nav bar hidden for consistency.
struct TricksSettingsView: View {
    let palette: Palette
    @Environment(\.dismiss) private var dismiss
    private var p: Palette { palette }

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                List {
                    ForEach(Tricks.all) { trick in
                        TrickRow(trick: trick, palette: p).listRowBackground(p.panel)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(p.accent)
            }.buttonStyle(.plain)
            Text(L.tricksTitle).font(.system(size: 17, weight: .semibold)).foregroundStyle(p.text)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
    }
}

private struct TrickRow: View {
    let trick: Trick
    let palette: Palette
    @State private var scale: Double = 1.0
    private var p: Palette { palette }
    private var isDefault: Bool { abs(scale - 1.0) < 0.01 }
    private var seconds: Double { Double(trick.totalMs) / 1000 * Tricks.clampScale(scale) }

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: trick.icon).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(p.accent).frame(width: 22)
            Text(L.trickName(trick.nameKey)).font(.system(size: 13)).foregroundStyle(p.text)
                .frame(width: 92, alignment: .leading)
            Slider(value: Binding(
                get: { Tricks.scaleToSlider(scale) },
                set: { scale = Tricks.sliderToScale($0) }
            ), in: 0...1) { editing in
                if !editing { TrickSettings.setScale(trick.id, scale) }
            }
            .tint(p.accent)
            VStack(alignment: .trailing, spacing: 1) {
                Text(L.trickSec(seconds)).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(p.accent).monospacedDigit()
                Text(L.trickMult(scale)).font(.system(size: 9)).foregroundStyle(p.muted).monospacedDigit()
            }
            .frame(width: 64, alignment: .trailing)
            Button { scale = 1.0; TrickSettings.setScale(trick.id, 1.0) } label: {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 13))
                    .foregroundStyle(isDefault ? p.muted : p.accent)
                    .frame(width: 28, height: 28)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(isDefault ? p.line : p.accent.opacity(0.4)))
            }
            .buttonStyle(.plain).disabled(isDefault)
        }
        .padding(.vertical, 4)
        .onAppear { scale = TrickSettings.scale(trick.id) }
    }
}
```

- [ ] **Step 2: Build (after Task 5 adds the L strings).** Deferred to Task 5.

- [ ] **Step 3: Commit**

```bash
git add ios/ESP32Car/TricksSettingsView.swift
git commit -m "feat(ios): TricksSettingsView — per-trick duration list"
```

---

### Task 5: Settings link + strings + build

**Files:**
- Modify: `ios/ESP32Car/SettingsView.swift`
- Modify: `ios/ESP32Car/L.swift`
- Modify: `ios/ESP32Car/Resources/ru.lproj/Localizable.strings`

- [ ] **Step 1: Add the Settings link (after «Авто-возврат», before «Прошивка»)**

In `SettingsView.swift`, before the `FirmwareView` `NavigationLink`, insert:

```swift
                    NavigationLink {
                        TricksSettingsView(palette: palette)
                    } label: {
                        Label(L.tricksTitle, systemImage: "sparkles")
                            .foregroundStyle(palette.text)
                    }
                    .listRowBackground(palette.panel)
```

- [ ] **Step 2: Add `L` accessors**

In `L.swift`, after `trickName`, add:

```swift
    static var tricksTitle: String { s("tricks.title") }
    static func trickSec(_ v: Double) -> String { s("tricks.sec", v) }
    static func trickMult(_ v: Double) -> String { s("tricks.mult", v) }
```

- [ ] **Step 3: Add the strings**

In `Resources/ru.lproj/Localizable.strings`, after the `tricks.donut` line, add:

```
"tricks.title" = "Трюки";
"tricks.sec"   = "%.1f с";
"tricks.mult"  = "×%.1f";
```

- [ ] **Step 4: Build**

Run: `cd ios && xcodegen generate && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/ESP32Car/SettingsView.swift ios/ESP32Car/L.swift ios/ESP32Car/Resources/ru.lproj/Localizable.strings
git commit -m "feat(ios): Settings → «Трюки» link + strings"
```

---

### Task 6: Visual check (gallery, both themes)

**Files:**
- (Temporary, not committed) `ios/ESP32Car/GalleryView.swift`

- [ ] **Step 1: Add a temporary gallery frame**

In `GalleryView.swift` `makeFrames`, after the "Settings" entry, temporarily add:

```swift
            ("Tricks settings", AnyView(NavigationStack { TricksSettingsView(palette: p) })),
```

- [ ] **Step 2: Screenshot dark + light**

Set the gallery `index` to that frame's index, build, install, launch `--args -gallery`, screenshot in dark and light. Confirm: 4 rows (Разворот/Восьмёрка/Вилять/Пончик), each with icon + name + slider + «5.0 с / ×1.0» + reset ↺ (dim at ×1); header «‹ Трюки»; readable in both themes.

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
# set index to the Tricks settings frame, then:
( cd ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -1 )
DD=$(find /tmp/ddata/Build/Products -name ESP32Car.app | head -1)
xcrun simctl install booted "$DD"
xcrun simctl ui booted appearance dark
xcrun simctl terminate booted com.adamjohnson.esp32car 2>/dev/null
xcrun simctl launch booted com.adamjohnson.esp32car --args -gallery
sleep 3; xcrun simctl io booted screenshot /tmp/tricks-settings-dark.png
xcrun simctl ui booted appearance light
xcrun simctl terminate booted com.adamjohnson.esp32car 2>/dev/null
xcrun simctl launch booted com.adamjohnson.esp32car --args -gallery
sleep 3; xcrun simctl io booted screenshot /tmp/tricks-settings-light.png
```

Read both screenshots.

- [ ] **Step 3: Revert the temporary gallery changes**

Remove the temporary "Tricks settings" frame and set `index` back to 0.
Run: `git diff --stat` — expect no tracked changes beyond Tasks 1–5.

- [ ] **Step 4: Final checks**

Run the pure check (`tricks: all passed`) and the app build (`** BUILD SUCCEEDED **`). No commit.

Note: applying a multiplier to actual trick MOTION can only be verified on hardware (motors) — out of scope for the simulator.
