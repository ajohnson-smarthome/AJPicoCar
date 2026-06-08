# iOS локализация текстов (ru) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Вынести все тексты iOS-приложения в `ru.lproj/Localizable.strings` через типизированный `enum L`, заодно русифицировав/причесав формулировки. Один язык (ru), структура под будущий второй.

**Architecture:** `enum L` (ключи поверх `NSLocalizedString`) + `Resources/ru.lproj/Localizable.strings` (файл переводов). `CFBundleDevelopmentRegion=ru`. Все вью используют `L.*`. Прошивка/мок не трогаются.

**Tech Stack:** Swift 6 / SwiftUI, `NSLocalizedString`, XcodeGen. Ветка `ios-localization`. Симулятор-SDK `iphonesimulator26.2`, устройство `iPhone 17`, мок `127.0.0.1:8080`.

---

## File Structure

| Файл | Ответственность |
|---|---|
| `ios/ESP32Car/Resources/ru.lproj/Localizable.strings` *(new)* | файл переводов (28 ключей) |
| `ios/ESP32Car/L.swift` *(new)* | типизированные аксессоры поверх `NSLocalizedString` |
| `ios/project.yml` | `CFBundleDevelopmentRegion: ru` + `CFBundleLocalizations: [ru]` |
| `ios/ESP32Car/{ConnectView,SettingsView,CalibrationView,DriveView,SchemeToggle}.swift` | литералы → `L.*` |

---

## Task 1: Файл переводов + `enum L` + конфиг

**Files:** Create `ios/ESP32Car/Resources/ru.lproj/Localizable.strings`, `ios/ESP32Car/L.swift`; Modify `ios/project.yml`.

- [ ] **Step 1: Создать `ios/ESP32Car/Resources/ru.lproj/Localizable.strings`**
```
"connect.title"      = "Машинка не найдена";
"connect.body"       = "Подключись к Wi-Fi «ESP32-Car» (пароль drive1234), затем вернись в приложение.";
"common.openSettings"= "Открыть настройки";
"common.close"       = "Закрыть";
"common.later"       = "Позже";
"settings.title"     = "Настройки";
"settings.calibration"= "Калибровка";
"calib.title"        = "Калибровка";
"calib.step"         = "Шаг %d из 4";
"calib.whichDir"     = "Колесо %@ — куда крутилось?";
"calib.forward"      = "Вперёд";
"calib.back"         = "Назад";
"calib.spinPrompt"   = "Крутится мотор %d — нажми на колесо, которое поехало.";
"calib.spin"         = "Крутить";
"calib.allSet"       = "Все колёса размечены.";
"calib.save"         = "Сохранить";
"calib.saveFailed"   = "Не удалось сохранить — повтори.";
"drive.connected"    = "На связи · %d мс";
"drive.searching"    = "Поиск…";
"drive.uptime"       = "вкл %d с";
"drive.uptimeUnknown"= "вкл —";
"drive.calibYes"     = "калибр ✓";
"drive.calibNo"      = "калибр ✗";
"drive.fw"           = "ПО %@";
"drive.fwUnknown"    = "ПО —";
"drive.sideLeft"     = "Л";
"drive.sideRight"    = "П";
"scheme.arcade"      = "Аркада";
"scheme.tank"        = "Танк";
```

