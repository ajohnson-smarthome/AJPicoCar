# SplitScreen Unified Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce a shared `SplitScreen` container that centers car+text content identically on every split screen (by suppressing the system nav bar) and draws an optional custom header, then migrate all seven split screens onto it.

**Architecture:** A generic `SplitScreen<Left, Right>` view owns the common `ZStack { bg; centered HStack { left | right }.padding(20); header }` boilerplate and applies `.toolbar(.hidden, for: .navigationBar)` so no screen carries a nav-bar inset — making vertical centering uniform. Titled screens pass `title`/`onBack`; gate screens pass neither.

**Tech Stack:** Swift 6 / SwiftUI (`@ViewBuilder`, generics, `ZStack(alignment:.topLeading)`, `.toolbar(.hidden:)`, `@Environment(\.dismiss)`).

**Verification note:** These are pure SwiftUI views (no host tests, like the other `*View`s). Each task verifies with a simulator build; Task 9 does the visual gallery sweep in both themes. To screenshot a specific gallery frame, temporarily set `@State private var index = N` in `GalleryView.swift`, build, screenshot, then revert to `0` (do not commit the temporary change).

---

### Task 1: Create the `SplitScreen` container

**Files:**
- Create: `ios/ESP32Car/SplitScreen.swift`

- [ ] **Step 1: Write the file**

Create `ios/ESP32Car/SplitScreen.swift`:

```swift
import SwiftUI

/// Shared split layout: car/graphic on the left, text panel on the right, centred
/// identically on every screen. Suppresses the system nav bar so no screen gets a
/// nav-bar inset (the source of the vertical misalignment); draws an optional custom
/// header (back chevron + title) as a top overlay instead.
struct SplitScreen<Left: View, Right: View>: View {
    let palette: Palette
    var title: String? = nil
    var onBack: (() -> Void)? = nil
    @ViewBuilder var left: () -> Left
    @ViewBuilder var right: () -> Right

    private var p: Palette { palette }

    var body: some View {
        ZStack(alignment: .topLeading) {
            p.bg.ignoresSafeArea()
            HStack(spacing: 24) {
                left().frame(maxWidth: .infinity, maxHeight: .infinity)
                right().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
            if title != nil || onBack != nil { header }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(p.accent)
                }.buttonStyle(.plain)
            }
            if let title {
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(p.text)
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.top, 12)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
cd ios && xcodegen generate && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/ESP32Car/SplitScreen.swift ios/ESP32Car.xcodeproj
git commit -m "feat(ios): SplitScreen — shared split layout, suppresses nav bar, custom header"
```

---

### Task 2: Migrate `NoInternetView`

**Files:**
- Modify: `ios/ESP32Car/NoInternetView.swift`

- [ ] **Step 1: Replace the body**

Replace the entire `var body` of `struct NoInternetView` (the `ZStack { ... }` block) with:

```swift
    var body: some View {
        SplitScreen(palette: p) {
            NoInternetCarView(palette: p)
        } right: {
            VStack(alignment: .leading, spacing: 9) {
                Text(L.gateNoInternetTitle).font(.system(size: 22, weight: .semibold)).foregroundStyle(p.text)
                Text(L.gateNoInternetSub).font(.system(size: 13)).foregroundStyle(p.muted)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 260, alignment: .leading)
                Button(action: onRetry) {
                    Text(L.fwRetry).font(.system(size: 14, weight: .semibold)).foregroundStyle(p.warn)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(p.warn.opacity(0.15)))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(p.warn.opacity(0.55), lineWidth: 1))
                }.buttonStyle(.plain).padding(.top, 3)
            }
        }
    }
```

(The `NoInternetCarView` struct below stays unchanged.)

- [ ] **Step 2: Build**

Run: `cd ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/ESP32Car/NoInternetView.swift
git commit -m "refactor(ios): NoInternetView on SplitScreen"
```

---

