# Сегментные LED-указатели мощности — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Заменить текст «Л NN%/П NN%» на главном экране сегментными LED-полосами мощности (зелёные вверх вперёд / янтарные вниз назад).

**Architecture:** Новый `PowerBar(value:palette:)` (5 вверх + центр + 5 вниз, горят от центра наружу). В `DriveView` заменить `sideLabel` на `PowerBar`, шире зазор; убрать строки `sideLeft/sideRight`.

**Tech Stack:** Swift 6 / SwiftUI. Ветка `power-bars`. SDK `iphonesimulator26.2`, `iPhone 17`, мок.

---

## File Structure

| Файл | Изменение |
|---|---|
| `ios/ESP32Car/PowerBar.swift` *(new)* | сегментная полоса мощности |
| `ios/ESP32Car/DriveView.swift` | `PowerBar` вместо `sideLabel`, шире зазор |
| `ios/ESP32Car/L.swift` + `ru.lproj/Localizable.strings` | удалить `sideLeft`/`sideRight` |

---

## Task 1: `PowerBar`

**Files:** Create `ios/ESP32Car/PowerBar.swift`.

- [ ] **Step 1: Создать `ios/ESP32Car/PowerBar.swift`**
```swift
import SwiftUI

/// Center-anchored segmented power meter for one side. value ∈ [-1, 1]:
/// forward (>0) lights green segments upward from the centre, reverse (<0) lights amber downward.
struct PowerBar: View {
    let value: Double
    let palette: Palette

    private let count = 5
    private let off = Color(red: 0.141, green: 0.122, blue: 0.090)  // #241f17

    var body: some View {
        let lit = min(count, Int((abs(value) * Double(count)).rounded()))
        let fwd = value > 0.03
        let rev = value < -0.03
        VStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { i in        // up = forward, lit from centre out
                seg(on: fwd && (count - i) <= lit, color: palette.accent)
            }
            RoundedRectangle(cornerRadius: 1).fill(palette.line).frame(width: 22, height: 2)
            ForEach(0..<count, id: \.self) { i in        // down = reverse, lit from centre out
                seg(on: rev && (i + 1) <= lit, color: palette.warn)
            }
        }
    }

    private func seg(on: Bool, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(on ? color : off)
            .frame(width: 18, height: 6)
            .shadow(color: on ? color.opacity(0.5) : .clear, radius: on ? 3 : 0)
    }
}
```

- [ ] **Step 2: Regenerate + compile-check**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -4
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/PowerBar.swift && git commit -m "feat(ios): PowerBar — segmented LED power meter"
```

---

## Task 2: `DriveView` + строки

**Files:** Modify `ios/ESP32Car/DriveView.swift`, `ios/ESP32Car/L.swift`, `ios/ESP32Car/Resources/ru.lproj/Localizable.strings`.

- [ ] **Step 1: Заменить центральный `HStack`** в `DriveView.body`:
```swift
            HStack(spacing: 34) {
                sideLabel(L.sideLeft, sides.left)
                DriveDiagram(t: curT, y: curY, palette: p)
                sideLabel(L.sideRight, sides.right)
            }
```
на:
```swift
            HStack(spacing: 44) {
                PowerBar(value: sides.left, palette: p)
                DriveDiagram(t: curT, y: curY, palette: p)
                PowerBar(value: sides.right, palette: p)
            }
```

- [ ] **Step 2: Удалить `sideLabel(_:_:)`** из `DriveView` (весь метод):
```swift
    private func sideLabel(_ name: String, _ v: Double) -> some View {
        VStack(spacing: 2) {
            Text(name).font(.system(size: 13)).foregroundStyle(p.accent)
            Text("\(Int(v * 100))%")
                .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                .foregroundStyle(p.accent)
        }
        .frame(width: 64)  // fixed width so the car doesn't shift as the % text changes
    }
```

- [ ] **Step 3: Удалить строки `drive.sideLeft`/`drive.sideRight`** из `Localizable.strings`:
```
"drive.sideLeft"     = "Л";
"drive.sideRight"    = "П";
```

- [ ] **Step 4: Удалить аксессоры** из `L.swift`:
```swift
    static var sideLeft: String { s("drive.sideLeft") }
    static var sideRight: String { s("drive.sideRight") }
```

- [ ] **Step 5: Regenerate + build + grep остатков**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -6
grep -rnE "sideLabel|L\.sideLeft|L\.sideRight|drive\.sideLeft|drive\.sideRight" ESP32Car || echo "(нет)"
```
Expected: `** BUILD SUCCEEDED **`, grep `(нет)`.

- [ ] **Step 6: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/DriveView.swift ios/ESP32Car/L.swift ios/ESP32Car/Resources
git commit -m "feat(ios): power bars on drive screen (replace L/R text), wider spacing"
```

---

## Task 3: Проверка (симулятор + форс-харнесс)

**Files:** (проверка)

- [ ] **Step 1: Idle-скрин** — мок calibrated=true, запуск, скриншот: полосы по бокам, все сегменты погашены, видна центр-линия; шире разнесены; без Л/П.
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/tools/mock_car
pgrep -f mock_car.py >/dev/null || { nohup .venv/bin/python -u mock_car.py >/tmp/mock_car.log 2>&1 & disown; }
curl -s -X POST --data "0:1,1:-1,2:1,3:-1" http://127.0.0.1:8080/calib/save >/dev/null
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios
xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | grep -iE "BUILD SUCCEEDED|FAILED" | head -1
xcrun simctl install booted "$(find /tmp/ddata/Build/Products -name ESP32Car.app | head -1)"
xcrun simctl terminate booted com.adamjohnson.esp32car 2>/dev/null
xcrun simctl launch booted com.adamjohnson.esp32car; sleep 3
xcrun simctl io booted screenshot /tmp/power_idle.png
```
- [ ] **Step 2: Форс-харнесс активных состояний** — временно в `ESP32CarApp.swift` корень → стек `HStack { PowerBar(value: 1, ...); PowerBar(value: -0.6, ...); PowerBar(value: 0, ...) }` на тёмном фоне; билд + скриншот: зелёные вверх / янтарные вниз / погашено, горят от центра. Откатить харнесс (grep TEMP → нет).
- [ ] **Step 3: Запустить продакшн в симуляторе.**

---

## Self-Review заметки

- **Покрытие спеки:** `PowerBar` 5+центр+5, горят от центра по `round(|value|·5)`, зелёный вверх/янтарный вниз, off-цвет тёмный + свечение (Task 1); замена `sideLabel`→`PowerBar` + шире зазор + удаление `sideLabel` (Task 2 1–2); удаление `sideLeft/sideRight` строк/аксессоров (Task 2 3–4). Проверка (Task 3).
- **Тип-консистентность:** `PowerBar(value:palette:)`; `ControlModel.sides` → `sides.left/right` (Double); `palette.accent/warn/line`. Grep (Task 2 Step 5) ловит остатки.
- **Тесты:** логика `lit` тривиальна (в вью); проверка — сборка + скриншоты.
- **Замечания:** зазор 44 подгонится по скриншоту. off-цвет `#241f17` фиксированный (как в макете).
