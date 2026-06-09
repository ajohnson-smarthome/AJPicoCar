# Экран обновления — полировка (тексты/иконки/анимации) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Единый лаконичный шаблон текста на всех 9 состояниях экрана обновления, иконки в чипе, анимация волн строго по процессу (ожидание → пульс), реальный прогресс скачивания, версии с `v`, без «Закрыть».

**Architecture:** `FirmwareCarView` рисует волны по режиму (none/deco/wait/active/ping) + чип-иконку; `FirmwareView` — шаблон Заголовок/Подзаголовок/действие с новыми строками; `UpdateClient` отдаёт `downloadProgress`.

**Tech Stack:** Swift 6 / SwiftUI, URLSessionDownloadDelegate. Ветка `fw-polish`. SDK `iphonesimulator26.2`, устройство `iPhone 17`, мок `127.0.0.1:8080`.

---

## File Structure

| Файл | Изменение |
|---|---|
| `ios/ESP32Car/UpdateClient.swift` | `downloadProgress` + `URLSessionDownloadDelegate` |
| `ios/ESP32Car/Resources/ru.lproj/Localizable.strings` | финальный набор `fw.*` |
| `ios/ESP32Car/L.swift` | финальные аксессоры `fw.*` |
| `ios/ESP32Car/FirmwareCarView.swift` | волны по режиму + анимации |
| `ios/ESP32Car/FirmwareView.swift` | шаблон + новые тексты + downloadProgress |

---

## Task 1: Прогресс скачивания в `UpdateClient`

**Files:** Modify `ios/ESP32Car/UpdateClient.swift`.

- [ ] **Step 1: Добавить `@Published var downloadProgress`** — рядом с `uploadProgress`:
```swift
    @Published var downloadProgress: Double = 0
```

- [ ] **Step 2: Заменить `download(_:)` на делегатную версию**
```swift
    func download(_ url: URL) async -> URL? {
        downloadProgress = 0
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (tmp, _) = try await session.download(from: url)
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("firmware.bin")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            return dest
        } catch { return nil }
    }
```

- [ ] **Step 3: Расширить extension до `URLSessionDownloadDelegate`** — change the extension declaration `extension UpdateClient: URLSessionTaskDelegate {` to:
```swift
extension UpdateClient: URLSessionTaskDelegate, URLSessionDownloadDelegate {
```
and add inside it (alongside the existing `didSendBodyData`):
```swift
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        let p = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        Task { @MainActor in self.downloadProgress = p }
    }
    // Required by URLSessionDownloadDelegate; async download(from:) consumes the file itself.
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) { }
```

