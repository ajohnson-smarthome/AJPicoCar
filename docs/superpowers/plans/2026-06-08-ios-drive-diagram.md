# DriveDiagram — траектория + шеврон-колёса — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Заменить статичный `WheelsView` на анимированный `DriveDiagram`: вытянутая машинка с бегущими шеврон-колёсами + затухающие рельсы предполагаемой траектории (или индикатор разворота), всё из текущей команды `t,y`.

**Architecture:** Чистая геометрия/решение состояния — в `ControlModel` (хост-тесты). Рендер — один SwiftUI `DriveDiagram` через `TimelineView(.animation)` + `Canvas`: машинка, 4 колеса с бегущими шевронами (направление/скорость борта из `ControlModel.sides`), и оверлей — рельсы (движение) или ↻-стрелки (разворот). Встраивается в центр `DriveView` вместо `WheelsView`.

**Tech Stack:** Swift 6 / SwiftUI (`Canvas`, `TimelineView`), `CoreGraphics` (CGPoint), XCTest + нативный `swiftc`. Ветка `ios-app-phase1`. Симулятор-SDK `iphonesimulator26.2`, рантайм iOS 26.3 (есть). Симулятор-устройство — `iPhone 17`.

---

## File Structure

| Файл | Ответственность |
|---|---|
| `ios/ESP32Car/ControlModel.swift` | + `DiagramState`, `diagramState(t:y:)`, `curvature(t:y:)`, `trajectoryPoints(...)` |
| `ios/ESP32CarTests/ControlModelTests.swift` | + тесты этих чистых функций |
| `ios/ESP32Car/Theme.swift` | + поле `warn` (янтарный) в `Palette` (обе темы) |
| `ios/ESP32Car/DriveDiagram.swift` *(new)* | анимированный Canvas: машинка + шеврон-колёса + рельсы/разворот |
| `ios/ESP32Car/DriveView.swift` | центр: `WheelsView` → `DriveDiagram` |
| `ios/ESP32Car/WheelsView.swift` | **удалить** (заменён) |

---

## Task 1: Чистая геометрия в `ControlModel` (TDD)

**Files:** Modify `ios/ESP32Car/ControlModel.swift`, `ios/ESP32CarTests/ControlModelTests.swift`.

- [ ] **Step 1: Нативный чек `/tmp/diag_check.swift`**
```swift
import Foundation
import CoreGraphics
func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }
func run() {
    // diagramState
    precondition(ControlModel.diagramState(t: 0.8, y: 0.0) == .drive, "drive")
    precondition(ControlModel.diagramState(t: 0.0, y: 0.7) == .spin, "spin")
    precondition(ControlModel.diagramState(t: 0.0, y: 0.0) == .idle, "idle")
    // curvature: 0 when y=0, sign follows y
    precondition(near(ControlModel.curvature(t: 1, y: 0), 0), "curv0")
    precondition(ControlModel.curvature(t: 1, y: 0.5) > 0, "curv+")
    precondition(ControlModel.curvature(t: 1, y: -0.5) < 0, "curv-")
    // trajectoryPoints: straight when y=0 (x stays ~0); curves when y!=0
    let straight = ControlModel.trajectoryPoints(t: 1, y: 0, length: 100, steps: 24)
    precondition(abs(straight.last!.x) < 1e-6, "straight x≈0")
    precondition(straight.last!.y < -10, "straight goes up")
    let curved = ControlModel.trajectoryPoints(t: 1, y: 0.6, length: 100, steps: 24)
    precondition(abs(curved.last!.x) > 5, "curved bends in x")
    print("diagram checks: all passed")
}
```
And `/tmp/main.swift` containing `run()`.

