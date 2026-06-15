# Trick Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans or subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Replace the single per-trick duration multiplier with a per-trick **editor**: tapping a trick in «Трюки» opens a screen listing its distinct actions (grouped by `(t,y)`), each with a 0.1–10 s duration slider + reset. Durations persist in `UserDefaults` and rebuild the streamed timeline. No firmware change.

**Architecture:** `Tricks.swift` gains pure helpers (`distinctActions`, `baseDurations`, `withDurations`, `clampDur`, `actionDescriptor`) and drops the scale/log helpers. `TrickSettings` stores a per-trick `[Int]` of per-action durations. `TricksSettingsView` becomes a navigation list → new `TrickEditorView`. `DriveView.startTrick` rebuilds the trick via `withDurations`.

**Tech Stack:** Swift 6 / SwiftUI; pure `Tricks` helpers host-checked with `swiftc`.

**Build/verify:**
- Pure check: `cd /tmp && swiftc <repo>/ios/ESP32Car/Tricks.swift main.swift -o tcheck && ./tcheck`
- App build: `cd ios && xcodegen generate && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata`

---

### Task 1: `Tricks.swift` — swap scale helpers for editor helpers + host check (TDD)

**Files:**
- Modify: `ios/ESP32Car/Tricks.swift`
- Modify: `ios/ESP32CarTests/TricksTests.swift`

- [ ] **Step 1: Replace the host check `/tmp/main.swift`**

```swift
import Foundation
func eq(_ a: [Int], _ b: [Int]) -> Bool { a == b }
for tr in Tricks.all {
    assert(tr.totalMs == 5000, "\(tr.nameKey) base 5000")
}
// distinct actions / counts
assert(Tricks.distinctActions(Tricks.spin).count == 1)
assert(Tricks.distinctActions(Tricks.figure8).count == 2)
assert(Tricks.distinctActions(Tricks.wiggle).count == 2)
let wig = Tricks.distinctActions(Tricks.wiggle)
assert(wig[0].count == 10 && wig[1].count == 10, "wiggle 10+10")
// base durations
assert(eq(Tricks.baseDurations(Tricks.spin), [5000]))
assert(eq(Tricks.baseDurations(Tricks.figure8), [2500, 2500]))
assert(eq(Tricks.baseDurations(Tricks.wiggle), [250, 250]))
// withDurations: order/count preserved, applied per action, clamped
let t = Tricks.withDurations(Tricks.wiggle, [400, 100])
assert(t.steps.count == 20)
assert(t.steps[0].ms == 400 && t.steps[1].ms == 100 && t.steps[2].ms == 400, "applied per action")
assert(t.totalMs == 10 * 400 + 10 * 100)
assert(Tricks.withDurations(Tricks.spin, [99]).steps[0].ms == 100, "clampDur min")
assert(Tricks.withDurations(Tricks.spin, [1, 2]).totalMs == 5000, "wrong length → base")
// descriptor
assert(Tricks.actionDescriptor(0, 1) == (0, 1))
assert(Tricks.actionDescriptor(0.6, -0.6) == (1, -1))
assert(Tricks.actionDescriptor(-0.5, 0) == (-1, 0))
print("tricks: all passed")
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `cd /tmp && swiftc /Users/adamjohnson/VSCode/esp32-p4-car/ios/ESP32Car/Tricks.swift main.swift -o tcheck 2>&1 | tail -3`
Expected: compile errors (`distinctActions`/`withDurations`/… not found).

- [ ] **Step 3: Edit `Tricks.swift` — replace the helper block**

Keep `TrickStep`/`Trick` structs and the four trick definitions + `static let all`. Replace everything from `static let baseMs` / the `// MARK: pure helpers` block (the scale helpers) with:

```swift
    // MARK: per-action durations (host-tested)
    static let durMin = 100      // ms
    static let durMax = 10000

    static func clampDur(_ ms: Int) -> Int { min(durMax, max(durMin, ms)) }

    private static func same(_ a: (t: Double, y: Double), _ t: Double, _ y: Double) -> Bool {
        abs(a.t - t) < 1e-9 && abs(a.y - y) < 1e-9
    }

    /// Distinct movements of a trick, in first-appearance order, with how many steps each spans.
    static func distinctActions(_ trick: Trick) -> [(t: Double, y: Double, count: Int)] {
        var order: [(t: Double, y: Double)] = []
        var counts: [Int] = []
        for s in trick.steps {
            if let i = order.firstIndex(where: { same($0, s.t, s.y) }) { counts[i] += 1 }
            else { order.append((s.t, s.y)); counts.append(1) }
        }
        return zip(order, counts).map { ($0.t, $0.y, $1) }
    }

    /// Base duration (ms) of each distinct action.
    static func baseDurations(_ trick: Trick) -> [Int] {
        distinctActions(trick).map { a in
            trick.steps.first(where: { same((a.t, a.y), $0.t, $0.y) })?.ms ?? durMin
        }
    }

    /// Rebuild the timeline: same order/count as the base, each step's ms = the (clamped)
    /// duration of its action. Wrong-length `durs` → the base trick unchanged.
    static func withDurations(_ trick: Trick, _ durs: [Int]) -> Trick {
        let acts = distinctActions(trick)
        guard durs.count == acts.count else { return trick }
        let steps = trick.steps.map { s -> TrickStep in
            let i = acts.firstIndex(where: { same(($0.t, $0.y), s.t, s.y) }) ?? 0
            return TrickStep(t: s.t, y: s.y, ms: clampDur(durs[i]))
        }
        return Trick(id: trick.id, nameKey: trick.nameKey, icon: trick.icon, steps: steps)
    }

    /// Movement signs for labeling: fwd ∈ {-1,0,1} (back/none/forward), turn ∈ {-1,0,1} (left/none/right).
    static func actionDescriptor(_ t: Double, _ y: Double) -> (fwd: Int, turn: Int) {
        let e = 0.05
        return (t > e ? 1 : (t < -e ? -1 : 0), y > e ? 1 : (y < -e ? -1 : 0))
    }
```

(`same` with a `(t,y)` tuple is used both ways — note both call sites pass the tuple as the first arg.)

- [ ] **Step 4: Run the host check**

Run: `cd /tmp && swiftc /Users/adamjohnson/VSCode/esp32-p4-car/ios/ESP32Car/Tricks.swift main.swift -o tcheck && ./tcheck`
Expected: `tricks: all passed`.

- [ ] **Step 5: Rewrite `TricksTests.swift`**

```swift
import XCTest
@testable import ESP32Car

final class TricksTests: XCTestCase {
    func testBaseFiveSeconds() {
        for tr in Tricks.all {
            XCTAssertFalse(tr.steps.isEmpty)
            XCTAssertEqual(tr.totalMs, 5000)
            for s in tr.steps { XCTAssertTrue(s.t >= -1 && s.t <= 1 && s.y >= -1 && s.y <= 1 && s.ms > 0) }
        }
    }
    func testIdsUnique() { XCTAssertEqual(Set(Tricks.all.map { $0.id }).count, Tricks.all.count) }
    func testDistinctActions() {
        XCTAssertEqual(Tricks.distinctActions(Tricks.spin).count, 1)
        XCTAssertEqual(Tricks.distinctActions(Tricks.figure8).count, 2)
        let w = Tricks.distinctActions(Tricks.wiggle)
        XCTAssertEqual(w.count, 2)
        XCTAssertEqual(w[0].count, 10); XCTAssertEqual(w[1].count, 10)
    }
    func testBaseDurations() {
        XCTAssertEqual(Tricks.baseDurations(Tricks.figure8), [2500, 2500])
        XCTAssertEqual(Tricks.baseDurations(Tricks.wiggle), [250, 250])
    }
    func testWithDurations() {
        let t = Tricks.withDurations(Tricks.wiggle, [400, 100])
        XCTAssertEqual(t.steps.count, 20)
        XCTAssertEqual(t.steps[0].ms, 400); XCTAssertEqual(t.steps[1].ms, 100)
        XCTAssertEqual(t.totalMs, 10 * 400 + 10 * 100)
        XCTAssertEqual(Tricks.withDurations(Tricks.spin, [99]).steps[0].ms, 100)   // clamp
        XCTAssertEqual(Tricks.withDurations(Tricks.spin, [1, 2]).totalMs, 5000)     // wrong length → base
    }
    func testDescriptor() {
        XCTAssertTrue(Tricks.actionDescriptor(0, 1) == (0, 1))
        XCTAssertTrue(Tricks.actionDescriptor(0.6, -0.6) == (1, -1))
    }
}
```

- [ ] **Step 6: Commit**

```bash
git add ios/ESP32Car/Tricks.swift ios/ESP32CarTests/TricksTests.swift
git commit -m "feat(ios): tricks per-action duration helpers (replace scale/log); host-checked"
```

---

### Task 2: `TrickSettings.swift` — per-action durations in UserDefaults

**Files:**
- Modify: `ios/ESP32Car/TrickSettings.swift`

- [ ] **Step 1: Replace the file**