- [ ] **Step 4: Regenerate + compile-check**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -6
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/UpdateClient.swift && git commit -m "feat(ios): download progress in UpdateClient"
```

---

## Task 2: Строки + `L` (финальный набор)

**Files:** Modify `ios/ESP32Car/Resources/ru.lproj/Localizable.strings`, `ios/ESP32Car/L.swift`.

- [ ] **Step 1: Заменить все `fw.*` строки** в `Localizable.strings` на финальный набор (удалить старые `fw.*`, кроме `settings.firmware`):
```
"settings.firmware" = "Прошивка";
"fw.checking"       = "Проверка обновлений…";
"fw.current"        = "Текущая %@";
"fw.upToDate"       = "Актуальная версия";
"fw.versionLine"    = "Версия %@";
"fw.recheck"        = "Проверить снова";
"fw.available"      = "Доступно обновление";
"fw.transition"     = "%@ → %@";
"fw.update"         = "Обновить";
"fw.downloadTitle"  = "Скачивание";
"fw.connectTitle"   = "Подключись к машинке";
"fw.connectSub"     = "Wi-Fi «ESP32-Car»";
"fw.flash"          = "Залить";
"fw.uploadTitle"    = "Заливка";
"fw.rebootTitle"    = "Перезагрузка…";
"fw.rebootWait"     = "Машинка скоро вернётся";
"fw.doneTitle"      = "Готово";
"fw.doneSub"        = "Обновлено до %@";
"fw.failTitle"      = "Не удалось";
"fw.failSub"        = "Проверь связь и повтори";
"fw.retry"          = "Повторить";
```

- [ ] **Step 2: Заменить все `fw*` аксессоры** в `L.swift` (между `settingsFirmware` и `fwCurrent`-блоком) на финальный набор. Remove every `fw*` accessor except `settingsFirmware`, and add:
```swift
    static var fwChecking: String { s("fw.checking") }
    static var fwUpToDate: String { s("fw.upToDate") }
    static var fwRecheck: String { s("fw.recheck") }
    static var fwAvailable: String { s("fw.available") }
    static var fwUpdate: String { s("fw.update") }
    static var fwDownloadTitle: String { s("fw.downloadTitle") }
    static var fwConnectTitle: String { s("fw.connectTitle") }
    static var fwConnectSub: String { s("fw.connectSub") }
    static var fwFlash: String { s("fw.flash") }
    static var fwUploadTitle: String { s("fw.uploadTitle") }
    static var fwRebootTitle: String { s("fw.rebootTitle") }
    static var fwRebootWait: String { s("fw.rebootWait") }
    static var fwDoneTitle: String { s("fw.doneTitle") }
    static var fwFailTitle: String { s("fw.failTitle") }
    static var fwFailSub: String { s("fw.failSub") }
    static var fwRetry: String { s("fw.retry") }
    static func fwCurrent(_ v: String) -> String { s("fw.current", v) }
    static func fwVersionLine(_ v: String) -> String { s("fw.versionLine", v) }
    static func fwTransition(_ a: String, _ b: String) -> String { s("fw.transition", a, b) }
    static func fwDoneSub(_ v: String) -> String { s("fw.doneSub", v) }
```

- [ ] **Step 3: Build** (FirmwareView still references old API — may fail here; the definitive build is Task 4. To gate cleanly, run after Task 4.)
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate >/dev/null && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -6 || true
```

- [ ] **Step 4: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/Resources ios/ESP32Car/L.swift && git commit -m "feat(ios): final firmware-screen strings (laconic, versioned, with v)"
```

---

## Task 3: `FirmwareCarView` — волны по процессу

**Files:** Modify `ios/ESP32Car/FirmwareCarView.swift` (rewrite body + helpers; keep `enum FwPhase`).

- [ ] **Step 1: Заменить содержимое `FirmwareCarView` (оставив `enum FwPhase` сверху файла) на:**
```swift
struct FirmwareCarView: View {
    let phase: FwPhase
    let palette: Palette
    @State private var pulse = false

    private enum WaveMode { case none, deco, wait, active, ping }
    private var mode: WaveMode {
        switch phase {
        case .checking, .downloading, .downloaded: return .wait
        case .uploading: return .active
        case .rebooting: return .ping
        case .upToDate: return .deco
        case .available, .done, .failed: return .none
        }
    }
    private var chipIcon: String {
        switch phase {
        case .upToDate, .done: return "checkmark"
        case .failed: return "exclamationmark"
        default: return "cpu"
        }
    }
    private var chipColor: Color { phase == .failed ? palette.warn : palette.accent }
    private var animating: Bool { mode == .wait || mode == .active }

