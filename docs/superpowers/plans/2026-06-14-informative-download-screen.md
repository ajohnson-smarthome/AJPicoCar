# Informative Download Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the firmware-download screen visibly informative — a progress bar that smoothly fills 0→100% over a guaranteed minimum window — instead of a bar stuck at 0 that flashes to the next screen.

**Architecture:** A shared `DownloadBar` view drives a synthetic progress ramp (`TimelineView`) and shows `max(realProgress, synthetic)`, so the bar always moves even when the ~0.93 MB download is instant or the server omits `Content-Length`. The `.downloading` phase is held for a minimum duration (`UpdateClient.downloadMinDisplay`) after a successful download so the fill is seen. Both gate (`AppFlow`/`UpdateCheckView`) and manual (`FirmwareView`) download paths use it.

**Tech Stack:** Swift 6 / SwiftUI (`TimelineView(.animation)`, `ProgressView`, async `Task.sleep`).

**Verification note:** Pure SwiftUI/async; no host tests. Verify with a simulator build; the gallery's "UpdateCheck downloading" / "Firmware downloading" frames show the animated bar (synthetic ramp runs on appear).

---

### Task 1: Add `downloadMinDisplay` + `holdAtLeast` to `UpdateClient`

**Files:**
- Modify: `ios/ESP32Car/UpdateClient.swift`

- [ ] **Step 1: Add the constant and helper**

In `UpdateClient.swift`, immediately after the `@Published var downloadProgress: Double = 0` line (line 8), add:

```swift

    /// Minimum on-screen duration for the download phase — also the synthetic fill
    /// time for DownloadBar, so the bar reaches 100% just as the screen advances.
    static let downloadMinDisplay: Double = 1.2

    /// Sleep for whatever remains of `seconds` since `start` (no-op if already elapsed).
    static func holdAtLeast(_ seconds: Double, since start: Date) async {
        let remaining = seconds - Date().timeIntervalSince(start)
        if remaining > 0 { try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
    }
```

- [ ] **Step 2: Build**

Run: `cd ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/ESP32Car/UpdateClient.swift
git commit -m "feat(ios): UpdateClient.downloadMinDisplay + holdAtLeast helper"
```

---

### Task 2: Create the `DownloadBar` view

**Files:**
- Create: `ios/ESP32Car/DownloadBar.swift`

- [ ] **Step 1: Write the file**

Create `ios/ESP32Car/DownloadBar.swift`:

```swift
import SwiftUI

/// Progress bar for firmware download that always visibly moves: a synthetic ramp fills
/// 0→100% over `UpdateClient.downloadMinDisplay`, and the shown value is max(real, synthetic),
/// so an instant download or a missing Content-Length still animates. The caption is computed
/// from the shown fraction so the percentage matches the bar.
struct DownloadBar: View {
    let progress: Double
    let caption: (Double) -> String
    let palette: Palette
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { ctx in
            let synthetic = min(1.0, ctx.date.timeIntervalSince(start) / UpdateClient.downloadMinDisplay)
            let shown = max(progress, synthetic)
            VStack(alignment: .leading, spacing: 9) {
                Text(caption(shown)).font(.system(size: 14)).foregroundStyle(palette.muted)
                ProgressView(value: shown).tint(palette.accent).frame(width: 160)
            }
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `cd ios && xcodegen generate && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/ESP32Car/DownloadBar.swift ios/ESP32Car.xcodeproj
git commit -m "feat(ios): DownloadBar — synthetic-ramp progress bar that always moves"
```

---

### Task 3: Hold the gate download phase + use `DownloadBar` in `UpdateCheckView`

**Files:**
- Modify: `ios/ESP32Car/AppFlow.swift`
- Modify: `ios/ESP32Car/UpdateCheckView.swift`

- [ ] **Step 1: Add the min-dwell hold in `AppFlow.startupCheck`**

In `AppFlow.swift`, replace:

```swift
            phase = .downloading
            guard await client.download(rel.assetURL) != nil else { phase = .checkFailed; return }
            if let b = latestBuild { UpdateClient.recordCache(build: b, tag: rel.tag) }
```

with:

```swift
            phase = .downloading
            let t0 = Date()
            guard await client.download(rel.assetURL) != nil else { phase = .checkFailed; return }
            await UpdateClient.holdAtLeast(UpdateClient.downloadMinDisplay, since: t0)
            if let b = latestBuild { UpdateClient.recordCache(build: b, tag: rel.tag) }