- [ ] **Step 2: Создать `ios/ESP32Car/L.swift`**
```swift
import Foundation

/// Typed accessors for localized strings. Text lives in Resources/<lang>.lproj/Localizable.strings.
enum L {
    private static func s(_ key: String, _ args: CVarArg...) -> String {
        let f = NSLocalizedString(key, comment: "")
        return args.isEmpty ? f : String(format: f, arguments: args)
    }
    static var connectTitle: String { s("connect.title") }
    static var connectBody: String { s("connect.body") }
    static var openSettings: String { s("common.openSettings") }
    static var close: String { s("common.close") }
    static var later: String { s("common.later") }
    static var settingsTitle: String { s("settings.title") }
    static var settingsCalibration: String { s("settings.calibration") }
    static var calibTitle: String { s("calib.title") }
    static var calibForward: String { s("calib.forward") }
    static var calibBack: String { s("calib.back") }
    static var calibSpin: String { s("calib.spin") }
    static var calibAllSet: String { s("calib.allSet") }
    static var calibSave: String { s("calib.save") }
    static var calibSaveFailed: String { s("calib.saveFailed") }
    static var driveSearching: String { s("drive.searching") }
    static var driveUptimeUnknown: String { s("drive.uptimeUnknown") }
    static var driveCalibYes: String { s("drive.calibYes") }
    static var driveCalibNo: String { s("drive.calibNo") }
    static var driveFwUnknown: String { s("drive.fwUnknown") }
    static var sideLeft: String { s("drive.sideLeft") }
    static var sideRight: String { s("drive.sideRight") }
    static var schemeArcade: String { s("scheme.arcade") }
    static var schemeTank: String { s("scheme.tank") }
    static func calibStep(_ n: Int) -> String { s("calib.step", n) }
    static func calibWhichDir(_ wheel: String) -> String { s("calib.whichDir", wheel) }
    static func calibSpinPrompt(_ n: Int) -> String { s("calib.spinPrompt", n) }
    static func driveConnected(_ ms: Int) -> String { s("drive.connected", ms) }
    static func driveUptime(_ sec: Int) -> String { s("drive.uptime", sec) }
    static func driveFw(_ v: String) -> String { s("drive.fw", v) }
}
```

- [ ] **Step 3: `ios/project.yml` — dev region + localizations**
In the `ESP32Car` target's `info.properties`, add these two keys (alongside `CFBundleDisplayName` etc.):
```yaml
        CFBundleDevelopmentRegion: ru
        CFBundleLocalizations: [ru]
```
(`ESP32Car/Resources/ru.lproj/...` is already covered by `sources: [ESP32Car]` — XcodeGen bundles `.lproj` files as localized resources.)

- [ ] **Step 4: Regenerate + compile-check + confirm the .strings is bundled**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 -derivedDataPath /tmp/ddata 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -4
echo "=== strings bundled? ==="; find /tmp/ddata/Build/Products -path "*ESP32Car.app*" -name "Localizable.strings"
```
Expected: `** BUILD SUCCEEDED **` and a path ending in `.../ESP32Car.app/ru.lproj/Localizable.strings` (the file is in the bundle under `ru.lproj`). If it is NOT under `ru.lproj`, add an explicit localized resource entry in `project.yml` (`sources: - path: ESP32Car/Resources` with `buildPhase: resources`) and rebuild until the `ru.lproj/Localizable.strings` appears in the app bundle.

- [ ] **Step 5: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/Resources ios/ESP32Car/L.swift ios/project.yml
git commit -m "feat(ios): localization scaffolding — ru.lproj/Localizable.strings + enum L"
```

---

## Task 2: Заменить литералы на `L.*` во всех вью

**Files:** Modify `ios/ESP32Car/ConnectView.swift`, `SettingsView.swift`, `CalibrationView.swift`, `DriveView.swift`, `SchemeToggle.swift`.

- [ ] **Step 1: `ConnectView.swift`**
Replace `Text("Машинка не найдена")` → `Text(L.connectTitle)`; the long Wi-Fi `Text("Подключись…")` → `Text(L.connectBody)`; `Button("Открыть Настройки")` → `Button(L.openSettings)`.

- [ ] **Step 2: `SettingsView.swift`**
`Label("Калибровка", systemImage: "gearshape.2")` → `Label(L.settingsCalibration, systemImage: "gearshape.2")`; `.navigationTitle("Настройки")` → `.navigationTitle(L.settingsTitle)`; `Button("Закрыть")` → `Button(L.close)`.

- [ ] **Step 3: `CalibrationView.swift`**
- `.navigationTitle("Калибровка")` → `.navigationTitle(L.calibTitle)`
- `Text("Шаг \(min(step + 1, 4)) из 4")` → `Text(L.calibStep(min(step + 1, 4)))`
- `Text("Колесо \(c.label) — куда крутилось?")` → `Text(L.calibWhichDir(c.label))`
- `Label("вперёд", systemImage: "arrow.up")` → `Label(L.calibForward, systemImage: "arrow.up")`
- `Label("назад", systemImage: "arrow.down")` → `Label(L.calibBack, systemImage: "arrow.down")`
- `Text("Крутится мотор \(step + 1) — тапни колесо, которое поехало.")` → `Text(L.calibSpinPrompt(step + 1))`
- `Label("Spin", systemImage: "play.fill")` → `Label(L.calibSpin, systemImage: "play.fill")`
- `Text("Все колёса размечены.")` → `Text(L.calibAllSet)`
- `Label("Save", systemImage: "checkmark")` → `Label(L.calibSave, systemImage: "checkmark")`
- `errMsg = "Сохранение не прошло — повтори."` → `errMsg = L.calibSaveFailed`

