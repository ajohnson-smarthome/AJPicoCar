# Галерея экранов (debug-only) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Debug-only галерея: листать все экраны приложения во всех состояниях тапом (лево/право), с подставным состоянием; включается launch-аргументом `-gallery`.

**Architecture:** Маленькие preview-хуки в экранах со стейт-машиной (FirmwareView `debugPhase`, CalibrationView `debugState`, DriveView `preview`), все с дефолтами (прод не меняется). `GalleryView` (#if DEBUG) — массив кадров `(label, AnyView)` + tap-зоны + счётчик; mock-хелперы строят `CarStatus`/`CarConnection`. `ESP32CarApp` в `#if DEBUG` при аргументе `-gallery` показывает галерею.

**Tech Stack:** Swift 6 / SwiftUI. Ветка `gallery`. SDK `iphonesimulator26.2`, `iPhone 17`. Визуальный инструмент — тестов логики нет, проверка = сборка + симулятор.

---

## File Structure

| Файл | Изменение |
|---|---|
| `ios/ESP32Car/FirmwareView.swift` | `var debugPhase: FwPhase? = nil` + short-circuit в `.task` |
| `ios/ESP32Car/CalibrationView.swift` | `enum CalDebug` + `var debugState: CalDebug? = nil` + seed в `.onAppear` |
| `ios/ESP32Car/DriveView.swift` | `var preview: Bool = false` → пропустить сетевой `start()` в `.onAppear` |
| `ios/ESP32Car/GalleryView.swift` *(new, #if DEBUG)* | кадры + навигация + счётчик + mock-хелперы |
| `ios/ESP32Car/ESP32CarApp.swift` | `#if DEBUG` + аргумент `-gallery` → корень = `GalleryView` |

---

## Task 1: Preview-хуки в экранах со стейт-машиной

**Files:** Modify `ios/ESP32Car/FirmwareView.swift`, `ios/ESP32Car/CalibrationView.swift`, `ios/ESP32Car/DriveView.swift`.

- [ ] **Step 1: `FirmwareView.swift`** — добавить параметр (после `onDone`):
```swift
    var debugPhase: FwPhase? = nil   // gallery: render a static phase, skip the network check
```
И заменить `.task { await check() }` на:
```swift
        .task {
            if let dp = debugPhase { phase = dp; return }
            await check()
        }
```

- [ ] **Step 2: `CalibrationView.swift`** — добавить публичный enum + параметр + seed. После `let palette: Palette`:
```swift
    enum CalDebug { case spin, direction, done, saving, failed }   // gallery preview seed
    var debugState: CalDebug? = nil
```
В `body`, на корневой `ZStack` (или `.frame(...).padding(20)` обёртку) навесить `.onAppear`:
```swift
        .onAppear {
            guard let d = debugState else { return }
            switch d {
            case .spin:      step = 0; pending = nil; saving = false; failed = false
            case .direction: pending = Corner.allCases.first
            case .done:      step = 4
            case .saving:    saving = true
            case .failed:    failed = true
            }
        }
```
(Добавить `.onAppear` к существующему `body`'s ZStack — НЕ ломая остальные модификаторы; повесить после `.padding(20)`.)

- [ ] **Step 3: `DriveView.swift`** — добавить параметр + гейт сетевого старта. После `@State private var did… ` (рядом с инициализаторами `@State`):
```swift
    var preview: Bool = false   // gallery: render statically, skip network start + calibration sheet
```
Найти `.onAppear { conn.start(); status.start() }` и заменить на:
```swift
        .onAppear { if !preview { conn.start(); status.start() } }
```
(Если `preview` true — джойстики/диаграмма рисуются из локального стейта без сетевых вызовов; калибровочный шит не всплывёт, т.к. mockStatus даёт `calibrated == true`.)

- [ ] **Step 4: Build + grep**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -6
grep -rn '[А-Яа-яЁё]' --include='*.swift' ESP32Car && echo LEAK || echo "(чисто)"
```
Expected: `** BUILD SUCCEEDED **`, чисто. (Прод-поведение не меняется: все новые параметры с дефолтами nil/false.)

- [ ] **Step 5: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/FirmwareView.swift ios/ESP32Car/CalibrationView.swift ios/ESP32Car/DriveView.swift
git commit -m "feat(ios): preview hooks for the screen gallery (debugPhase/debugState/preview, prod-inert)"
```

---

## Task 2: `GalleryView` (#if DEBUG) — кадры + навигация

**Files:** Create `ios/ESP32Car/GalleryView.swift`.

- [ ] **Step 1: `ios/ESP32Car/GalleryView.swift`** — весь файл под `#if DEBUG`:
```swift
#if DEBUG
import SwiftUI

/// Debug-only screen gallery: every screen/state, tap left/right to navigate. Enabled via the
/// `-gallery` launch argument (see ESP32CarApp). Not compiled into release builds.
struct GalleryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var index = 0
    private var p: Palette { Theme.current(colorScheme) }

    var body: some View {
        let frames = makeFrames(p)
        ZStack {
            p.bg.ignoresSafeArea()
            frames[index].view
            // invisible tap zones: left = prev, right = next (wrap-around)
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { index = (index - 1 + frames.count) % frames.count }
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { index = (index + 1) % frames.count }
            }
            VStack {
                Text("\(index + 1) / \(frames.count)  ·  \(frames[index].label)")
                    .font(.system(size: 11, weight: .medium)).monospacedDigit()
                    .foregroundStyle(p.text)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(p.panel.opacity(0.9)))
                    .padding(.top, 8)
                Spacer()
            }
        }
        .statusBarHidden(true)
    }

    // MARK: - Mock state helpers
    @MainActor private func mockStatus(online: Bool = true, calibrated: Bool? = true,
                                       fw: String? = "v1.0+264", rssi: Int? = -55,
                                       wdtTrips: Int? = nil) -> CarStatus {
        let s = CarStatus()
        s.online = online; s.calibrated = calibrated; s.fw = fw
        s.rssi = rssi; s.wdtTrips = wdtTrips; s.uptimeS = 3847
        return s
    }

    // MARK: - Frame list (label + view)
    @MainActor private func makeFrames(_ p: Palette) -> [(label: String, view: AnyView)] {
        let conn = CarConnection()
        func fw(_ phase: FwPhase, forced: Bool = false) -> AnyView {
            AnyView(NavigationStack { FirmwareView(palette: p, forced: forced, status: mockStatus(), debugPhase: phase) })
        }
        func calib(_ d: CalibrationView.CalDebug) -> AnyView {
            AnyView(NavigationStack { CalibrationView(palette: p, debugState: d) })
        }
        return [
            ("Connect (radar)",        AnyView(ConnectView())),
            ("NoInternet",             AnyView(NoInternetView(palette: p) {})),
            ("UpdateCheck checking",   AnyView(UpdateCheckView(palette: p, phase: .checkUpdate, client: UpdateClient()) {})),
            ("UpdateCheck downloading",AnyView(UpdateCheckView(palette: p, phase: .downloading, client: { let c = UpdateClient(); c.downloadProgress = 0.45; return c }()) {})),
            ("UpdateCheck failed",     AnyView(UpdateCheckView(palette: p, phase: .checkFailed, client: UpdateClient()) {})),
            ("Firmware checking",      fw(.checking)),
            ("Firmware upToDate",      fw(.upToDate)),
            ("Firmware available",     fw(.available)),
            ("Firmware downloading",   fw(.downloading)),
            ("Firmware downloaded",    fw(.downloaded)),
            ("Firmware uploading",     fw(.uploading)),
            ("Firmware rebooting",     fw(.rebooting)),
            ("Firmware done",          fw(.done)),
            ("Firmware failed",        fw(.failed)),
            ("Firmware forced",        fw(.available, forced: true)),
            ("Drive arcade",           AnyView(DriveView(conn: conn, status: mockStatus(), preview: true).onAppear { UserDefaults.standard.set("arcade", forKey: "scheme") })),
            ("Drive tank",             AnyView(DriveView(conn: conn, status: mockStatus(), preview: true).onAppear { UserDefaults.standard.set("tank", forKey: "scheme") })),
            ("Drive warning",          AnyView(DriveView(conn: conn, status: mockStatus(wdtTrips: 3), preview: true))),
            ("Settings",               AnyView(NavigationStack { SettingsView(palette: p, status: mockStatus()) })),
            ("Calibration spin",       calib(.spin)),
            ("Calibration direction",  calib(.direction)),
            ("Calibration done",       calib(.done)),
            ("Calibration saving",     calib(.saving)),
            ("Calibration failed",     calib(.failed)),
            ("Ramp",                   AnyView(NavigationStack { RampView(palette: p) })),
            ("Trim",                   AnyView(NavigationStack { TrimView(palette: p) })),
        ]
    }
}
#endif
```

- [ ] **Step 2: Build** (галерея ещё не подключена к корню, но должна компилироваться)
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -10
```
Expected: `** BUILD SUCCEEDED **`. (Debug-сборка компилирует `#if DEBUG`-код. Если сигнатуры конструкторов экранов отличаются — поправить вызовы под реальные: SettingsView(palette:status:), RampView(palette:), TrimView(palette:), ConnectView(), NoInternetView(palette:onRetry:), UpdateCheckView(palette:phase:client:onRetry:).)

- [ ] **Step 3: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/GalleryView.swift
git commit -m "feat(ios): debug-only screen gallery (all states, tap-zones, counter)"
```

---

## Task 3: Подключить галерею к корню по `-gallery`

**Files:** Modify `ios/ESP32Car/ESP32CarApp.swift`.

- [ ] **Step 1:** в `ESP32CarApp` сделать корень условным. Заменить тело `WindowGroup` так, чтобы в
  `#if DEBUG` при аргументе `-gallery` показывалась галерея:
```swift
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-gallery") {
                GalleryView()
            } else {
                appRoot
            }
            #else
            appRoot
            #endif
        }
    }

    private var appRoot: some View {
        root
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            .task { conn.onTelemetry = { status.apply($0) }; await flow.startupCheck() }
            .onChange(of: phase) { newPhase in
                if newPhase == .active { conn.resume(); status.start() }
                else { conn.pause(); status.stop() }
            }
    }
```
(Вынести существующую цепочку модификаторов в `appRoot`; `root` (switch по `flow.phase`) и `tryCarConnected()` оставить как есть.)

- [ ] **Step 2: Build**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -8
grep -rn '[А-Яа-яЁё]' --include='*.swift' ESP32Car && echo LEAK || echo "(чисто)"
```
Expected: SUCCEEDED, чисто.

- [ ] **Step 3: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/ESP32CarApp.swift
git commit -m "feat(ios): launch with -gallery (DEBUG) shows the screen gallery instead of the app flow"
```

---

## Task 4: Проверка в симуляторе

- [ ] **Step 1: запустить с `-gallery`**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios
xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | grep -iE "BUILD SUCCEEDED|FAILED" | head -1
xcrun simctl boot "iPhone 17" 2>/dev/null; sleep 3
APP="$(find /tmp/ddata/Build/Products -name ESP32Car.app | head -1)"
xcrun simctl install booted "$APP"
xcrun simctl terminate booted com.adamjohnson.esp32car 2>/dev/null
xcrun simctl launch booted com.adamjohnson.esp32car --args -gallery >/dev/null && sleep 3
xcrun simctl io booted screenshot /tmp/gallery_1.png 2>&1 | tail -1
```
Expected: первый кадр (Connect radar) + счётчик «1 / 26 · Connect (radar)».

- [ ] **Step 2: навигация** — тап по правой половине (через `simctl io ... tap`? нет — используем тап через
  `xcrun simctl` недоступен напрямую; вместо этого проверка перелистывания вручную скриншотами после
  программной симуляции тапа невозможна без UI-теста). Прагматично: проверить, что кадры строятся,
  скриншотами разных `index` через временный харнесс (`@State private var index = 5`) ИЛИ просто
  подтвердить первый кадр + сборку. Минимально: скриншот первого кадра подтверждает галерея-корень
  активна. (Тап-навигация — ручная проверка пользователем; для авто-скрипта достаточно первого кадра.)
- [ ] **Step 3: запуск БЕЗ `-gallery`** → обычный флоу (drive), галерея не активна. Скриншот `/tmp/gallery_off.png`.
- [ ] **Step 4:** дерево чистое; продакшн-запуск без аргумента работает как раньше.

---

## Self-Review заметки

- **Покрытие спеки:** доступ debug + `-gallery` (Task 3); ~26 кадров всех состояний (Task 2 makeFrames:
  Connect/NoInternet/UpdateCheck×3/Firmware×9+forced/Drive×3/Settings/Calibration×5/Ramp/Trim); навигация
  лево/право + зацикливание + счётчик (Task 2 GalleryView); mock-состояние (mockStatus, debugPhase/
  debugState/preview, Task 1–2); прод не меняется (дефолты, Task 1). Тесты = сборка+симулятор (Task 4).
- **Тип-консистентность:** `FirmwareView(...debugPhase:)`, `CalibrationView(...debugState:)` +
  `CalibrationView.CalDebug`, `DriveView(...preview:)`; `GalleryView()`; `mockStatus(online:calibrated:fw:rssi:wdtTrips:)`.
  Конструкторы экранов вызываются по их реальным сигнатурам (реализатор сверяет: SettingsView(palette:status:),
  RampView(palette:), TrimView(palette:), NoInternetView(palette:onRetry:), UpdateCheckView(palette:phase:client:onRetry:)).
- **Замечания:** debugPhase/debugState/preview сделаны обычными параметрами с дефолтами (не `#if DEBUG`-
  обёрнуты) — проще и надёжнее, прод-поведение идентично (дефолты nil/false). GalleryView целиком под
  `#if DEBUG`. Подписи счётчика — ASCII (debug-текст, не через `L`, кириллица-греп проходит). Drive-кадры
  используют `preview: true` → нет сетевого старта, `online` не гаснет по свежести. Тап-навигация в авто-
  проверке не симулируется (нет UI-теста) — подтверждается первый кадр + ручная проверка пользователем.