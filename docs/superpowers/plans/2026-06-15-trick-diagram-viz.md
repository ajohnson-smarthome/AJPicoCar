# Trick Diagram Visualization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans or subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** During trick playback, feed the trick's current command into `curT/curY` so the existing `DriveDiagram` + `PowerBar`s visualize the maneuver; zero them when the trick ends or is cancelled.

**Architecture:** One file (`DriveView.swift`). The trick `Task` already runs on the `@MainActor` view (it sets `@State runningTrick`), so writing `@State curT/curY` there is safe. No new types, no host tests (the change only assigns existing state).

**Tech Stack:** Swift 6 / SwiftUI.

---

### Task 1: Drive the diagram from the trick playback

**Files:**
- Modify: `ios/ESP32Car/DriveView.swift`

- [ ] **Step 1: Set `curT/curY` per step + zero on natural end**

Replace the `startTrick` task body:

```swift
        trickTask = Task {
            for step in trick.steps {
                conn.setCommand(ControlModel.frame(t: step.t, y: step.y))
                try? await Task.sleep(nanoseconds: UInt64(step.ms) * 1_000_000)
                if Task.isCancelled { return }
            }
            conn.setCommand(ControlModel.frame(t: 0, y: 0))   // natural end → stop
            runningTrick = nil; trickStartedAt = nil
        }
```

with:

```swift
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
```

- [ ] **Step 2: Zero `curT/curY` on cancel**

In `cancelTrick`, add the diagram reset:

```swift
    private func cancelTrick(stop: Bool) {
        trickTask?.cancel(); trickTask = nil; runningTrick = nil; trickStartedAt = nil
        curT = 0; curY = 0                                    // diagram back to idle (joystick reasserts if taking over)
        if stop { conn.setCommand(ControlModel.frame(t: 0, y: 0)) }
        // stop == false: leave the command — the joystick is about to set it (seamless takeover)
    }
```

- [ ] **Step 3: Build**

Run: `cd ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Verify the diagram moves during a trick (real flow vs mock)**

The trick MOTION needs no hardware to verify the *visualization* — the diagram is driven by `curT/curY` in the app. Seed a running trick to screenshot it statically (the diagram reads `curT/curY`):

Temporarily, in `DriveView`, seed mid-trick state for a gallery screenshot — set `@State private var curT = 0.0` → `= 0.0` stays, instead seed `runningTrick`/`trickStartedAt` is not enough (the diagram reads curT/curY, not runningTrick). So seed `curT`/`curY` directly:
- set `@State private var curT = 0.0` → `@State private var curT = 0.0` and `@State private var curY = 0.0` → temporarily `curY = 1.0` (a spin) OR `curT = 0.6, curY = 0.6` (an arc).

Then gallery "Drive arcade" (index 15) renders the diagram with that command. Build, screenshot dark + light, confirm `DriveDiagram` shows the maneuver (spin indicator / curved trajectory) and the `PowerBar`s are non-zero. Revert the seed.

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
# temporarily: curY seed = 1.0 (spin) in DriveView, index 15
( cd ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -1 )
DD=$(find /tmp/ddata/Build/Products -name ESP32Car.app | head -1)
xcrun simctl install booted "$DD"
xcrun simctl ui booted appearance dark
xcrun simctl terminate booted com.adamjohnson.esp32car 2>/dev/null
xcrun simctl launch booted com.adamjohnson.esp32car --args -gallery
sleep 3; xcrun simctl io booted screenshot /tmp/trick-viz.png
```
Read it; confirm the diagram reflects the seeded command. Then revert the temporary seed (`curT = 0.0`, `curY = 0.0`) and the gallery index to 0.

- [ ] **Step 5: Commit**

```bash
git add ios/ESP32Car/DriveView.swift
git commit -m "feat(ios): drive the Drive diagram + power bars from trick playback"
```