- [ ] **Step 2: Run native check — confirm FAIL (no symbols yet)**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && swiftc ios/ESP32Car/ControlModel.swift /tmp/diag_check.swift /tmp/main.swift -o /tmp/diag_check 2>&1 | tail -3
```
Expected: error `cannot find 'diagramState'`/`type 'ControlModel' has no member`. Paste it.

- [ ] **Step 3: Add to `ios/ESP32Car/ControlModel.swift`**
At file top add `import CoreGraphics` (after `import Foundation`). Then add inside (or alongside) — add the enum at file scope and the funcs inside `enum ControlModel`:
```swift
enum DiagramState { case idle, drive, spin }
```
Inside `enum ControlModel`, after `sides`:
```swift
    /// Which visual the diagram shows for a command.
    static func diagramState(t: Double, y: Double) -> DiagramState {
        if abs(t) >= 0.05 { return .drive }
        if abs(y) >= 0.05 { return .spin }
        return .idle
    }

    /// Signed path curvature ~ yaw / speed (bounded near t=0).
    static func curvature(t: Double, y: Double) -> Double {
        y / Swift.max(abs(t), 0.15)
    }

    /// Centerline points of the predicted path in local space: starts at (0,0),
    /// heads "up" (screen -y), bends by yaw. Caller offsets/positions for the two rails.
    static func trajectoryPoints(t: Double, y: Double, length: Double, steps: Int) -> [CGPoint] {
        let curv = curvature(t: t, y: y)
        let seg = length / Double(steps)
        var pts: [CGPoint] = []
        var x = 0.0, yy = 0.0
        var heading = -Double.pi / 2          // up
        for _ in 0...steps {
            pts.append(CGPoint(x: x, y: yy))
            heading += curv * seg * 0.045      // turn-per-length (tuned)
            x += Foundation.cos(heading) * seg
            yy += Foundation.sin(heading) * seg
        }
        return pts
    }
```

- [ ] **Step 4: Run native check — PASS**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && swiftc ios/ESP32Car/ControlModel.swift /tmp/diag_check.swift /tmp/main.swift -o /tmp/diag_check && /tmp/diag_check
```
Expected: `diagram checks: all passed`.

- [ ] **Step 5: Mirror into XCTest** — append to `ios/ESP32CarTests/ControlModelTests.swift` before the final `}`:
```swift
    func testDiagramState() {
        XCTAssertEqual(ControlModel.diagramState(t: 0.8, y: 0), .drive)
        XCTAssertEqual(ControlModel.diagramState(t: 0, y: 0.7), .spin)
        XCTAssertEqual(ControlModel.diagramState(t: 0, y: 0), .idle)
    }
    func testCurvature() {
        XCTAssertEqual(ControlModel.curvature(t: 1, y: 0), 0, accuracy: 1e-9)
        XCTAssertTrue(ControlModel.curvature(t: 1, y: 0.5) > 0)
        XCTAssertTrue(ControlModel.curvature(t: 1, y: -0.5) < 0)
    }
    func testTrajectoryStraightVsCurved() {
        XCTAssertLessThan(abs(ControlModel.trajectoryPoints(t: 1, y: 0, length: 100, steps: 24).last!.x), 1e-6)
        XCTAssertGreaterThan(abs(ControlModel.trajectoryPoints(t: 1, y: 0.6, length: 100, steps: 24).last!.x), 5)
    }
```

- [ ] **Step 6: App still compiles** (the new symbols are used next task)
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -4
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/ControlModel.swift ios/ESP32CarTests/ControlModelTests.swift
git commit -m "feat(ios): ControlModel diagram helpers (state/curvature/trajectory) + tests"
```

---

## Task 2: `Palette.warn` + `DriveDiagram` (Canvas-компонент)

**Files:** Modify `ios/ESP32Car/Theme.swift`; Create `ios/ESP32Car/DriveDiagram.swift`.

- [ ] **Step 1: Добавить `warn` в `Palette`** (`ios/ESP32Car/Theme.swift`)
Replace the `struct Palette { ... }` line with:
```swift
struct Palette {
    let bg: Color, panel: Color, line: Color, text: Color, muted: Color, accent: Color, idleWheel: Color, warn: Color
}
```
In `Theme.dark` add (inside the initializer, after `idleWheel:`):
```swift
        idleWheel: Color(red: 0.227, green: 0.353, blue: 0.267),
        warn:      Color(red: 0.878, green: 0.643, blue: 0.188))
