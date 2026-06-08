# Кнопка ⚙ + экран настроек (заглушка калибровки) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Добавить в пульт кнопку-шестерёнку рядом с переключателем режима, открывающую экран настроек со строкой «Калибровка» (заглушка).

**Architecture:** Новый `SettingsView` (лист настроек, презентуется `.sheet`) со строкой «Калибровка» → стаб-экран «в разработке». В `DriveView` — кнопка `⚙` в топ-баре справа от `SchemeToggle` + `@State showSettings` + `.sheet`. Темизировано из `Palette`. Прошивка/мок не трогаются.

**Tech Stack:** Swift 6 / SwiftUI (`NavigationStack`, `.sheet`, SF Symbols). Ветка `ios-app-phase1`. Симулятор-SDK `iphonesimulator26.2`, устройство `iPhone 17`.

---

## File Structure

| Файл | Ответственность |
|---|---|
| `ios/ESP32Car/SettingsView.swift` *(new)* | лист настроек (sheet) + строка «Калибровка» → стаб `CalibrationStub` |
| `ios/ESP32Car/DriveView.swift` | кнопка `⚙` в топ-баре + `@State showSettings` + `.sheet` |

---

## Task 1: `SettingsView` + кнопка ⚙ в `DriveView`

**Files:** Create `ios/ESP32Car/SettingsView.swift`; Modify `ios/ESP32Car/DriveView.swift`.

- [ ] **Step 1: Создать `ios/ESP32Car/SettingsView.swift`**
```swift
import SwiftUI

struct SettingsView: View {
    let palette: Palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                palette.bg.ignoresSafeArea()
                List {
                    NavigationLink {
                        CalibrationStub(palette: palette)
                    } label: {
                        Label("Калибровка", systemImage: "gearshape.2")
                            .foregroundStyle(palette.text)
                    }
                    .listRowBackground(palette.panel)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .tint(palette.accent)
    }
}

private struct CalibrationStub: View {
    let palette: Palette
    var body: some View {
        ZStack {
            palette.bg.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "gearshape.2").font(.largeTitle).foregroundStyle(palette.muted)
                Text("Калибровка — в разработке").foregroundStyle(palette.text)
            }
        }
        .navigationTitle("Калибровка")
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

- [ ] **Step 2: Кнопка `⚙` в топ-баре `DriveView.swift`**
Find the top-bar HStack:
```swift
                HStack {
                    HStack(spacing: 7) {
                        Circle().fill(status.online ? p.accent : Color.orange).frame(width: 8, height: 8)
                        Text(status.online ? "connected · \(status.pingMs ?? 0) ms" : "searching…")
                            .font(.system(size: 12)).foregroundStyle(p.muted)
                    }
                    Spacer()
                    SchemeToggle(scheme: $schemeRaw, palette: p)
                }
```
Add the gear button right after `SchemeToggle(...)` (inside the same HStack, before its closing brace):
```swift
                    SchemeToggle(scheme: $schemeRaw, palette: p)
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 15))
                            .foregroundStyle(p.muted)
                            .frame(width: 34, height: 28)
                            .background(p.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(p.line))
                    }
                    .padding(.leading, 8)
```

- [ ] **Step 3: `@State` + `.sheet` в `DriveView.swift`**
Add the state near the other `@State` declarations (e.g. after `@State private var curY = 0.0`):
```swift
    @State private var showSettings = false
```
Add the sheet modifier on the root `ZStack` — find the trailing modifiers:
```swift
        .onAppear { conn.start(); status.start() }
        .onReceive(pad.$leftX) { _ in push() }
        .onReceive(pad.$leftY) { _ in push() }
        .onReceive(pad.$rightY) { _ in push() }
        .onReceive(pad.$connected) { _ in push() }
```
and append after the last one:
```swift
        .sheet(isPresented: $showSettings) { SettingsView(palette: p) }
```

- [ ] **Step 4: Regenerate + compile-check**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -8
```
Expected: `** BUILD SUCCEEDED **`. Fix any Swift errors and rebuild.

- [ ] **Step 5: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/SettingsView.swift ios/ESP32Car/DriveView.swift
git commit -m "feat(ios): settings gear button + sheet with calibration placeholder"
```

---

## Task 2: Проверка в симуляторе

**Files:** (проверка — без изменений кода)

- [ ] **Step 1: Сборка + запуск (мок уже не нужен для настроек, но пусть работает)**
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
- кнопка `⚙` видна в топ-баре справа от Arcade/Tank;
- тап → открывается лист «Настройки» со строкой «Калибровка»;
- тап «Калибровка» → экран «Калибровка — в разработке»;
- «Закрыть» закрывает лист;
- переключить тему симулятора → лист в обеих темах читаем.
Скриншот: `xcrun simctl io booted screenshot /tmp/settings.png`.

---

## Self-Review заметки

- **Покрытие спеки:** кнопка `⚙` справа от `SchemeToggle` (Task 1 Step 2); `SettingsView` sheet + строка «Калибровка» → стаб (Step 1); «Закрыть» (toolbar confirmationAction); темы (`palette`/colorScheme). Проверка (Task 2).
- **Тип-консистентность:** `SettingsView(palette:)`, `CalibrationStub(palette:)`, `showSettings` (Bool), `p: Palette` (есть в DriveView). SF Symbols `gearshape`/`gearshape.2`.
- **Тесты:** чистой логики нет — верификация визуальная в симуляторе (Task 2).
- **Замечания:** sheet получает `palette: p` (снимок текущей темы); смена системной темы при открытом листе — крайний случай, не критично. Прошивка/мок не трогаются.
