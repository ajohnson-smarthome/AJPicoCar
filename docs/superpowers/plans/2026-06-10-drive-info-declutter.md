# Расчистка инфо-элементов + обязательная калибровка — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Верх — «палочки + N мс»; низ пуст (только «⚠ Обрывов: N»); uptime/версия — футером в настройках; первичная калибровка обязательна (без «Позже», не закрыть свайпом).

**Architecture:** Только iOS: правки строк, `DriveView` (плашка/статус-бар/шит калибровки), футер в `SettingsView`. Прошивка/мок не меняются.

**Tech Stack:** Swift 6 / SwiftUI. Ветка `declutter`. SDK `iphonesimulator26.2`, `iPhone 17`, мок.

---

## File Structure

| Файл | Изменение |
|---|---|
| `ios/ESP32Car/Resources/ru.lproj/Localizable.strings` + `L.swift` | connected→"%d мс", wdtTrips с заглавной; − calibratedYes/No, later |
| `ios/ESP32Car/DriveView.swift` | плашка, минимальный statusBar, обязательный шит |
| `ios/ESP32Car/SettingsView.swift` | футер `⏱ · ▣` |

---

## Task 1: Строки + `L`

**Files:** Modify `ios/ESP32Car/Resources/ru.lproj/Localizable.strings`, `ios/ESP32Car/L.swift`.

- [ ] **Step 1: `Localizable.strings`** — изменить:
```
"drive.connected"    = "%d мс";
"drive.wdtTrips"     = "Обрывов: %d";
```
(было `"На связи · %d мс"` и `"обрывов: %d"`). Удалить строки:
```
"common.later"       = "Позже";
"drive.calibratedYes"= "откалибрована";
"drive.calibratedNo" = "не откалибрована";
```

- [ ] **Step 2: `L.swift`** — удалить аксессоры:
```swift
    static var later: String { s("common.later") }
    static var driveCalibratedYes: String { s("drive.calibratedYes") }
    static var driveCalibratedNo: String { s("drive.calibratedNo") }
```
(`driveConnected`/`driveWdtTrips`/`uptime` остаются как есть.)

- [ ] **Step 3: Commit** (сборка временно красная до Task 2 — DriveView ссылается на удалённое):
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/Resources ios/ESP32Car/L.swift
git commit -m "feat(ios): declutter strings — terse ping, capitalized warning, drop later/calibrated"
```

---

## Task 2: `DriveView`

**Files:** Modify `ios/ESP32Car/DriveView.swift`.

- [ ] **Step 1: Удалить стейт-флаг** — строку `@State private var didPromptCalib = false`.

- [ ] **Step 2: statusBar → только предупреждения.** Заменить:
```swift
    private var statusBar: some View {
        HStack(spacing: 16) {
            statusItem("clock", status.uptimeS.map { L.uptime($0) } ?? "—", p.muted)
            let ok = status.calibrated ?? false
            statusItem(ok ? "checkmark.circle.fill" : "xmark.circle",
                       ok ? L.driveCalibratedYes : L.driveCalibratedNo,
                       ok ? p.accent : p.warn)
            statusItem("cpu", status.fw ?? "—", p.muted)
            if let trips = status.wdtTrips, trips > 0 {
                statusItem("exclamationmark.triangle", L.driveWdtTrips(trips), p.warn)
            }
        }
        .font(.system(size: 10))
    }
```
на:
```swift
    // Empty in the normal case: only amber warnings ever appear here.
    private var statusBar: some View {
        HStack(spacing: 16) {
            if let trips = status.wdtTrips, trips > 0 {
                statusItem("exclamationmark.triangle", L.driveWdtTrips(trips), p.warn)
            }
        }
        .font(.system(size: 10))
    }
```

- [ ] **Step 3: Обязательный шит.** Заменить:
```swift
        .onReceive(status.$calibrated) { cal in
            if cal == false && !didPromptCalib { didPromptCalib = true; showCalib = true }
        }
        .sheet(isPresented: $showCalib) {
            NavigationStack {
                CalibrationView(palette: p)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button(L.later) { showCalib = false } }
                    }
            }
        }
```
на:
```swift
        .onReceive(status.$calibrated) { cal in
            if cal == false { showCalib = true }        // mandatory: reopens until calibrated
        }
        .sheet(isPresented: $showCalib) {
            NavigationStack {
                CalibrationView(palette: p)
            }
            .interactiveDismissDisabled(true)
        }
```

- [ ] **Step 4: Build + grep**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -6
grep -rnE "L\.later|driveCalibratedYes|driveCalibratedNo|didPromptCalib|common\.later|drive\.calibrated" ESP32Car || echo "(нет)"
```
Expected: `** BUILD SUCCEEDED **`, grep `(нет)`.

- [ ] **Step 5: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/DriveView.swift
git commit -m "feat(ios): clean drive HUD (warnings-only bottom, terse ping) + mandatory calibration sheet"
```

---

## Task 3: Футер в настройках

**Files:** Modify `ios/ESP32Car/SettingsView.swift`.

- [ ] **Step 1:** обернуть `List` в `VStack(spacing: 0)` и добавить футер после него (внутри ZStack):
```swift
                VStack(spacing: 0) {
                    List {
                        // ... существующие NavigationLink без изменений ...
                    }
                    .scrollContentBackground(.hidden)
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                            Text(status.uptimeS.map { L.uptime($0) } ?? "—")
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "cpu")
                            Text(status.fw ?? "—")
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(palette.muted)
                    .padding(.bottom, 10)
                }
```

- [ ] **Step 2: Build**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -4
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/SettingsView.swift
git commit -m "feat(ios): settings footer with uptime + fw version"
```

---

## Task 4: Проверка в симуляторе

- [ ] **Step 1: Норма** — мок calibrated=true, `wdt_trips:0` → главный: верх «палочки + N мс» (без «На связи»), низ пустой. Скриншот.
- [ ] **Step 2: Предупреждение** — мок `wdt_trips:3` (временная правка + рестарт) → внизу «⚠ Обрывов: 3». Вернуть 0.
- [ ] **Step 3: Обязательная калибровка** — мок calibrated=false → шит калибровки без «Позже» (тулбар пуст). Скриншот. (Свайп проверить нельзя без тача — `interactiveDismissDisabled` компилируется и декларативен.)
- [ ] **Step 4: Футер настроек** — харнесс SettingsView → внизу `⏱ … · ▣ mock`. Скриншот, откат харнесса, чистое дерево.

---

## Self-Review заметки

- **Покрытие спеки:** плашка «N мс» (через изменённую строку `drive.connected` — код DriveView не меняется), statusBar только ⚠ с заглавной (T1+T2), обязательный шит (T2 Step 3: без Позже, interactiveDismissDisabled, реоткрытие по статусу), футер (T3), удаление строк (T1). Проверка (T4).
- **Тип-консистентность:** `L.driveConnected(_:)` остаётся (формат поменялся в .strings); `L.uptime` используется футером; `status.uptimeS/fw/wdtTrips` существуют.
- **Замечания:** реоткрытие шита: `onReceive` сработает на каждом поллинге (1.5 с) пока false — `showCalib = true` идемпотентен. После Save мастер делает `dismiss()`; статус станет true → больше не откроется.