### Task 3: Migrate `ConnectView`

**Files:**
- Modify: `ios/ESP32Car/ConnectView.swift`

- [ ] **Step 1: Replace the body**

Replace the entire `var body` of `struct ConnectView` with:

```swift
    var body: some View {
        SplitScreen(palette: p) {
            ConnectCarView(palette: p)
        } right: {
            rightPanel
        }
    }
```

(`rightPanel` and `ConnectCarView` stay unchanged.)

- [ ] **Step 2: Build**

Run: `cd ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/ESP32Car/ConnectView.swift
git commit -m "refactor(ios): ConnectView on SplitScreen"
```

---

### Task 4: Migrate `UpdateCheckView`

**Files:**
- Modify: `ios/ESP32Car/UpdateCheckView.swift`

- [ ] **Step 1: Replace the body**

Replace the entire `var body` of `struct UpdateCheckView` with:

```swift
    var body: some View {
        SplitScreen(palette: p) {
            FirmwareCarView(phase: fwPhase, palette: p)
        } right: {
            VStack(alignment: .leading, spacing: 9) {
                switch phase {
                case .downloading:
                    Text(L.fwDownloadTitle).font(.system(size: 22, weight: .semibold)).foregroundStyle(p.text)
                    Text("\(Int(client.downloadProgress * 100))%").font(.system(size: 14)).foregroundStyle(p.muted)
                    ProgressView(value: client.downloadProgress).tint(p.accent).frame(width: 160)
                case .checkFailed:
                    Text(L.gateCheckFailedTitle).font(.system(size: 22, weight: .semibold)).foregroundStyle(p.text)
                    Text(L.gateCheckFailedSub).font(.system(size: 14)).foregroundStyle(p.muted)
                    Button(action: onRetry) {
                        Text(L.fwRetry).font(.system(size: 14, weight: .semibold)).foregroundStyle(p.accent)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(p.accent.opacity(0.15)))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(p.accent.opacity(0.55), lineWidth: 1))
                    }.buttonStyle(.plain).padding(.top, 3)
                default:
                    Text(L.fwChecking).font(.system(size: 22, weight: .semibold)).foregroundStyle(p.text)
                }
            }
        }
    }
```

- [ ] **Step 2: Build**

Run: `cd ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/ESP32Car/UpdateCheckView.swift
git commit -m "refactor(ios): UpdateCheckView on SplitScreen"
```

---

### Task 5: Migrate `FirmwareView` + drop its NavigationStack wrapper

**Files:**
- Modify: `ios/ESP32Car/FirmwareView.swift`
- Modify: `ios/ESP32Car/ESP32CarApp.swift`

- [ ] **Step 1: Add a dismiss environment to `FirmwareView`**

In `FirmwareView.swift`, after the `@State private var phase` line (line 13), add:

```swift
    @Environment(\.dismiss) private var dismiss
```

- [ ] **Step 2: Replace the `FirmwareView` body**

Replace the entire `var body` (lines 18–37, the `ZStack { ... }.navigationTitle(...).task{...}`) with:

```swift
    var body: some View {
        SplitScreen(palette: p, title: L.settingsFirmware, onBack: forced ? nil : { dismiss() }) {
            FirmwareCarView(phase: phase, palette: p)
        } right: {
            stateBlock
        }
        .task {
            if let dp = debugPhase { phase = dp; return }
            await check()
        }
    }
```

(`stateBlock`, `title`/`sub`/`fwButton`, and the async methods stay unchanged. The removed modifiers — `.navigationTitle`, `.navigationBarTitleDisplayMode`, `.tint(p.accent)` — are intentionally dropped; the inline `ProgressView(...).tint(p.accent)` in `stateBlock` remains.)

- [ ] **Step 3: Drop the NavigationStack wrapper in `ESP32CarApp`**

In `ESP32CarApp.swift`, in `root`, replace the `.updateRequired` case:

