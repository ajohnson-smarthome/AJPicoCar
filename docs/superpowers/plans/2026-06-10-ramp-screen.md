# Экран «Разгон» (пункт меню + демо) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Перенести настройку плавного старта в отдельный пункт меню «Разгон» → split-layout экран с демо-анимацией разгона слева и слайдером справа.

**Architecture:** Новый `RampView.swift` (экран + Canvas-`RampCarView` с циклом пауза→разгон→полная скорость, темп = `ramp_ms`); в `SettingsView` инлайн-секция заменяется на `NavigationLink`. `RampClient`/прошивка/мок — без изменений.

**Tech Stack:** Swift 6 / SwiftUI (Canvas + TimelineView). Ветка `ramp` (продолжаем). SDK `iphonesimulator26.2`, `iPhone 17`, мок.

---

## File Structure

| Файл | Изменение |
|---|---|
| `ios/ESP32Car/Resources/ru.lproj/Localizable.strings` | `ramp.label/off` → `ramp.headline/sub/value/valueOff` |
| `ios/ESP32Car/L.swift` | соответствующие аксессоры |
| `ios/ESP32Car/RampView.swift` *(new)* | экран + `RampCarView` (демо) |
| `ios/ESP32Car/SettingsView.swift` | секция-слайдер → NavigationLink «Разгон» |

---

## Task 1: Строки + `L`

**Files:** Modify `ios/ESP32Car/Resources/ru.lproj/Localizable.strings`, `ios/ESP32Car/L.swift`.

- [ ] **Step 1: `Localizable.strings`** — заменить:
```
"ramp.label"         = "Плавный старт: %d мс";
"ramp.off"           = "Плавный старт: выкл";
```
на:
```
"ramp.headline"      = "Плавный старт";
"ramp.sub"           = "Время разгона до полной мощности.";
"ramp.value"         = "%d мс";
"ramp.valueOff"      = "Выкл";
```
(`"ramp.title" = "Разгон";` остаётся.)

- [ ] **Step 2: `L.swift`** — заменить:
```swift
    static var rampOff: String { s("ramp.off") }
```
на:
```swift
    static var rampHeadline: String { s("ramp.headline") }
    static var rampSub: String { s("ramp.sub") }
    static var rampValueOff: String { s("ramp.valueOff") }
```
и заменить:
```swift
    static func rampLabel(_ ms: Int) -> String { s("ramp.label", ms) }
```
на:
```swift
    static func rampValue(_ ms: Int) -> String { s("ramp.value", ms) }
```

- [ ] **Step 3: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/Resources ios/ESP32Car/L.swift
git commit -m "feat(ios): ramp screen strings (headline/sub/value)"
```
(Сборка временно красная — SettingsView ещё на старых ключах; чинится в Task 2.)

---

## Task 2: `RampView` + пункт меню

**Files:** Create `ios/ESP32Car/RampView.swift`; Modify `ios/ESP32Car/SettingsView.swift`.

- [ ] **Step 1: Создать `ios/ESP32Car/RampView.swift`**
```swift
import SwiftUI

/// Dedicated "Разгон" screen: demo car on the left, slider on the right (calib/firmware layout).
struct RampView: View {
    let palette: Palette
    @State private var rampMs = 300
    private var p: Palette { palette }

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()
            HStack(spacing: 24) {
                RampCarView(rampMs: rampMs, palette: p)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                rightPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        }
        .navigationTitle(L.rampTitle)
        .navigationBarTitleDisplayMode(.inline)
        .tint(p.accent)
        .task { if let v = await RampClient().get() { rampMs = v } }
    }

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L.rampHeadline).font(.system(size: 22, weight: .semibold)).foregroundStyle(p.text)
            Text(L.rampSub).font(.system(size: 13)).foregroundStyle(p.muted)
                .fixedSize(horizontal: false, vertical: true)
            Slider(value: Binding(
                get: { Double(rampMs) },
                set: { rampMs = Int($0 / 50) * 50 }
            ), in: 0...1000) { editing in
                if !editing { Task { await RampClient().set(rampMs) } }
            }
            .tint(p.accent)
            .frame(width: 220)
            Text(rampMs > 0 ? L.rampValue(rampMs) : L.rampValueOff)
                .font(.system(size: 14)).foregroundStyle(p.muted).monospacedDigit()
        }
    }
}