```
(remove the old trailing `)` on the idleWheel line so the literal ends after `warn`).
In `Theme.light` similarly:
```swift
        idleWheel: Color(red: 0.812, green: 0.890, blue: 0.824),
        warn:      Color(red: 0.722, green: 0.475, blue: 0.122))
```

- [ ] **Step 2: Создать `ios/ESP32Car/DriveDiagram.swift`**
```swift
import SwiftUI

/// Animated top-down car diagram driven by the current command (t, y):
/// chevron-tread wheels + predicted-trajectory rails (driving) or a spin indicator.
struct DriveDiagram: View {
    let t: Double
    let y: Double
    let palette: Palette

    // geometry (points)
    private let carW: CGFloat = 44
    private let carLen: CGFloat = 70
    private let wheelW: CGFloat = 10
    private let wheelH: CGFloat = 24
    private let railGap: CGFloat = 12

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                render(&ctx, size, time: tl.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: 150, height: 200)
    }

    private func render(_ ctx: inout GraphicsContext, _ size: CGSize, time: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.56)
        let sides = ControlModel.sides(t: t, y: y)
        switch ControlModel.diagramState(t: t, y: y) {
        case .drive: drawRails(&ctx, center: center)
        case .spin:  drawSpin(&ctx, center: center, time: time)
        case .idle:  break
        }
        drawCar(&ctx, center: center)
        let halfL = carLen / 2
        let frontY = center.y - halfL + 6 + wheelH / 2
        let rearY  = center.y + halfL - 6 - wheelH / 2
        let leftX  = center.x - carW / 2 - wheelW / 2 + 1
        let rightX = center.x + carW / 2 + wheelW / 2 - 1
        drawWheel(&ctx, cx: leftX,  cy: frontY, speed: sides.left,  time: time)
        drawWheel(&ctx, cx: leftX,  cy: rearY,  speed: sides.left,  time: time)
        drawWheel(&ctx, cx: rightX, cy: frontY, speed: sides.right, time: time)
        drawWheel(&ctx, cx: rightX, cy: rearY,  speed: sides.right, time: time)
    }

    private func wheelColor(_ s: Double) -> Color {
        if s > 0.03 { return palette.accent }
        if s < -0.03 { return palette.warn }
        return palette.idleWheel
    }

    private func drawCar(_ ctx: inout GraphicsContext, center: CGPoint) {
        let body = CGRect(x: center.x - carW / 2, y: center.y - carLen / 2, width: carW, height: carLen)
        let bp = Path(roundedRect: body, cornerRadius: 11)
        ctx.fill(bp, with: .color(palette.panel))
        ctx.stroke(bp, with: .color(palette.line), lineWidth: 1)
        let wind = CGRect(x: center.x - 14, y: body.minY + 6, width: 28, height: 11)
        ctx.fill(Path(roundedRect: wind, cornerRadius: 3), with: .color(palette.bg.opacity(0.7)))
    }

    private func drawWheel(_ ctx: inout GraphicsContext, cx: CGFloat, cy: CGFloat, speed: Double, time: Double) {
        let rect = CGRect(x: cx - wheelW / 2, y: cy - wheelH / 2, width: wheelW, height: wheelH)
        let wp = Path(roundedRect: rect, cornerRadius: 3)
        ctx.fill(wp, with: .color(wheelColor(speed)))
        let mag = min(abs(speed), 1)
        guard mag > 0.03 else { return }

        var c = ctx
        c.clip(to: wp)
        let up = speed > 0
        let spacing = 14 - 7 * CGFloat(mag)              // denser at higher speed
        let tempo = 70 * mag                             // px/sec
        let offset = (CGFloat(time) * tempo).truncatingRemainder(dividingBy: spacing)
        let ch: CGFloat = 4.5
        var k = -2
        while CGFloat(k) * spacing < wheelH + spacing {
            // base marches up (forward) or down (reverse)
            let base = up ? (rect.maxY - CGFloat(k) * spacing + offset)
                          : (rect.minY + CGFloat(k) * spacing - offset)
            var p = Path()
            if up {
                p.move(to: CGPoint(x: rect.minX + 1, y: base + ch))
                p.addLine(to: CGPoint(x: rect.midX, y: base - ch))
                p.addLine(to: CGPoint(x: rect.maxX - 1, y: base + ch))
            } else {
                p.move(to: CGPoint(x: rect.minX + 1, y: base - ch))
                p.addLine(to: CGPoint(x: rect.midX, y: base + ch))
                p.addLine(to: CGPoint(x: rect.maxX - 1, y: base - ch))
            }
            c.stroke(p, with: .color(palette.bg), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            k += 1
        }
    }

    private func drawRails(_ ctx: inout GraphicsContext, center: CGPoint) {
        let forward = t >= 0
        let railColor = forward ? palette.accent : palette.warn
        let length = 50 + 80 * min(abs(t), 1)
        let halfW = carW / 2 + 2
        let startY = forward ? (center.y - carLen / 2 - railGap)
                             : (center.y + carLen / 2 + railGap)
        let pts = ControlModel.trajectoryPoints(t: t, y: y, length: length, steps: 24)
        let endY = startY + CGFloat(forward ? -length : length)
        let grad = Gradient(colors: [railColor.opacity(0.95), railColor.opacity(0.05)])
        for side in [CGFloat(-1), CGFloat(1)] {
            var path = Path()
            for (i, pt) in pts.enumerated() {
                let px = center.x + side * halfW + CGFloat(pt.x)
                let py = startY + (forward ? CGFloat(pt.y) : -CGFloat(pt.y))
                if i == 0 { path.move(to: CGPoint(x: px, y: py)) } else { path.addLine(to: CGPoint(x: px, y: py)) }
            }
            ctx.stroke(path, with: .linearGradient(grad,
                startPoint: CGPoint(x: center.x, y: startY),
                endPoint: CGPoint(x: center.x, y: endY)),
                style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
        }
    }

    private func drawSpin(_ ctx: inout GraphicsContext, center: CGPoint, time: Double) {
        var c = ctx
        c.translateBy(x: center.x, y: center.y)
        let dirSign: Double = y >= 0 ? 1 : -1
        let ang = (time.truncatingRemainder(dividingBy: 2.8) / 2.8) * 2 * Double.pi * dirSign
        c.rotate(by: .radians(ang))
        let r: CGFloat = 52
        // two opposing 90° arcs with arrowheads
        for s in [CGFloat(1), CGFloat(-1)] {
            var arc = Path()
            arc.addArc(center: .zero, radius: r, startAngle: .degrees(Double(s) * 0 - 40), endAngle: .degrees(Double(s) * 0 + 50), clockwise: false)
            // place each arc on opposite side
            var t2 = c
            t2.rotate(by: .degrees(s > 0 ? 0 : 180))
            t2.stroke(arc, with: .color(palette.accent), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            // arrowhead at the arc end (≈ angle 50°)
            let a = CGFloat.pi / 180 * 50
            let tip = CGPoint(x: Foundation.cos(a) * r, y: Foundation.sin(a) * r)
            var head = Path()
            head.move(to: CGPoint(x: tip.x - 5, y: tip.y - 1))
            head.addLine(to: CGPoint(x: tip.x + 4, y: tip.y + 3))
            head.addLine(to: CGPoint(x: tip.x - 2, y: tip.y + 7))
            head.closeSubpath()
            t2.fill(head, with: .color(palette.accent))
        }
    }
}
```

- [ ] **Step 3: Regenerate + compile-check**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -10
```
Expected: `** BUILD SUCCEEDED **`. Fix any Swift errors (e.g. `GraphicsContext` copy semantics — `var c = ctx; c.clip(...)` is correct; `inout` render param is fine) and rebuild. Report fixes.

- [ ] **Step 4: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/Theme.swift ios/ESP32Car/DriveDiagram.swift
git commit -m "feat(ios): DriveDiagram — chevron-tread wheels + trajectory rails + spin indicator"
```

---

## Task 3: Встроить в `DriveView`, удалить `WheelsView`

**Files:** Modify `ios/ESP32Car/DriveView.swift`; Delete `ios/ESP32Car/WheelsView.swift`.

- [ ] **Step 1: Заменить центр в `DriveView.swift`**
Find the center HStack (the one with `WheelsView(left:right:palette:)`):
```swift
            HStack(spacing: 34) {
                sideLabel("L", sides.left)
                WheelsView(left: sides.left, right: sides.right, palette: p)
                sideLabel("R", sides.right)
            }
```
Replace the middle line so it becomes:
```swift
            HStack(spacing: 34) {
                sideLabel("L", sides.left)
                DriveDiagram(t: curT, y: curY, palette: p)
                sideLabel("R", sides.right)
            }
```

- [ ] **Step 2: Удалить `WheelsView.swift`**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && git rm ios/ESP32Car/WheelsView.swift
```

- [ ] **Step 3: Regenerate + compile-check**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -6
```
Expected: `** BUILD SUCCEEDED **` (no remaining references to `WheelsView`).

- [ ] **Step 4: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/DriveView.swift
git commit -m "feat(ios): use DriveDiagram in DriveView center (replaces WheelsView)"
```

---

## Task 4: Проверка в симуляторе (+ позже на устройстве)

**Files:** (проверка — без изменений кода)

- [ ] **Step 1: Поднять мок (если не запущен) и запустить апп**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/tools/mock_car
pgrep -f mock_car.py >/dev/null || { nohup .venv/bin/python -u mock_car.py > /tmp/mock_car.log 2>&1 & disown; }
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios
xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | grep -iE "BUILD SUCCEEDED|FAILED" | head -1
xcrun simctl boot "iPhone 17" 2>/dev/null; open -a Simulator
xcrun simctl install booted "$(find /tmp/ddata/Build/Products -name ESP32Car.app | head -1)"
xcrun simctl launch booted com.adamjohnson.esp32car
```

- [ ] **Step 2: Визуальная проверка**
Двигать стик мышью в симуляторе (повернуть в ландшафт):
- forward → зелёные рельсы вверх затухают, шевроны на колёсах бегут вверх, темп растёт со скоростью;
- поворот → рельсы изгибаются по стороне;
- reverse (стик вниз) → рельсы вниз + янтарные, шевроны вниз;
- спин (Tank: стики врозь / Arcade: x без y... фактически t≈0,y≠0) → ↻-стрелки вокруг центра + борта в противоход (один зелёный, другой янтарный);
- переключить тему симулятора → цвета из палитры обе темы.
Снять скриншот (`xcrun simctl io booted screenshot /tmp/d.png`) для глаз.

- [ ] **Step 3: На устройстве (с пользователем)**
Позже: Run на iPhone, проверить ту же анимацию вживую (моторы на подставке).

---

## Self-Review заметки

- **Покрытие спеки:** машинка вытянутая + 4 колеса (Task 2 `drawCar`/`drawWheel`); CD-A бегущие шевроны, темп/плотность по скорости, цвет зелёный/янтарный (`drawWheel`); затухающие рельсы с зазором, изгиб по yaw, длина по throttle, зелёный/янтарный (`drawRails`); разворот B+C — ↻-стрелки (`drawSpin`) + борта в противоход (через `sides`); пороги состояния (`diagramState`). Размещение в `DriveView` (Task 3). Темы (`palette.warn`).
- **Тип-консистентность:** `DiagramState{idle,drive,spin}`; `diagramState/curvature/trajectoryPoints`; `DriveDiagram(t:y:palette:)`; `Palette.warn`; `ControlModel.sides` (есть). `curT/curY` — источник в `DriveView` (есть из апгрейда).
- **Тесты:** чистая геометрия/состояние — нативно + XCTest (Task 1); рендер/анимация — визуально в симуляторе (Task 4).
- **Замечания:** `GraphicsContext` — value type; `var c = ctx; c.clip(...)`/`c.rotate(...)` создаёт локальную копию (правильно). Константы (длина рельсов, темп, `0.045`-изгиб) — подбор на глаз в симуляторе. Имя симулятора `iPhone 17`, bundle `com.adamjohnson.esp32car`. Прошивка не трогается.