```swift
        case .updateRequired:
            NavigationStack {
                FirmwareView(palette: p, forced: true, onDone: { flow.updateFinished() }, status: status)
            }
            .onAppear { conn.start(); status.start() }
```

with:

```swift
        case .updateRequired:
            FirmwareView(palette: p, forced: true, onDone: { flow.updateFinished() }, status: status)
                .onAppear { conn.start(); status.start() }
```

- [ ] **Step 4: Build**

Run: `cd ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/ESP32Car/FirmwareView.swift ios/ESP32Car/ESP32CarApp.swift
git commit -m "refactor(ios): FirmwareView on SplitScreen; drop forced-update NavigationStack"
```

---

### Task 6: Migrate `CalibrationView` + pass `dismissible:false` from the auto-prompt

**Files:**
- Modify: `ios/ESP32Car/CalibrationView.swift`
- Modify: `ios/ESP32Car/DriveView.swift`

- [ ] **Step 1: Add the `dismissible` property**

In `CalibrationView.swift`, after `var debugState: CalDebug? = nil` (line 6), add:

```swift
    var dismissible: Bool = true   // Settings push = back chevron; mandatory auto-prompt = none
```

- [ ] **Step 2: Replace the `CalibrationView` body**

Replace the entire `var body` (the `ZStack { ... }.navigationTitle(L.calibTitle).navigationBarTitleDisplayMode(.inline).tint(p.accent).onAppear { ... }`) with:

```swift
    var body: some View {
        SplitScreen(palette: p, title: L.calibTitle, onBack: dismissible ? { dismiss() } : nil) {
            carDiagram
        } right: {
            rightPanel
        }
        .onAppear {
            guard let d = debugState else { return }
            switch d {
            case .spin:      step = 0; pending = nil; saving = false; failed = false
            case .direction: pending = Corner.allCases.first
            case .done:      step = 4
            case .saving:    saving = true
            case .failed:    failed = true
            }
        }
    }
```

(`carDiagram`, `rightPanel`, and all logic stay unchanged. Dropped: `.navigationTitle`, `.navigationBarTitleDisplayMode`, `.tint(p.accent)`.)

- [ ] **Step 3: Pass `dismissible:false` from the DriveView auto-prompt**

In `DriveView.swift`, in the `.sheet(isPresented: $showCalib)` closure, change:

```swift
                CalibrationView(palette: p)
```

to:

```swift
                CalibrationView(palette: p, dismissible: false)
```

- [ ] **Step 4: Build**

Run: `cd ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/ESP32Car/CalibrationView.swift ios/ESP32Car/DriveView.swift
git commit -m "refactor(ios): CalibrationView on SplitScreen; mandatory auto-prompt hides back"
```

---

### Task 7: Migrate `RampView`

**Files:**
- Modify: `ios/ESP32Car/RampView.swift`

- [ ] **Step 1: Add a dismiss environment**

In `RampView.swift`, after `@State private var demoMs = 300` (line 7), add:

```swift
    @Environment(\.dismiss) private var dismiss
```

- [ ] **Step 2: Replace the `RampView` body**

Replace the entire `var body` (lines 10–27, the `ZStack { ... }.navigationTitle(...).tint(...).task{...}`) with:

```swift
    var body: some View {
        SplitScreen(palette: p, title: L.rampTitle, onBack: { dismiss() }) {
            RampCarView(rampMs: demoMs, palette: p)
        } right: {
            rightPanel
        }
        .task { if let v = await RampClient().get() { rampMs = v; demoMs = v } }
    }
```

(`rightPanel`, `RampCarView` stay unchanged. The inline `Slider(...).tint(p.accent)` in `rightPanel` remains; the view-level `.tint`/`.navigationTitle`/`.navigationBarTitleDisplayMode` are dropped.)

- [ ] **Step 3: Build**

