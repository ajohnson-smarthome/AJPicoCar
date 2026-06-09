# Экран обновления — редизайн в формат калибровки — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Переписать `FirmwareView` в формат экрана калибровки (split-layout, центрирование): слева — машинка с чипом и волнами OTA (phase-driven), справа — блок всех 9 состояний обновления.

**Architecture:** Новый `FirmwareCarView` (левая картинка, реагирует на `FwPhase`) + `FirmwareView` с расширенной машиной состояний (`checking → upToDate|available → downloading → downloaded → uploading → rebooting → done`, `failed` на любом шаге). `UpdateClient` без изменений.

**Tech Stack:** Swift 6 / SwiftUI. Ветка `fw-screen`. Симулятор-SDK `iphonesimulator26.2`, устройство `iPhone 17`, мок `127.0.0.1:8080`.

---

## File Structure

| Файл | Изменение |
|---|---|
| `ios/ESP32Car/Resources/ru.lproj/Localizable.strings` | +9 ключей, правка 2, удаление 3 |
| `ios/ESP32Car/L.swift` | +9 аксессоров, удаление 3 |
| `ios/ESP32Car/FirmwareCarView.swift` *(new)* | `FwPhase` enum + левая картинка |
| `ios/ESP32Car/FirmwareView.swift` | split-layout + машина состояний |

---

## Task 1: Строки + `L`

**Files:** Modify `ios/ESP32Car/Resources/ru.lproj/Localizable.strings`, `ios/ESP32Car/L.swift`.

- [ ] **Step 1: `Localizable.strings` — удалить 3 устаревших**
Delete these lines:
```
"fw.download"        = "1. Скачать (нужен интернет)";
"fw.downloading"     = "Скачиваю…";
"fw.uploading"       = "Заливаю…";
```

- [ ] **Step 2: `Localizable.strings` — поправить 2 (убрать нумерацию шагов)**
Replace:
```
"fw.connectCar"      = "2. Подключись к Wi-Fi ESP32-Car";
"fw.flash"           = "3. Залить";
```
with:
```
"fw.connectCar"      = "Подключись к Wi-Fi ESP32-Car";
"fw.flash"           = "Залить";
```

- [ ] **Step 3: `Localizable.strings` — добавить 9 новых**
```
"fw.checking"        = "Проверяю обновления…";
"fw.recheck"         = "Проверить снова";
"fw.update"          = "Обновить";
"fw.downloadingGh"   = "Скачиваю с GitHub…";
"fw.downloaded"      = "Скачано %@";
"fw.uploadingTag"    = "Заливаю %@…";
"fw.rebootWait"      = "жду возврата на связь";
"fw.version"         = "Версия: %@";
"fw.retry"           = "Повторить";
```

- [ ] **Step 4: `L.swift` — удалить 3 устаревших аксессора**
Delete:
```swift
    static var fwDownload: String { s("fw.download") }
    static var fwDownloading: String { s("fw.downloading") }
    static var fwUploading: String { s("fw.uploading") }
```

- [ ] **Step 5: `L.swift` — добавить 9 (рядом с остальными `fw*`)**
```swift
    static var fwChecking: String { s("fw.checking") }
    static var fwRecheck: String { s("fw.recheck") }
    static var fwUpdate: String { s("fw.update") }
    static var fwDownloadingGh: String { s("fw.downloadingGh") }
    static var fwRebootWait: String { s("fw.rebootWait") }
    static var fwRetry: String { s("fw.retry") }
    static func fwDownloaded(_ v: String) -> String { s("fw.downloaded", v) }
    static func fwUploadingTag(_ v: String) -> String { s("fw.uploadingTag", v) }
    static func fwVersion(_ v: String) -> String { s("fw.version", v) }
```

- [ ] **Step 6: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/Resources ios/ESP32Car/L.swift
git commit -m "feat(ios): firmware-screen strings (states, recheck, version)"
```

---

## Task 2: `FirmwareCarView` (левая картинка)

**Files:** Create `ios/ESP32Car/FirmwareCarView.swift`.

- [ ] **Step 1: Создать `ios/ESP32Car/FirmwareCarView.swift`**
```swift
import SwiftUI

/// Phases of the firmware-update screen, shared by FirmwareView and its car image.
enum FwPhase { case checking, upToDate, available, downloading, downloaded, uploading, rebooting, done, failed }

/// Top-down car + center chip + OTA waves; waves brighten/animate while uploading.
struct FirmwareCarView: View {
    let phase: FwPhase
    let palette: Palette
    @State private var pulse = false