```

- [ ] **Step 2: Use `DownloadBar` in `UpdateCheckView`**

In `UpdateCheckView.swift`, replace the `.downloading` case:

```swift
                case .downloading:
                    Text(L.fwDownloadTitle).font(.system(size: 22, weight: .semibold)).foregroundStyle(p.text)
                    Text("\(Int(client.downloadProgress * 100))%").font(.system(size: 14)).foregroundStyle(p.muted)
                    ProgressView(value: client.downloadProgress).tint(p.accent).frame(width: 160)
```

with:

```swift
                case .downloading:
                    Text(L.fwDownloadTitle).font(.system(size: 22, weight: .semibold)).foregroundStyle(p.text)
                    DownloadBar(progress: client.downloadProgress,
                                caption: { "\(Int($0 * 100))%" }, palette: p)
```

- [ ] **Step 3: Build**

Run: `cd ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add ios/ESP32Car/AppFlow.swift ios/ESP32Car/UpdateCheckView.swift
git commit -m "feat(ios): gate download holds min display + DownloadBar in UpdateCheckView"
```

---

### Task 4: Hold the manual download + use `DownloadBar` in `FirmwareView`

**Files:**
- Modify: `ios/ESP32Car/FirmwareView.swift`

- [ ] **Step 1: Add the min-dwell hold in `FirmwareView.download()`**

In `FirmwareView.swift`, replace the `download()` method body:

```swift
    private func download() async {
        guard let r = release else { return }
        phase = .downloading
        if let url = await client.download(r.assetURL) { binURL = url; phase = .downloaded }
        else { phase = .failed }
    }
```

with:

```swift
    private func download() async {
        guard let r = release else { return }
        phase = .downloading
        let t0 = Date()
        if let url = await client.download(r.assetURL) {
            binURL = url
            await UpdateClient.holdAtLeast(UpdateClient.downloadMinDisplay, since: t0)
            phase = .downloaded
        } else { phase = .failed }
    }
```

- [ ] **Step 2: Use `DownloadBar` in the `.downloading` state of `stateBlock`**

In `FirmwareView.swift`, replace the `.downloading` case:

```swift
            case .downloading:
                title(L.fwDownloadTitle)
                sub("\(L.fwTransition(current, release?.tag ?? "")) · \(Int(client.downloadProgress * 100))%")
                ProgressView(value: client.downloadProgress).tint(p.accent).frame(width: 160)
```

with:

```swift
            case .downloading:
                title(L.fwDownloadTitle)
                DownloadBar(progress: client.downloadProgress,
                            caption: { "\(L.fwTransition(current, release?.tag ?? "")) · \(Int($0 * 100))%" },
                            palette: p)
```

- [ ] **Step 3: Build**

Run: `cd ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add ios/ESP32Car/FirmwareView.swift
git commit -m "feat(ios): manual download holds min display + DownloadBar in FirmwareView"
```

---

### Task 5: Visual verification (gallery)

**Files:**
- (Temporary, not committed) `ios/ESP32Car/GalleryView.swift`

- [ ] **Step 1: Screenshot the download frames (dark)**

For frame index 3 ("UpdateCheck downloading") and 8 ("Firmware downloading"): set `@State private var index = N` in `GalleryView.swift`, rebuild, relaunch, screenshot ~0.5s apart to confirm the bar is partway (animating), then again ~1.5s later near full. Example for index 3:

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
sed -i '' 's/@State private var index = [0-9]*/@State private var index = 3/' ios/ESP32Car/GalleryView.swift
( cd ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -1 )
DD=$(find /tmp/ddata/Build/Products -name ESP32Car.app | head -1)
xcrun simctl install booted "$DD"
xcrun simctl ui booted appearance dark
xcrun simctl terminate booted com.adamjohnson.esp32car 2>/dev/null
xcrun simctl launch booted com.adamjohnson.esp32car --args -gallery
sleep 1; xcrun simctl io booted screenshot /tmp/dl-early.png
sleep 2; xcrun simctl io booted screenshot /tmp/dl-late.png
```

Read both. Expected: `dl-early.png` shows the bar partially filled with a matching `%` caption; `dl-late.png` shows it near/at 100%. Confirms the bar visibly animates (not stuck at 0).

- [ ] **Step 2: Revert the temporary gallery index**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
sed -i '' 's/@State private var index = [0-9]*/@State private var index = 0/' ios/ESP32Car/GalleryView.swift
git diff --stat   # expect: no tracked changes
```

- [ ] **Step 3: Final build on the clean tree**

Run: `cd ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`. No commit (verification only).