```swift
import Foundation

/// Per-trick action durations (ms, one per distinct action), persisted in UserDefaults.
enum TrickSettings {
    private static func key(_ id: Int) -> String { "trick.durs.\(id)" }

    static func durations(for trick: Trick) -> [Int] {
        let base = Tricks.baseDurations(trick)
        if let saved = UserDefaults.standard.array(forKey: key(trick.id)) as? [Int], saved.count == base.count {
            return saved.map { Tricks.clampDur($0) }
        }
        return base
    }
    static func setDuration(_ trick: Trick, action i: Int, ms: Int) {
        var d = durations(for: trick)
        guard d.indices.contains(i) else { return }
        d[i] = Tricks.clampDur(ms)
        UserDefaults.standard.set(d, forKey: key(trick.id))
    }
    static func reset(_ trick: Trick, action i: Int) {
        var d = durations(for: trick)
        let base = Tricks.baseDurations(trick)
        guard d.indices.contains(i) else { return }
        d[i] = base[i]
        if d == base { UserDefaults.standard.removeObject(forKey: key(trick.id)) }
        else { UserDefaults.standard.set(d, forKey: key(trick.id)) }
    }
}
```

- [ ] **Step 2: Commit** (builds with later tasks)

```bash
git add ios/ESP32Car/TrickSettings.swift
git commit -m "feat(ios): TrickSettings stores per-action durations"
```

---

### Task 3: `TrickEditorView.swift` — the per-trick editor

**Files:**
- Create: `ios/ESP32Car/TrickEditorView.swift`

- [ ] **Step 1: Write the screen**

```swift
import SwiftUI

/// Edits one trick's per-action durations (slider 0.1–10 s each, per distinct movement).
struct TrickEditorView: View {
    let trick: Trick
    let palette: Palette
    @Environment(\.dismiss) private var dismiss
    @State private var durs: [Int] = []
    private var p: Palette { palette }
    private var actions: [(t: Double, y: Double, count: Int)] { Tricks.distinctActions(trick) }
    private var totalSec: Double {
        Double(zip(actions, durs).reduce(0) { $0 + $1.1 * $1.0.count }) / 1000
    }

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                List {
                    ForEach(actions.indices, id: \.self) { i in
                        row(i).listRowBackground(p.panel)
                    }
                    Text(L.trickTotal(totalSec))
                        .font(.system(size: 12)).foregroundStyle(p.muted).monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { if durs.isEmpty { durs = TrickSettings.durations(for: trick) } }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(p.accent)
            }.buttonStyle(.plain)
            Text(L.trickName(trick.nameKey)).font(.system(size: 17, weight: .semibold)).foregroundStyle(p.text)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
    }

    @ViewBuilder private func row(_ i: Int) -> some View {
        let a = actions[i]
        let base = Tricks.baseDurations(trick)
        let isDefault = durs.indices.contains(i) && durs[i] == base[i]
        let secs = durs.indices.contains(i) ? Double(durs[i]) / 1000 : 0
        HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 1) {
                Text(actionLabel(Tricks.actionDescriptor(a.t, a.y))).font(.system(size: 13)).foregroundStyle(p.text)
                if a.count > 1 { Text(L.trickCycles(a.count)).font(.system(size: 9)).foregroundStyle(p.muted) }
            }
            .frame(width: 150, alignment: .leading)
            Slider(value: Binding(
                get: { secs },
                set: { if durs.indices.contains(i) { durs[i] = Int($0 * 1000) } }
            ), in: 0.1...10) { editing in
                if !editing, durs.indices.contains(i) { TrickSettings.setDuration(trick, action: i, ms: durs[i]) }
            }
            .tint(p.accent)
            Text(L.trickSec(secs)).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(p.accent).monospacedDigit().frame(width: 54, alignment: .trailing)
            Button {
                durs[i] = base[i]; TrickSettings.reset(trick, action: i)
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

    private func actionLabel(_ d: (fwd: Int, turn: Int)) -> String {
        let dir = d.fwd > 0 ? L.actFwd : (d.fwd < 0 ? L.actBack : nil)
        let turn = d.turn > 0 ? L.actRight : (d.turn < 0 ? L.actLeft : nil)
        switch (dir, turn) {
        case let (dr?, tn?): return "\(dr)-\(tn)"
        case let (dr?, nil): return dr
        case let (nil, tn?): return "\(L.actTurn) \(tn)"
        default: return L.actFwd
        }
    }
}
```