    private var wavesActive: Bool { phase == .uploading }
    private var chipIcon: String { phase == .done ? "checkmark" : (phase == .failed ? "exclamationmark" : "cpu") }
    private var chipColor: Color { phase == .failed ? palette.warn : palette.accent }

    var body: some View {
        ZStack {
            // OTA waves (concentric)
            ForEach(0..<3, id: \.self) { i in
                Circle().stroke(palette.accent, lineWidth: 2)
                    .frame(width: CGFloat(64 + i * 28), height: CGFloat(64 + i * 28))
                    .opacity(waveOpacity(i))
                    .scaleEffect(wavesActive && pulse ? 1.16 : 1.0)
                    .animation(wavesActive ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true) : .default,
                               value: pulse)
            }
            // body + windshield
            RoundedRectangle(cornerRadius: 13).fill(palette.panel)
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(palette.line))
                .frame(width: 64, height: 98)
            RoundedRectangle(cornerRadius: 4).fill(palette.bg.opacity(0.7))
                .frame(width: 34, height: 12).offset(y: -31)
            // 4 neutral wheels
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 5).fill(palette.idleWheel)
                    .frame(width: 22, height: 32)
                    .offset(x: i % 2 == 0 ? -33 : 33, y: i < 2 ? -36 : 36)
            }
            // center chip (cpu / done / failed)
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
        .opacity(phase == .rebooting ? 0.5 : 1)
        .onAppear { pulse = true }
    }

    private func waveOpacity(_ i: Int) -> Double {
        (wavesActive ? [0.60, 0.36, 0.18] : [0.22, 0.12, 0.05])[i]
    }
}
```

- [ ] **Step 2: Regenerate + compile-check**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -8
```
Expected: `** BUILD SUCCEEDED **`. (`FirmwareView` still references the old API — if the build breaks only inside `FirmwareView.swift`, that's expected; it's rewritten in Task 3. To compile Task 2 alone, this build may fail in FirmwareView — that's acceptable here; the definitive build is at the end of Task 3. If you prefer a clean gate, do Step 2 after Task 3.)

- [ ] **Step 3: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/FirmwareCarView.swift
git commit -m "feat(ios): FirmwareCarView — top-down car + chip + OTA waves (phase-driven)"
```

---

## Task 3: `FirmwareView` рерайт (split-layout + состояния)

**Files:** Modify `ios/ESP32Car/FirmwareView.swift` (full rewrite of the body + state machine).

- [ ] **Step 1: Заменить весь `ios/ESP32Car/FirmwareView.swift` на**
```swift
import SwiftUI

struct FirmwareView: View {
    let palette: Palette
    @ObservedObject var status: CarStatus
    @StateObject private var client = UpdateClient()
    @Environment(\.dismiss) private var dismiss

    @State private var release: UpdateClient.Release?
    @State private var binURL: URL?
    @State private var phase: FwPhase = .checking

    private var current: String { status.fw ?? "—" }
    private var p: Palette { palette }

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()
            HStack(spacing: 24) {
                FirmwareCarView(phase: phase, palette: p)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                stateBlock
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        }
        .navigationTitle(L.settingsFirmware)
        .navigationBarTitleDisplayMode(.inline)
        .tint(p.accent)
        .task { await check() }
    }

    @ViewBuilder private var stateBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            switch phase {
            case .checking:
                Text(L.fwCurrent(current)).foregroundStyle(p.text)
                ProgressView(L.fwChecking).tint(p.accent)
            case .upToDate:
                Text(L.fwCurrent(current)).foregroundStyle(p.text)
                Label(L.fwUpToDate, systemImage: "checkmark.seal").foregroundStyle(p.accent)
                Button { Task { await check() } } label: { Label(L.fwRecheck, systemImage: "arrow.clockwise") }
                    .buttonStyle(.bordered).tint(p.muted)
            case .available:
                Text(L.fwCurrent(current)).foregroundStyle(p.text)
                Text(L.fwLatest(release?.tag ?? "—")).foregroundStyle(p.accent)
                Button { Task { await download() } } label: { Label(L.fwUpdate, systemImage: "arrow.down.circle") }
                    .buttonStyle(.borderedProminent).tint(p.accent)
            case .downloading:
                Text("\(current) → \(release?.tag ?? "")").font(.subheadline).foregroundStyle(p.muted)
                Text(L.fwDownloadingGh).font(.caption).foregroundStyle(p.muted)
                ProgressView().tint(p.accent)
            case .downloaded:
                Label(L.fwDownloaded(release?.tag ?? ""), systemImage: "checkmark.circle").foregroundStyle(p.accent)
                Text(L.fwConnectCar).font(.caption).foregroundStyle(p.warn)
                Button { Task { await flash() } } label: { Label(L.fwFlash, systemImage: "bolt.fill") }
                    .buttonStyle(.borderedProminent).tint(p.accent)
                    .disabled(!status.online)
            case .uploading:
                Text(L.fwUploadingTag(release?.tag ?? "")).font(.subheadline).foregroundStyle(p.muted)
                ProgressView(value: client.uploadProgress).tint(p.accent).frame(width: 160)
                Text("\(Int(client.uploadProgress * 100))%").font(.caption).foregroundStyle(p.muted)
            case .rebooting:
                ProgressView(L.fwRebooting).tint(p.accent)
                Text(L.fwRebootWait).font(.caption).foregroundStyle(p.muted)
            case .done:
                Label(L.fwDone, systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(p.accent)
                Text(L.fwVersion(current)).foregroundStyle(p.text)
                Button { dismiss() } label: { Text(L.close) }
                    .buttonStyle(.bordered).tint(p.muted)
            case .failed:
                Label(L.fwFailed, systemImage: "xmark.circle").font(.headline).foregroundStyle(p.warn)
                Button { Task { await check() } } label: { Label(L.fwRetry, systemImage: "arrow.clockwise") }
                    .buttonStyle(.borderedProminent).tint(p.accent)
            }
        }
    }

    private func check() async {
        phase = .checking
        let r = await client.latestRelease()
        release = r
        guard let r else { phase = .failed; return }
        phase = (UpdateClient.normalize(r.tag) != UpdateClient.normalize(status.fw)) ? .available : .upToDate
    }
    private func download() async {
        guard let r = release else { return }
        phase = .downloading
        if let url = await client.download(r.assetURL) { binURL = url; phase = .downloaded }
        else { phase = .failed }
    }
    private func flash() async {
        guard let url = binURL else { return }
        phase = .uploading
        guard await client.upload(url) else { phase = .failed; return }
        phase = .rebooting
        var sawOffline = false
        let deadline = Date.now.addingTimeInterval(25)
        while Date.now < deadline {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if !status.online { sawOffline = true }
            else if sawOffline { phase = .done; return }
        }
        phase = .failed
    }
}
```

- [ ] **Step 2: Regenerate + compile-check**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -8
```
Expected: `** BUILD SUCCEEDED **`. Fix any Swift errors (e.g. ProgressView label forms) and rebuild.

