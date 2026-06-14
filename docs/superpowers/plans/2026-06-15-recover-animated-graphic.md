# Animated RecoverCarView Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make the «Авто-возврат» screen's car graphic animated (reverse-scrolling chevron-tread wheels + marching breadcrumb trail) like RampCarView/TrimCarView, gated on the toggle.

**Architecture:** Replace `RecoverCarView`'s static `Canvas` with a `TimelineView(.animation)`-driven one. Same car geometry; wheels gain reverse-scrolling chevron treads and the dashed trail dashes march toward the car when `active`, freezing/dimming when off.

**Tech Stack:** Swift 6 / SwiftUI (`TimelineView(.animation)`, `Canvas`, `StrokeStyle.dashPhase`).

---

### Task 1: Animate `RecoverCarView`

**Files:**
- Modify: `ios/ESP32Car/RecoverView.swift`

- [ ] **Step 1: Replace the `RecoverCarView` struct body**

Replace the entire `struct RecoverCarView { ... }` (from `var body` through the end of the struct) with the animated version:

```swift
struct RecoverCarView: View {
    let active: Bool
    let palette: Palette

    private var metal: Color { palette.metal }
    private let carW: CGFloat = 34
    private let carLen: CGFloat = 72
    private let wheelW: CGFloat = 11
    private let wheelH: CGFloat = 15

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                render(&ctx, size, time: tl.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: 120, height: 210)
        .scaleEffect(1.6)
    }

    private func render(_ ctx: inout GraphicsContext, _ size: CGSize, time: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        drawTrail(&ctx, center: center, time: time)
        drawCar(&ctx, center: center)
        let wx = carW / 2 + 1
        let wy = carLen / 2 - 16
        let phase = active ? time * 60 : 0
        for dx in [-wx, wx] {
            for dy in [-wy, wy] {
                drawWheel(&ctx, cx: center.x + dx, cy: center.y + dy, phase: phase)
            }
        }
    }

    private func drawCar(_ ctx: inout GraphicsContext, center: CGPoint) {
        let body = CGRect(x: center.x - carW / 2, y: center.y - carLen / 2, width: carW, height: carLen)
        let bp = Path(roundedRect: body, cornerRadius: 11)
        ctx.fill(bp, with: .color(palette.bg))
        ctx.fill(bp, with: .color(palette.panel))
        ctx.stroke(bp, with: .color(metal), lineWidth: 1)
        let wind = CGRect(x: center.x - 11, y: body.minY + 7, width: 22, height: 9)
        ctx.fill(Path(roundedRect: wind, cornerRadius: 3), with: .color(palette.bg.opacity(0.85)))
    }

    // Chevron-tread wheel; treads scroll in REVERSE (backward) when active, static when off.
    private func drawWheel(_ ctx: inout GraphicsContext, cx: CGFloat, cy: CGFloat, phase: Double) {
        let rect = CGRect(x: cx - wheelW / 2, y: cy - wheelH / 2, width: wheelW, height: wheelH)
        let wp = Path(roundedRect: rect, cornerRadius: 3)
        ctx.fill(wp, with: .color(metal))
        guard active else { return }                       // off → plain dark wheel, no motion
        var c = ctx
        c.clip(to: wp)
        let spacing: CGFloat = 7
        let offset = CGFloat(-phase).truncatingRemainder(dividingBy: spacing)  // negative → reverse
        let ch: CGFloat = 4
        var k = -2
        while CGFloat(k) * spacing < wheelH + spacing {
            let base = rect.maxY - CGFloat(k) * spacing + offset
            var p = Path()
            p.move(to: CGPoint(x: rect.minX + 1, y: base + ch))
            p.addLine(to: CGPoint(x: rect.midX, y: base - ch))
            p.addLine(to: CGPoint(x: rect.maxX - 1, y: base + ch))
            c.stroke(p, with: .color(palette.bg), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            k += 1
        }
    }

    // Dashed trail behind the car; dashes march toward the car (retrace) when active.
    private func drawTrail(_ ctx: inout GraphicsContext, center: CGPoint, time: Double) {
        let startY = center.y + carLen / 2 + 6
        let endY = startY + 58
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: startY))
        path.addLine(to: CGPoint(x: center.x, y: endY))
        // dashPhase increasing along a startY→endY path moves dashes away from the car;
        // negate so they march toward the car (the path being retraced).
        let dashPhase = active ? CGFloat((-time * 24).truncatingRemainder(dividingBy: 13)) : 0
        ctx.stroke(path, with: .color(palette.accent.opacity(active ? 0.55 : 0.12)),
                   style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 7], dashPhase: dashPhase))
        var chev = Path()
        chev.move(to: CGPoint(x: center.x - 5, y: endY - 5))
        chev.addLine(to: CGPoint(x: center.x, y: endY))
        chev.addLine(to: CGPoint(x: center.x + 5, y: endY - 5))
        ctx.stroke(chev, with: .color(palette.accent.opacity(active ? 0.7 : 0.12)),
                   style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
}
```

- [ ] **Step 2: Build for the simulator**

Run: `cd ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Visual check in the gallery (motion + both themes)**

Temporarily set `@State private var index = 26` (the "Recover" frame) in `GalleryView.swift`, build, install, launch `--args -gallery`. Take TWO dark-theme screenshots ~1 s apart and confirm the wheel tread / trail dashes shifted (animation running). Then a light-theme screenshot. Confirm the car stays centred/same size as other screens.

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
sed -i '' 's/@State private var index = [0-9]*/@State private var index = 26/' ios/ESP32Car/GalleryView.swift
( cd ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -1 )
xcrun simctl boot "iPhone 17" 2>/dev/null; sleep 2
DD=$(find /tmp/ddata/Build/Products -name ESP32Car.app | head -1)
xcrun simctl install booted "$DD"
xcrun simctl ui booted appearance dark
xcrun simctl terminate booted com.adamjohnson.esp32car 2>/dev/null
xcrun simctl launch booted com.adamjohnson.esp32car --args -gallery
sleep 2; xcrun simctl io booted screenshot /tmp/recover-anim1.png
sleep 1; xcrun simctl io booted screenshot /tmp/recover-anim2.png
xcrun simctl ui booted appearance light
sleep 1; xcrun simctl io booted screenshot /tmp/recover-anim-light.png
```

Read the three; expect tread/dash phase to differ between anim1 and anim2.

- [ ] **Step 4: Revert the temporary gallery index**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
sed -i '' 's/@State private var index = [0-9]*/@State private var index = 0/' ios/ESP32Car/GalleryView.swift
git diff --stat   # expect only RecoverView.swift changed
```

- [ ] **Step 5: Commit**

```bash
git add ios/ESP32Car/RecoverView.swift
git commit -m "feat(ios): animate RecoverCarView — reverse chevron treads + marching trail"
```