- [ ] **Step 2: Commit** (builds with Task 6's strings)

```bash
git add ios/ESP32Car/TrickEditorView.swift
git commit -m "feat(ios): TrickEditorView — per-action duration sliders"
```

---

### Task 4: `TricksSettingsView` — list → navigation into the editor

**Files:**
- Modify: `ios/ESP32Car/TricksSettingsView.swift`

- [ ] **Step 1: Replace the file**

```swift
import SwiftUI

/// Settings sub-screen: list of tricks; tapping one opens its per-action duration editor.
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
                        NavigationLink {
                            TrickEditorView(trick: trick, palette: p)
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: trick.icon).font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(p.accent).frame(width: 22)
                                Text(L.trickName(trick.nameKey)).font(.system(size: 14)).foregroundStyle(p.text)
                                Spacer()
                                Text(L.trickSec(totalSec(trick))).font(.system(size: 13))
                                    .foregroundStyle(p.muted).monospacedDigit()
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(p.panel)
                    }
                }
                .scrollContentBackground(.hidden)
                .tint(p.accent)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func totalSec(_ trick: Trick) -> Double {
        Double(Tricks.withDurations(trick, TrickSettings.durations(for: trick)).totalMs) / 1000
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
```

- [ ] **Step 2: Commit**

```bash
git add ios/ESP32Car/TricksSettingsView.swift
git commit -m "feat(ios): «Трюки» list navigates into the per-trick editor"
```

---

### Task 5: `DriveView` — play with per-action durations

**Files:**
- Modify: `ios/ESP32Car/DriveView.swift`

- [ ] **Step 1: Rebuild the trick from stored durations**

In `startTrick`, replace:

```swift
        let trick = Tricks.scaledTrick(base, by: TrickSettings.scale(base.id))  // scaled steps; totalMs drives the ring
```

with:

```swift
        let trick = Tricks.withDurations(base, TrickSettings.durations(for: base))  // per-action durations; totalMs drives the ring
```

- [ ] **Step 2: Commit**

```bash
git add ios/ESP32Car/DriveView.swift
git commit -m "feat(ios): trick playback uses per-action durations"
```

---

### Task 6: Strings + build

**Files:**
- Modify: `ios/ESP32Car/L.swift`
- Modify: `ios/ESP32Car/Resources/ru.lproj/Localizable.strings`

- [ ] **Step 1: Update `L.swift`**

Replace the `trickMult` accessor with the editor accessors:

```swift
    static func trickTotal(_ v: Double) -> String { s("tricks.total", v) }
    static func trickCycles(_ n: Int) -> String { s("tricks.cycles", n) }
    static var actFwd: String { s("tricks.fwd") }
    static var actBack: String { s("tricks.back") }
    static var actRight: String { s("tricks.right") }
    static var actLeft: String { s("tricks.left") }
    static var actTurn: String { s("tricks.turn") }
```
(Remove `static func trickMult(_ v: Double) -> String { s("tricks.mult") }`. Keep `trickName`, `tricksTitle`, `trickSec`.)

- [ ] **Step 2: Update `Resources/ru.lproj/Localizable.strings`**

Remove the `"tricks.mult"` line; after `"tricks.sec"` add:

```
"tricks.total"   = "Всего: %.1f с";
"tricks.cycles"  = "×%d";
"tricks.fwd"     = "Вперёд";
"tricks.back"    = "Назад";
"tricks.right"   = "вправо";
"tricks.left"    = "влево";
"tricks.turn"    = "Поворот";
```

- [ ] **Step 3: Build**

Run: `cd ios && xcodegen generate && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add ios/ESP32Car/L.swift ios/ESP32Car/Resources/ru.lproj/Localizable.strings
git commit -m "feat(ios): trick-editor strings (action labels, total, cycles)"
```

---

### Task 7: Visual check (gallery, both themes)

**Files:**
- (Temporary, not committed) `ios/ESP32Car/GalleryView.swift`

- [ ] **Step 1: Add temp gallery frames**

In `GalleryView.makeFrames`, after the "Settings" entry, temporarily add:

```swift
            ("Tricks list",   AnyView(NavigationStack { TricksSettingsView(palette: p) })),
            ("Trick editor",  AnyView(NavigationStack { TrickEditorView(trick: Tricks.figure8, palette: p) })),
```

- [ ] **Step 2: Screenshot both frames in dark + light**

For each of the two frame indices: set the gallery `index`, build, install, launch `--args -gallery`, screenshot dark and light. Read them. Expected: the **list** shows 4 trick rows with name + total + chevron; the **editor** («Восьмёрка») shows 2 action rows («Вперёд-вправо» / «Вверёд-влево» — i.e. forward-right / forward-left) each with a slider + seconds + reset, and a «Всего: 5.0 с» footer. Both themes readable.

- [ ] **Step 3: Revert the temp gallery changes**

Remove the two temp frames and set `index` back to 0.
Run: `git diff --stat` — expect no tracked changes beyond Tasks 1–6.

- [ ] **Step 4: Final checks**

Run the pure check (`tricks: all passed`) and the app build (`** BUILD SUCCEEDED **`). No commit.

Note: applying durations to actual trick MOTION can only be verified on hardware (motors) — out of scope for the simulator.