- [ ] **Step 4: `DriveView.swift`**
- Status pill: `Text(status.online ? "connected · \(status.pingMs ?? 0) ms" : "searching…")` →
  `Text(status.online ? L.driveConnected(status.pingMs ?? 0) : L.driveSearching)`
- `statusLine` computed property body →
  ```swift
        let up = status.uptimeS.map { L.driveUptime($0) } ?? L.driveUptimeUnknown
        let cal = (status.calibrated ?? false) ? L.driveCalibYes : L.driveCalibNo
        let fw = status.fw.map { L.driveFw($0) } ?? L.driveFwUnknown
        return "\(up) · \(cal) · \(fw)"
  ```
- `sideLabel("L", sides.left)` → `sideLabel(L.sideLeft, sides.left)`; `sideLabel("R", sides.right)` → `sideLabel(L.sideRight, sides.right)`
- `Button("Позже") { showCalib = false }` → `Button(L.later) { showCalib = false }`

- [ ] **Step 5: `SchemeToggle.swift`**
Segment labels: `seg("Arcade", "arcade")` → `seg(L.schemeArcade, "arcade")`; `seg("Tank", "tank")` → `seg(L.schemeTank, "tank")`.
(If the file builds the two segments inline rather than via a `seg(_:_:)` helper, replace the two display strings `"Arcade"`/`"Tank"` with `L.schemeArcade`/`L.schemeTank`, leaving the `"arcade"`/`"tank"` data values untouched.)

- [ ] **Step 6: Regenerate + compile-check + grep for leftover literals**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -6
echo "=== остались ли кириллические литералы во вью? ==="
grep -rnoE '"[А-Яа-яЁё][^"]*"' ESP32Car/{ConnectView,SettingsView,CalibrationView,DriveView,SchemeToggle}.swift || echo "(нет — всё через L)"
```
Expected: `** BUILD SUCCEEDED **`, and the grep prints nothing (no Cyrillic literals remain in the views).

- [ ] **Step 7: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/ConnectView.swift ios/ESP32Car/SettingsView.swift ios/ESP32Car/CalibrationView.swift ios/ESP32Car/DriveView.swift ios/ESP32Car/SchemeToggle.swift
git commit -m "feat(ios): route all UI strings through L (localized, russified)"
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
- статус-плашка «На связи · N мс» / «Поиск…»; статус-строка «вкл N с · калибр ✓ · ПО mock»; подписи Л/П; переключатель «Аркада/Танк»;
- Settings: «Настройки» / «Калибровка» / «Закрыть»;
- Calibration: «Калибровка», «Шаг 1 из 4», «Крутится мотор 1 — нажми на колесо…», «Крутить», «Вперёд/Назад», «Сохранить»;
- НИГДЕ не видно сырых ключей (типа `calib.step`).
Скриншот: `xcrun simctl io booted screenshot /tmp/loc.png`.

---

## Self-Review заметки

- **Покрытие спеки:** все 28 ключей в `.strings` (Task 1); `enum L` со всеми аксессорами; конфиг dev-region (Task 1 Step 3); замены во всех 5 вью (Task 2); проверка русского без сырых ключей (Task 3).
- **Тип-консистентность:** имена `L.*` в Task 2 совпадают с объявленными в Task 1 `L.swift` (connectTitle/connectBody/openSettings/close/later/settingsTitle/settingsCalibration/calibTitle/calibForward/calibBack/calibSpin/calibAllSet/calibSave/calibSaveFailed/driveSearching/driveUptimeUnknown/driveCalibYes/driveCalibNo/driveFwUnknown/sideLeft/sideRight/schemeArcade/schemeTank + функции calibStep/calibWhichDir/calibSpinPrompt/driveConnected/driveUptime/driveFw).
- **Тесты:** чистой логики нет; визуальная проверка (Task 3) + grep на остаточные литералы (Task 2 Step 6).
- **Замечания:** ключевой риск — попадёт ли `ru.lproj/Localizable.strings` в бандл и подхватится ли (Task 1 Step 4 это проверяет; при провале — явный resources-source). Подстановки `%d`/`%@` — целые/строка.