Run: `cd ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add ios/ESP32Car/RampView.swift
git commit -m "refactor(ios): RampView on SplitScreen"
```

---

### Task 8: Migrate `TrimView`

**Files:**
- Modify: `ios/ESP32Car/TrimView.swift`

- [ ] **Step 1: Add a dismiss environment**

In `TrimView.swift`, after `@State private var demoPct = 0` (line 6), add:

```swift
    @Environment(\.dismiss) private var dismiss
```

- [ ] **Step 2: Replace the `TrimView` body**

Replace the entire `var body` (lines 10–26, the `ZStack { ... }.navigationTitle(...).tint(...).task{...}`) with:

```swift
    var body: some View {
        SplitScreen(palette: p, title: L.trimTitle, onBack: { dismiss() }) {
            TrimCarView(trimPct: demoPct, palette: p)
        } right: {
            rightPanel
        }
        .task { if let v = await TrimClient().get() { trimPct = v; demoPct = v } }
    }
```

(`rightPanel`, `TrimCarView` stay unchanged. The inline `Slider(...).tint(p.accent)` remains; view-level `.tint`/`.navigationTitle`/`.navigationBarTitleDisplayMode` are dropped.)

- [ ] **Step 3: Build**

Run: `cd ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add ios/ESP32Car/TrimView.swift
git commit -m "refactor(ios): TrimView on SplitScreen"
```

---

### Task 9: Visual verification sweep (gallery, both themes)

**Files:**
- (Temporary, not committed) `ios/ESP32Car/GalleryView.swift`

- [ ] **Step 1: Install the current build and boot the simulator**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
xcrun simctl boot "iPhone 17" 2>/dev/null; sleep 2
DD=$(find /tmp/ddata/Build/Products -name ESP32Car.app | head -1)
xcrun simctl install booted "$DD"
```

- [ ] **Step 2: Screenshot key frames in dark theme**

For each frame index N in {1 (NoInternet), 5 (Firmware checking), 7 (Firmware available), 19 (Calibration spin), 24 (Ramp), 25 (Trim)}, do: set `@State private var index = N` in `GalleryView.swift`, rebuild, relaunch, screenshot. Practical loop — run once per index, replacing N:

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
sed -i '' 's/@State private var index = [0-9]*/@State private var index = 5/' ios/ESP32Car/GalleryView.swift
( cd ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -1 )
DD=$(find /tmp/ddata/Build/Products -name ESP32Car.app | head -1)
xcrun simctl install booted "$DD"
xcrun simctl ui booted appearance dark
xcrun simctl terminate booted com.adamjohnson.esp32car 2>/dev/null
xcrun simctl launch booted com.adamjohnson.esp32car --args -gallery
sleep 3
xcrun simctl io booted screenshot /tmp/split-firmware-dark.png
```

Read each screenshot. Expected: on every frame the car (left) and the right text block sit at the **same vertical center**; titled frames (Firmware/Calibration/Ramp/Trim) show the custom header (title, top-left); gate frames (NoInternet) have no header. Compare the car's vertical position across frames — it must not shift between titled and untitled screens.

- [ ] **Step 3: Spot-check light theme**

```bash
xcrun simctl ui booted appearance light
xcrun simctl terminate booted com.adamjohnson.esp32car 2>/dev/null
xcrun simctl launch booted com.adamjohnson.esp32car --args -gallery
sleep 3
xcrun simctl io booted screenshot /tmp/split-light.png
```
Read it; confirm header + centering read correctly in light theme.

- [ ] **Step 4: Revert the temporary gallery index**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
sed -i '' 's/@State private var index = [0-9]*/@State private var index = 0/' ios/ESP32Car/GalleryView.swift
git diff --stat   # expect: no tracked changes (GalleryView back at index 0)
```

- [ ] **Step 5: Final build to confirm a clean tree builds**

Run: `cd ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`. No commit needed (verification only; all view changes already committed in Tasks 1–8).
```
