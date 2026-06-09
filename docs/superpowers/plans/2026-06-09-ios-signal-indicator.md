# Индикатор сигнала (по пингу) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Заменить точку в плашке связи на 4 палочки «уровня сигнала», вычисляемого из пинга.

**Architecture:** Чистая `ControlModel.signalLevel(online:pingMs:) -> Int` (0–4, хост-тест) + presentational `SignalBars(level:color:)`; в `DriveView` точка-кружок → `SignalBars`. Прошивка не трогается.

**Tech Stack:** Swift 6 / SwiftUI, XCTest + нативный `swiftc`. Ветка `ios-signal`. Симулятор-SDK `iphonesimulator26.2`, устройство `iPhone 17`, мок `127.0.0.1:8080`.

---

## File Structure

| Файл | Изменение |
|---|---|
| `ios/ESP32Car/ControlModel.swift` | + `signalLevel(online:pingMs:)` |
| `ios/ESP32CarTests/ControlModelTests.swift` | + тест `signalLevel` |
| `ios/ESP32Car/SignalBars.swift` *(new)* | 4-палочный индикатор |
| `ios/ESP32Car/DriveView.swift` | точка в плашке → `SignalBars` + computed `signalLevel`/`signalColor` |

---

## Task 1: `ControlModel.signalLevel` (TDD)

**Files:** Modify `ios/ESP32Car/ControlModel.swift`, `ios/ESP32CarTests/ControlModelTests.swift`.

- [ ] **Step 1: Native check `/tmp/sig_check.swift`**
```swift
import Foundation
func run() {
    precondition(ControlModel.signalLevel(online: false, pingMs: 10) == 0, "offline")
    precondition(ControlModel.signalLevel(online: true, pingMs: nil) == 0, "nil ping")
    precondition(ControlModel.signalLevel(online: true, pingMs: 10) == 4, "excellent")
    precondition(ControlModel.signalLevel(online: true, pingMs: 100) == 3, "good")
    precondition(ControlModel.signalLevel(online: true, pingMs: 200) == 2, "ok")
    precondition(ControlModel.signalLevel(online: true, pingMs: 400) == 1, "weak")
    print("signal checks: all passed")
}
```
And `/tmp/main.swift` containing `run()`.

- [ ] **Step 2: Run native check — FAIL**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && swiftc ios/ESP32Car/ControlModel.swift /tmp/sig_check.swift /tmp/main.swift -o /tmp/sig_check 2>&1 | tail -3
```
Expected: error `has no member 'signalLevel'`.

- [ ] **Step 3: Add to `enum ControlModel` (after `sides`)**
```swift
    /// Link-quality level 0...4 from ping (we can't read real Wi-Fi RSSI on iOS).
    static func signalLevel(online: Bool, pingMs: Int?) -> Int {
        guard online, let p = pingMs else { return 0 }
        if p < 50 { return 4 }
        if p < 120 { return 3 }
        if p < 250 { return 2 }
        return 1
    }
```

- [ ] **Step 4: Run native check — PASS**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && swiftc ios/ESP32Car/ControlModel.swift /tmp/sig_check.swift /tmp/main.swift -o /tmp/sig_check && /tmp/sig_check
```
Expected: `signal checks: all passed`.

- [ ] **Step 5: Mirror into XCTest** — append before the final `}` of the class:
```swift
    func testSignalLevel() {
        XCTAssertEqual(ControlModel.signalLevel(online: false, pingMs: 10), 0)
        XCTAssertEqual(ControlModel.signalLevel(online: true, pingMs: nil), 0)
        XCTAssertEqual(ControlModel.signalLevel(online: true, pingMs: 10), 4)
        XCTAssertEqual(ControlModel.signalLevel(online: true, pingMs: 100), 3)
        XCTAssertEqual(ControlModel.signalLevel(online: true, pingMs: 200), 2)
        XCTAssertEqual(ControlModel.signalLevel(online: true, pingMs: 400), 1)
    }
```

- [ ] **Step 6: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/ControlModel.swift ios/ESP32CarTests/ControlModelTests.swift
git commit -m "feat(ios): ControlModel.signalLevel (ping → 0..4) + test"
```

---

## Task 2: `SignalBars` + плашка в `DriveView`

**Files:** Create `ios/ESP32Car/SignalBars.swift`; Modify `ios/ESP32Car/DriveView.swift`.

- [ ] **Step 1: Создать `ios/ESP32Car/SignalBars.swift`**
```swift
import SwiftUI

/// Four ascending signal bars, filled up to `level` (0...4).
struct SignalBars: View {
    let level: Int
    let color: Color
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i <= level ? color : color.opacity(0.18))
                    .frame(width: 3, height: CGFloat(2 + i * 3))
            }
        }
        .frame(height: 14)
    }
}
```

- [ ] **Step 2: `DriveView.swift` — computed уровень/цвет**
Add near other computed properties (e.g. after `private var p: Palette { ... }`):
```swift
    private var signalLevel: Int { ControlModel.signalLevel(online: status.online, pingMs: status.pingMs) }
    private var signalColor: Color { signalLevel == 0 ? .red : (signalLevel == 1 ? p.warn : p.accent) }
```

- [ ] **Step 3: `DriveView.swift` — точка → `SignalBars`**
In the connection pill, replace:
```swift
                        Circle().fill(status.online ? p.accent : Color.orange).frame(width: 8, height: 8)
```
with:
```swift
                        SignalBars(level: signalLevel, color: signalColor)
```

- [ ] **Step 4: Regenerate + compile-check**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -6
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/SignalBars.swift ios/ESP32Car/DriveView.swift
git commit -m "feat(ios): signal bars in the connection pill (ping-derived)"
```

---

## Task 3: Проверка в симуляторе

**Files:** (проверка — без изменений кода)

- [ ] **Step 1: Мок + запуск**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/tools/mock_car
pgrep -f mock_car.py >/dev/null || { nohup .venv/bin/python -u mock_car.py > /tmp/mock_car.log 2>&1 & disown; }
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios
xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | grep -iE "BUILD SUCCEEDED|FAILED" | head -1
xcrun simctl install booted "$(find /tmp/ddata/Build/Products -name ESP32Car.app | head -1)"
xcrun simctl terminate booted com.adamjohnson.esp32car 2>/dev/null
xcrun simctl launch booted com.adamjohnson.esp32car
```

- [ ] **Step 2: Визуально**
- в плашке связи слева — 4 палочки (мок отвечает быстро → 4 зелёные) + «На связи · N мс»;
- обе темы; нет регрессов в верхней панели.
Скриншот: `xcrun simctl io booted screenshot /tmp/sig.png`.

---

## Self-Review заметки

- **Покрытие спеки:** `signalLevel` пороги 50/120/250 + офлайн=0 (Task 1); `SignalBars(level:color:)` 4 палочки приглушаются выше уровня (Task 2 Step 1); плашка точка→палочки + цвет 0=red/1=warn/≥2=accent (Step 2–3). Проверка (Task 3).
- **Тип-консистентность:** `ControlModel.signalLevel(online:pingMs:)`, `SignalBars(level:color:)`, `signalLevel`/`signalColor` в DriveView; `status.online`(Bool)/`status.pingMs`(Int?), `p.warn`/`p.accent` — есть.
- **Тесты:** `signalLevel` — нативно + XCTest; вид — визуально (Task 3).
- **Замечания:** офлайн-цвет `.red` (системный) — на тёплых темах читаемо; при желании заменить на палитру. Пороги тюнятся в `signalLevel`.