    var body: some View {
        ZStack {
            waves
            RoundedRectangle(cornerRadius: 13).fill(palette.panel)
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(palette.line))
                .frame(width: 64, height: 98)
            RoundedRectangle(cornerRadius: 4).fill(palette.bg.opacity(0.7))
                .frame(width: 34, height: 12).offset(y: -31)
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 5).fill(palette.idleWheel)
                    .frame(width: 22, height: 32)
                    .offset(x: i % 2 == 0 ? -33 : 33, y: i < 2 ? -36 : 36)
            }
            Image(systemName: chipIcon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.bg)
                .frame(width: 26, height: 26)
                .background(chipColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: chipColor.opacity(0.7), radius: phase == .done ? 11 : 5)
        }
        .scaleEffect(1.75)
        .frame(width: 190, height: 240)
        .opacity(phase == .rebooting ? 0.6 : 1)
        .onAppear { pulse = true }
    }

    @ViewBuilder private var waves: some View {
        switch mode {
        case .none:
            EmptyView()
        case .ping:
            ForEach(0..<2, id: \.self) { i in
                Circle().stroke(palette.accent, lineWidth: 2)
                    .frame(width: 60, height: 60)
                    .scaleEffect(pulse ? 1.7 : 0.4)
                    .opacity(pulse ? 0 : 0.7)
                    .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false).delay(Double(i) * 0.9), value: pulse)
            }
        default:
            ForEach(0..<3, id: \.self) { i in
                Circle().stroke(palette.accent, lineWidth: 2)
                    .frame(width: CGFloat(64 + i * 28), height: CGFloat(64 + i * 28))
                    .opacity(ringOpacity(i))
                    .scaleEffect(animating && pulse ? 1.10 : 1.0)
                    .animation(animating ? .easeInOut(duration: mode == .active ? 1.05 : 1.3).repeatForever(autoreverses: true) : .default, value: pulse)
            }
        }
    }

    private func ringOpacity(_ i: Int) -> Double {
        switch mode {
        case .active: return [0.62, 0.38, 0.20][i]
        case .wait: return [0.42, 0.24, 0.11][i]
        case .deco: return [0.20, 0.11, 0.045][i]
        default: return 0
        }
    }
}
```

- [ ] **Step 2: Build** (как Task 2 Step 3 — может падать в FirmwareView до Task 4).
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error: .*FirmwareCarView|BUILD SUCCEEDED|BUILD FAILED" | head -4 || true
```
Expected: no errors originating in `FirmwareCarView.swift` (errors only in FirmwareView.swift are OK until Task 4).

- [ ] **Step 3: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/FirmwareCarView.swift && git commit -m "feat(ios): process-driven car waves (pulse/ping/deco/none) by phase"
```

---

## Task 4: `FirmwareView` — единый шаблон + тексты

**Files:** Modify `ios/ESP32Car/FirmwareView.swift` (rewrite `stateBlock`).

- [ ] **Step 1: Заменить `stateBlock` на единый шаблон** (внутри `struct FirmwareView`; `body`, `check/download/flash` — без изменений, кроме того что `.done` больше не имеет кнопки):
```swift
    @ViewBuilder private var stateBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            switch phase {
            case .checking:
                title(L.fwChecking); sub(L.fwCurrent(current))
            case .upToDate:
                title(L.fwUpToDate); sub(L.fwVersionLine(current))
                Button { Task { await check() } } label: { Text(L.fwRecheck) }
                    .buttonStyle(.bordered).tint(p.muted).padding(.top, 2)
            case .available:
                title(L.fwAvailable); sub(L.fwTransition(current, release?.tag ?? "—"))
                Button { Task { await download() } } label: { Text(L.fwUpdate) }
                    .buttonStyle(.borderedProminent).tint(p.accent).padding(.top, 2)
            case .downloading:
                title(L.fwDownloadTitle)
                sub("\(L.fwTransition(current, release?.tag ?? "")) · \(Int(client.downloadProgress * 100))%")
                ProgressView(value: client.downloadProgress).tint(p.accent).frame(width: 150)
            case .downloaded:
                title(L.fwConnectTitle); sub(L.fwConnectSub)
                Button { Task { await flash() } } label: { Text(L.fwFlash) }
                    .buttonStyle(.borderedProminent).tint(p.accent).disabled(!status.online).padding(.top, 2)
            case .uploading:
                title(L.fwUploadTitle)
                sub("\(release?.tag ?? "") · \(Int(client.uploadProgress * 100))%")
                ProgressView(value: client.uploadProgress).tint(p.accent).frame(width: 150)
            case .rebooting:
                title(L.fwRebootTitle); sub(L.fwRebootWait)
            case .done:
                title(L.fwDoneTitle); sub(L.fwDoneSub(current))
            case .failed:
                title(L.fwFailTitle); sub(L.fwFailSub)
                Button { Task { await check() } } label: { Text(L.fwRetry) }
                    .buttonStyle(.borderedProminent).tint(p.accent).padding(.top, 2)
            }
        }
    }
    private func title(_ t: String) -> some View {
        Text(t).font(.system(size: 16, weight: .semibold)).foregroundStyle(p.text)
    }
    private func sub(_ t: String) -> some View {
        Text(t).font(.system(size: 12)).foregroundStyle(p.muted)
    }
