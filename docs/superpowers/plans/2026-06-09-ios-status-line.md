# Нижняя строка статуса (редизайн) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Заменить нижнюю строку статуса на drive-экране на три инлайн-элемента «иконка + значение» (человеко-аптайм · калибровка · версия ПО).

**Architecture:** Новый `L.uptime(sec)` + ключи `uptime.*`, ключи «откалибрована/не откалибрована»; в `DriveView` старый `statusLine`(String) → `statusBar`(HStack из SF-Symbol элементов). Удаляются устаревшие L-ключи старой строки. Прошивка не трогается.

**Tech Stack:** Swift 6 / SwiftUI, `NSLocalizedString`, XcodeGen. Ветка `ios-status-line`. Симулятор-SDK `iphonesimulator26.2`, устройство `iPhone 17`, мок `127.0.0.1:8080`.

---

## File Structure

| Файл | Изменение |
|---|---|
| `ios/ESP32Car/Resources/ru.lproj/Localizable.strings` | +6 ключей (`uptime.*`, calibrated yes/no), −6 устаревших |
| `ios/ESP32Car/L.swift` | +`uptime(_:)`, +calibrated yes/no; −6 устаревших аксессоров |
| `ios/ESP32Car/DriveView.swift` | `statusLine`(String) → `statusBar`(иконки) |

---

## Task 1: Строки + `L` + `DriveView`

**Files:** Modify `ios/ESP32Car/Resources/ru.lproj/Localizable.strings`, `ios/ESP32Car/L.swift`, `ios/ESP32Car/DriveView.swift`.

- [ ] **Step 1: `Localizable.strings` — удалить устаревшие, добавить новые**
Delete these 6 lines:
```
"drive.uptime"       = "вкл %d с";
"drive.uptimeUnknown"= "вкл —";
"drive.calibYes"     = "калибр ✓";
"drive.calibNo"      = "калибр ✗";
"drive.fw"           = "ПО %@";
"drive.fwUnknown"    = "ПО —";
```
Add these:
```
"uptime.sec"     = "%d с";
"uptime.min"     = "%d мин";
"uptime.hourMin" = "%d ч %d мин";
"uptime.day"     = "%d дн";
"drive.calibratedYes" = "откалибрована";
"drive.calibratedNo"  = "не откалибрована";
```

- [ ] **Step 2: `L.swift` — удалить устаревшие аксессоры**
Delete these lines:
```swift
    static var driveUptimeUnknown: String { s("drive.uptimeUnknown") }
    static var driveCalibYes: String { s("drive.calibYes") }
    static var driveCalibNo: String { s("drive.calibNo") }
    static var driveFwUnknown: String { s("drive.fwUnknown") }
    static func driveUptime(_ sec: Int) -> String { s("drive.uptime", sec) }
    static func driveFw(_ v: String) -> String { s("drive.fw", v) }
```

- [ ] **Step 3: `L.swift` — добавить новые** (рядом с остальными `drive*`/функциями)
```swift
    static var driveCalibratedYes: String { s("drive.calibratedYes") }
    static var driveCalibratedNo: String { s("drive.calibratedNo") }
    static func uptime(_ sec: Int) -> String {
        if sec < 60 { return s("uptime.sec", sec) }
        if sec < 3600 { return s("uptime.min", sec / 60) }
        if sec < 86400 { return s("uptime.hourMin", sec / 3600, (sec % 3600) / 60) }
        return s("uptime.day", sec / 86400)
    }
```

- [ ] **Step 4: `DriveView.swift` — удалить `statusLine`**
Delete the whole computed property:
```swift
    private var statusLine: String {
        let up = status.uptimeS.map { L.driveUptime($0) } ?? L.driveUptimeUnknown
        let cal = (status.calibrated ?? false) ? L.driveCalibYes : L.driveCalibNo
        let fw = status.fw.map { L.driveFw($0) } ?? L.driveFwUnknown
        return "\(up) · \(cal) · \(fw)"
    }
```

- [ ] **Step 5: `DriveView.swift` — добавить `statusBar` + `statusItem`**
Add these two methods (e.g. where `statusLine` was):
```swift
    private var statusBar: some View {
        HStack(spacing: 16) {
            statusItem("clock", status.uptimeS.map { L.uptime($0) } ?? "—", p.muted)
            let ok = status.calibrated ?? false
            statusItem(ok ? "checkmark.circle.fill" : "xmark.circle",
                       ok ? L.driveCalibratedYes : L.driveCalibratedNo,
                       ok ? p.accent : p.warn)
            statusItem("cpu", status.fw ?? "—", p.muted)
        }
        .font(.system(size: 10))
    }
    private func statusItem(_ icon: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(color.opacity(0.85))
            Text(text).foregroundStyle(color)
        }
    }
```

- [ ] **Step 6: `DriveView.swift` — использовать `statusBar` в нижнем VStack**
Find:
```swift
            VStack {
                Spacer()
                Text(statusLine).font(.system(size: 10)).foregroundStyle(p.muted).padding(.bottom, 20)
            }
```
Replace the inner `Text(statusLine)…` line with:
```swift
                statusBar.padding(.bottom, 20)
```
(so the VStack becomes `VStack { Spacer(); statusBar.padding(.bottom, 20) }`).

- [ ] **Step 7: Regenerate + compile-check + grep for stale refs**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -6
echo "=== остались ли ссылки на удалённые ключи/аксессоры? ==="
grep -rnE "statusLine|driveUptime|driveCalibYes|driveCalibNo|driveFw|drive\.uptime|drive\.fw|drive\.calibYes|drive\.calibNo" ESP32Car || echo "(нет)"
```
Expected: `** BUILD SUCCEEDED **`, и grep печатает `(нет)`.

- [ ] **Step 8: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/Resources ios/ESP32Car/L.swift ios/ESP32Car/DriveView.swift
git commit -m "feat(ios): redesign drive status line — inline icons, human uptime"
```

---

## Task 2: Проверка в симуляторе

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
- нижняя строка: `⏱ <аптайм> · ✓ откалибрована · ▣ mock` (SF-иконки, человеко-аптайм);
- если мок `calibrated=false` → `✗ не откалибрована` янтарным (перезапусти мок для проверки);
- нет сырых ключей; обе темы.
Скриншот: `xcrun simctl io booted screenshot /tmp/sl.png`.

---

## Self-Review заметки

- **Покрытие спеки:** новые ключи `uptime.*` + calibrated yes/no и `L.uptime` (Task 1 Step 1–3); удаление устаревших (Step 1–2); `statusBar` с тремя SF-Symbol элементами, калибровка accent/warn (Step 5); подстановка в нижний VStack (Step 6). Проверка (Task 2).
- **Тип-консистентность:** `L.uptime(_:)`, `L.driveCalibratedYes/No`; в `DriveView` — `statusBar`/`statusItem(_:_:_:)`; `status.uptimeS`(Int?)/`status.calibrated`(Bool?)/`status.fw`(String?) — существуют; `p.muted/accent/warn` — есть. Grep (Step 7) ловит остаточные ссылки на удалённое.
- **Тесты:** логика порога аптайма тривиальна (3 ветки) — визуальная проверка (Task 2); чистого юнита не требуется.
- **Замечания:** SF Symbols `clock`/`checkmark.circle.fill`/`xmark.circle`/`cpu` — стандартные. Имя симулятора `iPhone 17`.