/// Looping acceleration demo: pause → ramp up over rampMs (wheels colour up, chevrons speed up,
/// rails grow) → full speed → reset. Same car geometry as DriveDiagram.
struct RampCarView: View {
    let rampMs: Int
    let palette: Palette

    private let metal = Color(red: 0.227, green: 0.188, blue: 0.141)  // #3a3024
    private let carW: CGFloat = 36
    private let carLen: CGFloat = 74
    private let wheelW: CGFloat = 12
    private let wheelH: CGFloat = 20
    private let railGap: CGFloat = 12
    private let railMax: CGFloat = 52

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                render(&ctx, size, time: tl.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: 120, height: 210)
        .scaleEffect(1.45)
    }

    private func render(_ ctx: inout GraphicsContext, _ size: CGSize, time: Double) {
        // Demo cycle: pause 0.4s → accel rampMs (min 0.15s; instant look for 0) → hold 0.8s.
        let pause = 0.4
        let accelT = max(Double(rampMs) / 1000.0, 0.15)
        let hold = 0.8
        let total = pause + accelT + hold
        let t = time.truncatingRemainder(dividingBy: total)
        let progress: Double
        if t < pause { progress = 0 }
        else if t < pause + accelT { progress = rampMs == 0 ? 1 : (t - pause) / accelT }
        else { progress = 1 }
        // Chevron phase = ∫speed dt (smooth speed-up, no jumps within the cycle).
        let tempo = 70.0
        let phase: Double
        if t < pause { phase = 0 }
        else if t < pause + accelT { let u = t - pause; phase = tempo * u * u / (2 * accelT) }
        else { phase = tempo * (accelT / 2 + (t - pause - accelT)) }

        // Composition: rails above the car; car sits below centre so the whole group is centred.
        let center = CGPoint(x: size.width / 2, y: size.height * 0.62)

        if progress > 0.01 { drawRails(&ctx, center: center, progress: progress) }
        drawCar(&ctx, center: center)
        let wx = carW / 2 + 1
        let wy = carLen / 2 - 16
        for dx in [-wx, wx] {
            for dy in [-wy, wy] {
                drawWheel(&ctx, cx: center.x + dx, cy: center.y + dy, progress: progress, phase: phase)
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

    private func drawWheel(_ ctx: inout GraphicsContext, cx: CGFloat, cy: CGFloat, progress: Double, phase: Double) {
        let rect = CGRect(x: cx - wheelW / 2, y: cy - wheelH / 2, width: wheelW, height: wheelH)
        let wp = Path(roundedRect: rect, cornerRadius: 3)
        ctx.fill(wp, with: .color(metal))
        ctx.fill(wp, with: .color(palette.accent.opacity(progress)))   // dark → green as it spools up
        guard progress > 0.03 else { return }

        var c = ctx
        c.clip(to: wp)
        let spacing: CGFloat = 13 - 6 * CGFloat(progress)
        let offset = CGFloat(phase).truncatingRemainder(dividingBy: spacing)
        let ch: CGFloat = 4
        var k = -2
        while CGFloat(k) * spacing < wheelH + spacing {
            let base = rect.maxY - CGFloat(k) * spacing + offset   // forward: chevrons run up
            var p = Path()
            p.move(to: CGPoint(x: rect.minX + 1, y: base + ch))
            p.addLine(to: CGPoint(x: rect.midX, y: base - ch))
            p.addLine(to: CGPoint(x: rect.maxX - 1, y: base + ch))
            c.stroke(p, with: .color(palette.bg), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            k += 1
        }
    }

    private func drawRails(_ ctx: inout GraphicsContext, center: CGPoint, progress: Double) {
        let len = railMax * CGFloat(progress)
        let startY = center.y - carLen / 2 - railGap
        let halfW = carW / 2 + 2
        let grad = Gradient(colors: [palette.accent.opacity(0.95 * progress), palette.accent.opacity(0.04)])
        for side in [CGFloat(-1), CGFloat(1)] {
            var path = Path()
            path.move(to: CGPoint(x: center.x + side * halfW, y: startY))
            path.addLine(to: CGPoint(x: center.x + side * halfW, y: startY - len))
            ctx.stroke(path, with: .linearGradient(grad,
                startPoint: CGPoint(x: center.x, y: startY),
                endPoint: CGPoint(x: center.x, y: startY - railMax)),
                style: StrokeStyle(lineWidth: 6, lineCap: .round))
        }
    }
}
```

- [ ] **Step 2: `SettingsView.swift`** — заменить блок `Section {...} header: {...}` (инлайн-слайдер) на третий NavigationLink:
```swift
                    NavigationLink {
                        RampView(palette: palette)
                    } label: {
                        Label(L.rampTitle, systemImage: "gauge.with.needle")
                            .foregroundStyle(palette.text)
                    }
                    .listRowBackground(palette.panel)
```
И удалить из `SettingsView`: `@State private var rampMs = 300` и модификатор `.task { if let v = await RampClient().get() { rampMs = v } }` (загрузка теперь в RampView).

- [ ] **Step 3: Regenerate + build + grep**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -6
grep -rnE "rampLabel|rampOff\b|ramp\.label|ramp\.off" ESP32Car || echo "(нет)"
grep -rn '[А-Яа-яЁё]' --include='*.swift' ESP32Car && echo "CYRILLIC LEAK" || echo "(локализация чистая)"
```
Expected: `** BUILD SUCCEEDED **`, оба грепа чистые.

- [ ] **Step 4: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/RampView.swift ios/ESP32Car/SettingsView.swift
git commit -m "feat(ios): dedicated Ramp screen — menu item + acceleration demo car"
```

---

## Task 3: Проверка в симуляторе

**Files:** (временный харнесс, откатывается)

- [ ] **Step 1: Харнесс** — в `ESP32CarApp.swift` корень → `NavigationStack { RampView(palette: Theme.dark) }  // TEMP harness`; мок запущен.
- [ ] **Step 2: Билд + скриншот** (`/tmp/ramp_screen.png`): слева демо-машинка (композиция целиком отцентрована, рельсы над машинкой по осям колёс), справа «Плавный старт / подзаголовок / слайдер / NN мс» со значением с мока. Подвинуть нельзя (нет тача) — POST проверен в T5/T6 ранее.
- [ ] **Step 3: Откат харнесса** — вернуть корень; `grep -rn TEMP ios/ESP32Car` → нет; build SUCCEEDED.
- [ ] **Step 4: Скриншот меню** — продакшн-сборка → ⚙: три строки (Калибровка / Прошивка / Разгон) в одном стиле.

---

## Self-Review заметки

- **Покрытие спеки:** пункт меню `gauge.with.needle` + удаление секции (Task 2 Step 2); split-layout + правый блок headline/sub/слайдер/значение (RampView); демо-цикл пауза 0.4с → разгон `max(ramp_ms,150мс)` (мгновенный при 0) → hold 0.8с, колёса лерп тёмный→зелёный, шевроны с гладкой фазой (∫speed), рельсы от зазора над крышей по осям (RampCarView); строки headline/sub/value/valueOff + удаление label/off (Task 1); GET в `.task`, POST на отпускании (перенесено). Проверка (Task 3).
- **Тип-консистентность:** `RampView(palette:)`, `RampCarView(rampMs:palette:)`; `L.rampTitle/rampHeadline/rampSub/rampValueOff/rampValue(_:)`; `RampClient.get/set` (не меняется); геометрия = DriveDiagram (carW 36, carLen 74, wheel 12×20).
- **Замечания:** сборка после Task 1 временно красная (SettingsView на старых ключах) — нормально, Task 2 чинит; коммиты последовательные. Демо-фаза детерминирована внутри цикла (без межцикловой непрерывности — колёса в паузе тёмные).