```

- [ ] **Step 2: Убедиться, что `flash()` ставит `.done` без кнопки** — `flash()` уже завершается `phase = .done`; ничего менять не нужно. Удалить неиспользуемый `@Environment(\.dismiss)` если на него ругается компилятор (оставить, если используется системной навигацией — он безвреден).

- [ ] **Step 3: Regenerate + полный build**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -8
echo "=== остатки старых строк? ===" && grep -rnE "fwLatest|fwDownloadingGh|fwUploadingTag|fwDownloaded|fwConnectCar|fwVersion\b|fwRebooting|fwDone\b|fwFailed\b|driveCalib" ESP32Car || echo "(нет)"
```
Expected: `** BUILD SUCCEEDED **`, grep `(нет)`.

- [ ] **Step 4: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/FirmwareView.swift && git commit -m "feat(ios): unified firmware state template (title/sub/action), download %, no Close"
```

---

## Task 5: Проверка в симуляторе (форс-харнесс)

**Files:** (временные правки, откатываются)

- [ ] **Step 1: Временный харнесс** — в `ESP32CarApp.swift` заменить корневой `ZStack {...}` на `NavigationStack { FirmwareView(palette: Theme.dark, status: status) }`; в `FirmwareView` временно `phase = .available` + `.task { release = UpdateClient.Release(tag: "v1.1", assetURL: URL(string: "https://example.com/fw.bin")!) }`.
- [ ] **Step 2: Скриншоты ключевых фаз** — поочерёдно ставя `phase` в `.available / .downloading / .uploading / .rebooting / .done / .failed`, билдить для `iPhone 17`, `xcrun simctl launch` + `xcrun simctl io booted screenshot /tmp/fwp_<phase>.png`. Проверить: available/done/failed — без колец; upToDate — статичны; waiting — пульс/пинг; версии с `v`; тексты по шаблону.
- [ ] **Step 3: Откатить харнесс** — вернуть `ESP32CarApp.swift` и `FirmwareView` (`phase = .checking`, `.task { await check() }`); `grep -rn "TEMP\|example.com/fw.bin" ios/ESP32Car` → `(нет)`; финальный build SUCCEEDED.
- [ ] **Step 4: Commit** (если харнесс затронул файлы — убедиться, что откат без изменений; иначе пропустить).

---

## Self-Review заметки

- **Покрытие спеки:** download progress (Task 1); финальные строки с `v`/лаконичные (Task 2); волны по процессу none/deco/wait/active/ping + чип-иконки (Task 3); единый шаблон Заголовок/Подзаголовок/действие, downloading/% , без «Закрыть» (Task 4); проверка (Task 5).
- **Тип-консистентность:** `UpdateClient.downloadProgress`/`uploadProgress`/`Release(tag,assetURL)`/`normalize`; `FwPhase` (в FirmwareCarView); `FirmwareCarView(phase:palette:)`; `L.fw*` (полный финальный набор, функции `fwCurrent/fwVersionLine/fwTransition/fwDoneSub`); `status.fw`/`status.online`; `p.text/muted/accent/warn`.
- **Тесты:** чистой логики нет; проверка — сборка + скриншоты (Task 5).
- **Замечания:** `URLSessionDownloadDelegate` требует `didFinishDownloadingTo` (пустой — async API сам берёт файл). Версии показываем сырые (`vX.Y` на устройстве, `mock` на моке). `.done` без кнопки — закрытие системной «назад».
```