- [ ] **Step 3: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/FirmwareView.swift
git commit -m "feat(ios): firmware screen — calib split-layout + 9-state machine + recheck"
```

---

## Task 4: Проверка в симуляторе

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

- [ ] **Step 2: Визуально (⚙ → Прошивка)**
- Раскладка как в калибровке: машинка слева (центр), блок справа (верт. центр, текст слева).
- Без GitHub-релиза экран покажет `✗ Не удалось` (latestRelease=nil) + «Повторить» — это ожидаемо, пока релиза нет;
  с релизом — `checking → available/upToDate`.
- Скриншот: `xcrun simctl io booted screenshot /tmp/fw.png`. Обе темы.
> Полный путь download→flash проверяется реальным GitHub-релизом + моком `/ota` (как в OTA-плане, Task 7).

---

## Self-Review заметки

- **Покрытие спеки:** split-layout вариант C (Task 3 Step 1 — `maxWidth/maxHeight:.infinity` + `.leading`); `FirmwareCarView` car+chip+waves, faint/active/dim/done/failed (Task 2); 9 состояний с контентом и кнопками (Task 3 `stateBlock`); явная «Проверить»/«Проверить снова» + «upToDate» (`check()`, `.upToDate`); переходы (`check/download/flash`); строки (Task 1).
- **Тип-консистентность:** `FwPhase` (в FirmwareCarView.swift, используется в FirmwareView); `FirmwareCarView(phase:palette:)`; `UpdateClient.Release.tag/assetURL`, `normalize`, `latestRelease/download/upload`, `uploadProgress`; `L.fw*`/`fwDownloaded/fwUploadingTag/fwVersion/close`; `status.fw`/`status.online`.
- **Тесты:** чистой логики нет (вью); проверка — сборка + визуал (Task 4); полный OTA-путь — на устройстве/моке.
- **Замечания:** при отсутствии релиза `latestRelease`=nil → `.failed` (приемлемо до первого релиза; «Повторить» доступна). Анимация волн — breathing через `pulse` + `repeatForever(autoreverses:true)`; подгоним на скриншоте. Старый фикс «подтверждение возврата опросом `status.online`» сохранён в `flash()`.
```
