# iOS: вынос текстов в локализацию + аудит — Design

**Дата:** 2026-06-09
**Статус:** дизайн утверждён, готов к плану

## Цель

Вынести все пользовательские тексты iOS-приложения в файл переводов (под будущий второй язык),
заодно провести аудит формулировок: лаконично, по-русски, с заглавной буквы. Сейчас язык один —
русский; структура готова к добавлению второго.

## Решения

- **Механизм:** `ios/ESP32Car/Resources/ru.lproj/Localizable.strings` (файл переводов) + типизированный
  `enum L` (ключи/аксессоры) поверх `NSLocalizedString`. `CFBundleDevelopmentRegion = ru` — приложение
  показывает русский независимо от языка устройства. Второй язык = добавить `en.lproj/Localizable.strings`.
- **Русифицируем всё** (Spin→Крутить, Save→Сохранить, connected→На связи и т.д.). Значения схем
  (`arcade`/`tank` в `@AppStorage`) — это данные, не трогаем; меняем только подписи.

## Файл переводов `ru.lproj/Localizable.strings` (полный набор)

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

## `enum L` (аксессоры)

```swift
enum L {
    private static func s(_ key: String, _ args: CVarArg...) -> String {
        let f = NSLocalizedString(key, comment: "")
        return args.isEmpty ? f : String(format: f, arguments: args)
    }
    // простые
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
    // с подстановкой
    static func calibStep(_ n: Int) -> String { s("calib.step", n) }
    static func calibWhichDir(_ wheel: String) -> String { s("calib.whichDir", wheel) }
    static func calibSpinPrompt(_ n: Int) -> String { s("calib.spinPrompt", n) }
    static func driveConnected(_ ms: Int) -> String { s("drive.connected", ms) }
    static func driveUptime(_ sec: Int) -> String { s("drive.uptime", sec) }
    static func driveFw(_ v: String) -> String { s("drive.fw", v) }
}
```

## Замены во вью

- `ConnectView`: title/body/кнопка → `L.connectTitle/connectBody/openSettings`.
- `SettingsView`: `L.settingsTitle`, `L.settingsCalibration`, `L.close`.
- `CalibrationView`: `L.calibTitle`, `L.calibStep(...)`, `L.calibWhichDir(c.label)`, `L.calibForward/Back/Spin/AllSet/Save/SaveFailed`, `L.calibSpinPrompt(...)`.
- `DriveView`: статус-плашка `status.online ? L.driveConnected(status.pingMs ?? 0) : L.driveSearching`; статус-строка из `L.driveUptime/UptimeUnknown`, `L.driveCalibYes/No`, `L.driveFw/FwUnknown`; `L.later`; `L.sideLeft/sideRight` для L/R-подписей.
- `SchemeToggle`: подписи сегментов → `L.schemeArcade/schemeTank` (значения `"arcade"/"tank"` остаются).

## Конфиг (XcodeGen)

- В `project.yml`: добавить `ESP32Car/Resources` в `sources` таргета (чтобы `ru.lproj/Localizable.strings`
  попал в бандл); в `info.properties` добавить `CFBundleDevelopmentRegion: ru` и `CFBundleLocalizations: [ru]`.

## Тестирование

- **Сборка:** `xcodebuild` под симулятор-SDK.
- **Симулятор:** все экраны (Connect/Drive/Settings/Calibration) на русском, тексты совпадают с таблицей,
  нет «сырых ключей» (`calib.step` вместо текста); подстановки (шаг, пинг, %@) корректны; обе темы.
- Чистой логики нет; визуальная проверка.

## Вне объёма

- Второй язык сейчас (только структура).
- Локализация форматов чисел/множественного числа (plural rules) — пока простые `%d`.
- Прошивка/мок/протокол.
