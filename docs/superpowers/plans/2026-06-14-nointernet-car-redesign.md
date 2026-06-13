# NoInternet Screen Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the standalone amber Wi-Fi glyph on the «Нет интернета» screen with a reference car bearing an amber `wifi.exclamationmark` chip and pulsing amber waves, matching the other split-layout screens.

**Architecture:** A new private `struct NoInternetCarView` in `NoInternetView.swift` clones `FirmwareCarView`'s geometry (body 34×72, 4 corner wheels, windshield, center chip) but draws everything in `palette.warn` (amber). Waves pulse via animated `frame` size (NOT `.scaleEffect`) so the rings stay under the opaque car. `NoInternetView` swaps `WifiGlyph` for `NoInternetCarView`; the right column and all logic are untouched.

**Tech Stack:** Swift 6 / SwiftUI (`ZStack`, `TimelineView(.animation)`, `RoundedRectangle`, `Image(systemName:)`).

---

### Task 1: Replace WifiGlyph with NoInternetCarView

**Files:**
- Modify: `ios/ESP32Car/NoInternetView.swift`

This is a pure SwiftUI visual component (like the other `*CarView`s) — no host tests; verification is a simulator build + gallery screenshot.

- [ ] **Step 1: Swap the left-half view in `NoInternetView.body`**

In `ios/ESP32Car/NoInternetView.swift`, replace the `WifiGlyph` usage:

```swift
                WifiGlyph(color: p.warn)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
```

with:

```swift
                NoInternetCarView(palette: p)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
```

- [ ] **Step 2: Delete the old `WifiGlyph` struct**

Remove the entire `private struct WifiGlyph` block (the doc comment line `/// Concentric Wi-Fi arcs ...` through its closing brace — lines 33–59 in the current file).

- [ ] **Step 3: Add the new `NoInternetCarView` struct**

Append this struct to `ios/ESP32Car/NoInternetView.swift` (replacing what `WifiGlyph` occupied):

```swift
/// Reference car bearing an amber Wi-Fi-warning chip, ringed by pulsing amber waves.
/// Mirrors FirmwareCarView geometry but in `palette.warn`. Rings pulse via animated
/// frame size (NOT .scaleEffect) so they stay flat in the ZStack — under the opaque car.
private struct NoInternetCarView: View {
    let palette: Palette
    private var metal: Color { palette.metal }
    private var warn: Color { palette.warn }
    private let ringD: [CGFloat] = [56, 80, 104]

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let s = 1.0 + 0.08 * (0.5 + 0.5 * sin(t * 2 * .pi / 1.4))
            ZStack {
                waves(scale: s)   // behind
                car               // opaque, on top
            }
        }
        .scaleEffect(1.6)
        .frame(width: 200, height: 240)
    }

    private func waves(scale: Double) -> some View {
        let op: [Double] = [0.42, 0.24, 0.11]
        return ZStack {
            ForEach(0..<3, id: \.self) { i in
                let d = ringD[i] * scale
                Circle().stroke(warn, lineWidth: 1.5)
                    .frame(width: d, height: d)
                    .opacity(op[i])
            }
        }
    }

    private var car: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(palette.bg)
                .overlay(RoundedRectangle(cornerRadius: 10).fill(palette.panel))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(metal, lineWidth: 1))
                .frame(width: 34, height: 72)
            RoundedRectangle(cornerRadius: 3).fill(palette.bg)
                .frame(width: 20, height: 8).offset(y: -25)
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3).fill(metal)
                    .frame(width: 11, height: 15)
                    .offset(x: i % 2 == 0 ? -18.5 : 18.5, y: i < 2 ? -20.5 : 20.5)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(palette.bg)
                RoundedRectangle(cornerRadius: 5).fill(warn.opacity(0.18))
                RoundedRectangle(cornerRadius: 5).stroke(warn, lineWidth: 1)
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(warn)
            }
            .frame(width: 20, height: 20)
            .shadow(color: warn.opacity(0.55), radius: 5)
        }
    }
}
```

- [ ] **Step 4: Build for the simulator**

Run:
```bash
cd ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Visual check in the gallery (both themes)**

Run (mock car already covered; gallery needs no network):
```bash
DD=$(find /tmp/ddata/Build/Products -name ESP32Car.app | head -1)
# if not built into /tmp/ddata, rebuild with -derivedDataPath /tmp/ddata first
xcrun simctl install booted "$DD"
xcrun simctl launch booted com.adamjohnson.esp32car --args -gallery
xcrun simctl ui booted appearance dark
xcrun simctl io booted screenshot /tmp/nointernet-dark.png
xcrun simctl ui booted appearance light
xcrun simctl io booted screenshot /tmp/nointernet-light.png
```
Expected (frame 1, «No Internet»): reference car with an amber `wifi.exclamationmark` chip on the body and pulsing amber rings UNDER the car; car size/centering matches the neighbouring Firmware/Calibration frames; readable in both themes. Read both screenshots to confirm.

- [ ] **Step 6: Commit**

```bash
git add ios/ESP32Car/NoInternetView.swift
git commit -m "feat(ios): NoInternet screen — car with amber wifi.exclamationmark chip + pulsing waves"
```
