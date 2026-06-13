# Обязательный гейт обновления при запуске — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** При запуске апп проверяет интернет → тянет/кэширует свежую прошивку → подключается к машинке → если на ней старая версия, форсит обновление из кэша → только потом пускает управлять.

**Architecture:** Чистые `UpdateClient.needsDownload`/`mustUpdate` (host-тест) + инфра (reachability, кэш `.bin`). Координатор `AppFlow` (enum фаз) заменяет корневой ZStack в `ESP32CarApp`. Новые экраны `NoInternetView`/`UpdateCheckView`; `FirmwareView` получает forced-режим; `ConnectView`/`DriveView` переиспользуются.

**Tech Stack:** Swift 6 / SwiftUI, swiftc host-тест, мок. Ветка `update-gate`. SDK `iphonesimulator26.2`, `iPhone 17`.

---

## File Structure

| Файл | Изменение |
|---|---|
| `ios/ESP32Car/UpdateClient.swift` | `needsDownload`/`mustUpdate` (pure) + `internetReachable()` + кэш (cachedBinURL/Build/Tag, recordCache); `download` → в кэш |
| `ios/ESP32Car/AppFlow.swift` *(new)* | координатор фаз запуска |
| `ios/ESP32Car/NoInternetView.swift` *(new)* | экран «Нет интернета» (Wi-Fi-glyph) |
| `ios/ESP32Car/UpdateCheckView.swift` *(new)* | экран проверки/скачивания/ошибки (переиспользует FirmwareCarView) |
| `ios/ESP32Car/FirmwareView.swift` | `forced: Bool` + `onDone` |
| `ios/ESP32Car/ESP32CarApp.swift` | корень = switch по `flow.phase` |
| `ios/ESP32Car/L.swift` + `ru.lproj` | строки гейта |
| `ios/ESP32CarTests/ControlModelTests.swift` | тесты needsDownload/mustUpdate |
| `tools/mock_car/mock_car.py` | (без изменений — fw уже версионный) |

---

## Task 1: Чистая логика гейта (TDD)

**Files:** Modify `ios/ESP32Car/UpdateClient.swift`, `ios/ESP32CarTests/ControlModelTests.swift`.

- [ ] **Step 1: добавить в `UpdateClient`** (после `buildNumber`/`isUpdateAvailable`):
```swift
    /// Need to (re)download the .bin: only when there IS a versioned latest release, and the
    /// cached file is missing or its build differs from the latest.
    static func needsDownload(latestBuild: Int?, cachedBuild: Int?, hasCachedFile: Bool) -> Bool {
        guard let latestBuild else { return false }   // no versioned release → nothing to fetch
        return !hasCachedFile || cachedBuild != latestBuild
    }

    /// Forced update required iff the latest release carries a build number AND either the running
    /// firmware predates versioning (no build number) or its build is lower.
    static func mustUpdate(carFw: String?, latestTag: String?) -> Bool {
        guard let latest = buildNumber(latestTag) else { return false }  // no versioned release → gate inert
        guard let car = buildNumber(carFw) else { return true }          // pre-versioning firmware → must update
        return latest > car
    }
```

- [ ] **Step 2 (native): `/tmp/gate.swift`**
```swift
import Foundation
func buildNumber(_ v: String?) -> Int? {
    guard let v, let p = v.firstIndex(of: "+") else { return nil }
    let d = v[v.index(after: p)...].prefix { $0.isNumber }; return d.isEmpty ? nil : Int(d)
}
func needsDownload(latestBuild: Int?, cachedBuild: Int?, hasCachedFile: Bool) -> Bool {
    guard let latestBuild else { return false }
    return !hasCachedFile || cachedBuild != latestBuild
}
func mustUpdate(carFw: String?, latestTag: String?) -> Bool {
    guard let latest = buildNumber(latestTag) else { return false }
    guard let car = buildNumber(carFw) else { return true }
    return latest > car
}
// needsDownload
precondition(needsDownload(latestBuild: nil, cachedBuild: nil, hasCachedFile: false) == false)  // legacy
precondition(needsDownload(latestBuild: 254, cachedBuild: nil, hasCachedFile: false) == true)    // nothing cached
precondition(needsDownload(latestBuild: 254, cachedBuild: 254, hasCachedFile: true) == false)    // up to date cache
precondition(needsDownload(latestBuild: 260, cachedBuild: 254, hasCachedFile: true) == true)     // newer release
precondition(needsDownload(latestBuild: 254, cachedBuild: 254, hasCachedFile: false) == true)    // file gone
// mustUpdate
precondition(mustUpdate(carFw: "v1.0+250", latestTag: "v1.0") == false)        // latest has no build → inert
precondition(mustUpdate(carFw: "v0.9", latestTag: "v1.0+254") == true)         // car pre-versioning → force
precondition(mustUpdate(carFw: "v1.0+254", latestTag: "v1.0+254") == false)    // equal
precondition(mustUpdate(carFw: "v1.0+250", latestTag: "v1.0+254") == true)     // older car
precondition(mustUpdate(carFw: "v1.0+260", latestTag: "v1.0+254") == false)    // car newer (manual flash)
print("gate logic: all passed")
```
Run: `swiftc /tmp/gate.swift -o /tmp/gate && /tmp/gate` → `gate logic: all passed`.

- [ ] **Step 3: XCTest-зеркало** — в `ControlModelTests.swift` перед закрывающей `}`:
```swift
    func testGateLogic() {
        XCTAssertFalse(UpdateClient.needsDownload(latestBuild: nil, cachedBuild: nil, hasCachedFile: false))
        XCTAssertTrue(UpdateClient.needsDownload(latestBuild: 254, cachedBuild: nil, hasCachedFile: false))
        XCTAssertFalse(UpdateClient.needsDownload(latestBuild: 254, cachedBuild: 254, hasCachedFile: true))
        XCTAssertTrue(UpdateClient.needsDownload(latestBuild: 260, cachedBuild: 254, hasCachedFile: true))
        XCTAssertTrue(UpdateClient.needsDownload(latestBuild: 254, cachedBuild: 254, hasCachedFile: false))
        XCTAssertFalse(UpdateClient.mustUpdate(carFw: "v1.0+250", latestTag: "v1.0"))
        XCTAssertTrue(UpdateClient.mustUpdate(carFw: "v0.9", latestTag: "v1.0+254"))
        XCTAssertFalse(UpdateClient.mustUpdate(carFw: "v1.0+254", latestTag: "v1.0+254"))
        XCTAssertTrue(UpdateClient.mustUpdate(carFw: "v1.0+250", latestTag: "v1.0+254"))
        XCTAssertFalse(UpdateClient.mustUpdate(carFw: "v1.0+260", latestTag: "v1.0+254"))
    }
```

- [ ] **Step 4: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/UpdateClient.swift ios/ESP32CarTests/ControlModelTests.swift
git commit -m "feat(ios): pure gate logic — needsDownload + mustUpdate (host-tested)"
```

---

## Task 2: UpdateClient — reachability + кэш

**Files:** Modify `ios/ESP32Car/UpdateClient.swift`.

- [ ] **Step 1: добавить инфраструктуру** (статики + правка `download`). После pure-функций добавить:
```swift
    // MARK: - Internet reachability + firmware cache

    /// Lightweight reachability probe to GitHub (distinguishes "no internet" from "API failed").
    static func internetReachable() async -> Bool {
        guard let url = URL(string: "https://api.github.com") else { return false }
        var req = URLRequest(url: url); req.httpMethod = "HEAD"; req.timeoutInterval = 4
        if let (_, resp) = try? await URLSession.shared.data(for: req) {
            return (resp as? HTTPURLResponse) != nil
        }
        return false
    }

    private static let kBuild = "cachedLatestBuild"
    private static let kTag   = "cachedLatestTag"

    static var cachedBinURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("firmware-latest.bin")
    }
    static var cachedBuild: Int? {
        let v = UserDefaults.standard.integer(forKey: kBuild); return v == 0 ? nil : v
    }
    static var cachedTag: String? { UserDefaults.standard.string(forKey: kTag) }
    static var hasCachedFile: Bool { FileManager.default.fileExists(atPath: cachedBinURL.path) }
    static func recordCache(build: Int, tag: String) {
        UserDefaults.standard.set(build, forKey: kBuild)
        UserDefaults.standard.set(tag, forKey: kTag)
    }
```

- [ ] **Step 2: `download(_:)` сохраняет в кэш** — заменить тело (dest = cachedBinURL вместо temp "firmware.bin"):
```swift
    func download(_ url: URL) async -> URL? {
        downloadProgress = 0
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (tmp, _) = try await session.download(from: url)
            let dest = UpdateClient.cachedBinURL
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            return dest
        } catch { return nil }
    }
```

- [ ] **Step 3: Build**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -4
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/UpdateClient.swift
git commit -m "feat(ios): UpdateClient internet reachability + firmware cache (.bin to Caches + UserDefaults)"
```

---

## Task 3: Строки гейта

**Files:** Modify `ios/ESP32Car/Resources/ru.lproj/Localizable.strings`, `ios/ESP32Car/L.swift`.

- [ ] **Step 1: `Localizable.strings`** — добавить:
```
"gate.noInternetTitle"     = "Нет интернета";
"gate.noInternetSub"       = "Подключись к интернету, чтобы проверить обновление прошивки перед поездкой.";
"gate.checkFailedTitle"    = "Не удалось проверить";
"gate.checkFailedSub"      = "Не получилось проверить обновления. Повтори.";
"gate.updateTitle"         = "Требуется обновление";
"gate.updateSub"           = "Прошивка устарела — обнови, чтобы продолжить.";
```
(`gate.retry` не нужен — переиспользуем существующий `L.fwRetry` = «Повторить».)

- [ ] **Step 2: `L.swift`** — добавить (рядом с fw-аксессорами):
```swift
    static var gateNoInternetTitle: String { s("gate.noInternetTitle") }
    static var gateNoInternetSub: String { s("gate.noInternetSub") }
    static var gateCheckFailedTitle: String { s("gate.checkFailedTitle") }
    static var gateCheckFailedSub: String { s("gate.checkFailedSub") }
    static var gateUpdateTitle: String { s("gate.updateTitle") }
    static var gateUpdateSub: String { s("gate.updateSub") }
```

- [ ] **Step 3: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/L.swift ios/ESP32Car/Resources
git commit -m "feat(ios): launch-gate strings"
```

---

## Task 4: `NoInternetView` (Wi-Fi-glyph)

**Files:** Create `ios/ESP32Car/NoInternetView.swift`.

- [ ] **Step 1: `ios/ESP32Car/NoInternetView.swift`**
```swift
import SwiftUI

/// Startup gate screen: GitHub unreachable. Amber pulsing Wi-Fi glyph + retry.
struct NoInternetView: View {
    let palette: Palette
    let onRetry: () -> Void
    private var p: Palette { palette }

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()
            HStack(spacing: 24) {
                WifiGlyph(color: p.warn)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 9) {
                    Text(L.gateNoInternetTitle).font(.system(size: 22, weight: .semibold)).foregroundStyle(p.text)
                    Text(L.gateNoInternetSub).font(.system(size: 13)).foregroundStyle(p.muted)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 260, alignment: .leading)
                    Button(action: onRetry) {
                        Text(L.fwRetry).font(.system(size: 14, weight: .semibold)).foregroundStyle(p.warn)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(p.warn.opacity(0.15)))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(p.warn.opacity(0.55), lineWidth: 1))
                    }.buttonStyle(.plain).padding(.top, 3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).padding(20)
        }
    }
}

/// Concentric Wi-Fi arcs sharing one bottom-centre origin, pulsing outward (amber).
private struct WifiGlyph: View {
    let color: Color
    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let origin = CGPoint(x: size.width / 2, y: size.height / 2 + 26)
                let radii: [CGFloat] = [16, 33, 50]
                for (i, r) in radii.enumerated() {
                    // staggered breathing: each arc phase-shifted
                    let phase = (t / 1.8 - Double(i) * 0.16).truncatingRemainder(dividingBy: 1)
                    let op = 0.16 + 0.84 * (0.5 - 0.5 * cos(2 * .pi * phase))
                    var path = Path()
                    path.addArc(center: origin, radius: r,
                                startAngle: .degrees(-145), endAngle: .degrees(-35), clockwise: false)
                    ctx.stroke(path, with: .color(color.opacity(op)),
                               style: StrokeStyle(lineWidth: 5, lineCap: .round))
                }
                // source dot
                let dotPhase = (t / 1.8).truncatingRemainder(dividingBy: 1)
                let dotOp = 0.45 + 0.55 * (0.5 - 0.5 * cos(2 * .pi * dotPhase))
                let dot = CGRect(x: origin.x - 5.5, y: origin.y - 5.5, width: 11, height: 11)
                ctx.fill(Path(ellipseIn: dot), with: .color(color.opacity(dotOp)))
            }
        }
        .frame(width: 130, height: 120)
    }
}
```

- [ ] **Step 2: Build + grep**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -4
grep -rn '[А-Яа-яЁё]' --include='*.swift' ESP32Car && echo LEAK || echo "(чисто)"
```
Expected: SUCCEEDED, чисто. (`palette.warn` — янтарный, существует в Theme.)

- [ ] **Step 3: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/NoInternetView.swift
git commit -m "feat(ios): NoInternetView — pulsing amber Wi-Fi glyph"
```

---

## Task 5: `UpdateCheckView` (проверка/скачивание/ошибка)

**Files:** Create `ios/ESP32Car/UpdateCheckView.swift`.

- [ ] **Step 1: `ios/ESP32Car/UpdateCheckView.swift`** — переиспользует `FirmwareCarView(phase:)`:
```swift
import SwiftUI

/// Startup gate: checking GitHub / downloading the firmware into cache / check failed.
/// Reuses the firmware car animation; progress comes from the shared UpdateClient.
struct UpdateCheckView: View {
    let palette: Palette
    let phase: AppFlow.Phase
    @ObservedObject var client: UpdateClient
    let onRetry: () -> Void
    private var p: Palette { palette }

    private var fwPhase: FwPhase {
        switch phase {
        case .downloading: return .downloading
        case .checkFailed: return .failed
        default:           return .checking
        }
    }

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()
            HStack(spacing: 24) {
                FirmwareCarView(phase: fwPhase, palette: p)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 9) {
                    switch phase {
                    case .downloading:
                        Text(L.fwDownloadTitle).font(.system(size: 22, weight: .semibold)).foregroundStyle(p.text)
                        Text("\(Int(client.downloadProgress * 100))%").font(.system(size: 14)).foregroundStyle(p.muted)
                        ProgressView(value: client.downloadProgress).tint(p.accent).frame(width: 160)
                    case .checkFailed:
                        Text(L.gateCheckFailedTitle).font(.system(size: 22, weight: .semibold)).foregroundStyle(p.text)
                        Text(L.gateCheckFailedSub).font(.system(size: 14)).foregroundStyle(p.muted)
                        Button(action: onRetry) {
                            Text(L.fwRetry).font(.system(size: 14, weight: .semibold)).foregroundStyle(p.accent)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 10).fill(p.accent.opacity(0.15)))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(p.accent.opacity(0.55), lineWidth: 1))
                        }.buttonStyle(.plain).padding(.top, 3)
                    default:
                        Text(L.fwChecking).font(.system(size: 22, weight: .semibold)).foregroundStyle(p.text)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).padding(20)
        }
    }
}
```

- [ ] **Step 2: Build**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -6
```
Expected: SUCCEEDED. (Зависит от `AppFlow.Phase` из Task 6 — если ещё нет, эта задача идёт ПОСЛЕ Task 6, либо временно `enum AppFlow { enum Phase ... }` уже определён. Порядок: выполнять Task 6 ДО Task 5 build, либо сослаться — см. примечание.)

- [ ] **Step 3: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/UpdateCheckView.swift
git commit -m "feat(ios): UpdateCheckView — checking/downloading/failed startup screen"
```

> ⚠ Зависимость: `UpdateCheckView` ссылается на `AppFlow.Phase`. **Выполнять Task 6 перед сборкой Task 5** (или объединить их сборку). Реализатор: создай оба файла, собери вместе.

---

## Task 6: `AppFlow` координатор + forced-режим `FirmwareView`

**Files:** Create `ios/ESP32Car/AppFlow.swift`; Modify `ios/ESP32Car/FirmwareView.swift`.

- [ ] **Step 1: `ios/ESP32Car/AppFlow.swift`**
```swift
import Foundation

/// Drives the launch gate: internet → fetch/cache firmware → connect to car → force-update if stale → drive.
@MainActor
final class AppFlow: ObservableObject {
    enum Phase: Equatable {
        case checkInternet, noInternet, checkUpdate, checkFailed, downloading, connectToCar, updateRequired, drive
    }
    @Published var phase: Phase = .checkInternet
    @Published var latestTag: String?
    let client = UpdateClient()

    /// Run the pre-connect gate (internet probe → latest release → download if needed).
    func startupCheck() async {
        phase = .checkInternet
        guard await UpdateClient.internetReachable() else { phase = .noInternet; return }
        phase = .checkUpdate
        guard let rel = await client.latestRelease() else { phase = .checkFailed; return }
        latestTag = rel.tag
        let latestBuild = UpdateClient.buildNumber(rel.tag)
        if UpdateClient.needsDownload(latestBuild: latestBuild,
                                      cachedBuild: UpdateClient.cachedBuild,
                                      hasCachedFile: UpdateClient.hasCachedFile) {
            phase = .downloading
            guard await client.download(rel.assetURL) != nil else { phase = .checkFailed; return }
            if let b = latestBuild { UpdateClient.recordCache(build: b, tag: rel.tag) }
        }
        phase = .connectToCar
    }

    /// Called once the car is reachable and its fw is known (on the connectToCar phase).
    func carConnected(carFw: String?) {
        guard phase == .connectToCar else { return }
        phase = UpdateClient.mustUpdate(carFw: carFw, latestTag: latestTag) ? .updateRequired : .drive
    }

    /// Forced FirmwareView signals completion.
    func updateFinished() { if phase == .updateRequired { phase = .drive } }

    func retry() { Task { await startupCheck() } }
}
```

- [ ] **Step 2: `FirmwareView.swift` — forced-режим.** Добавить параметры и поведение:
(a) В объявление структуры добавить:
```swift
    var forced: Bool = false
    var onDone: (() -> Void)? = nil
```
(b) В `.task { await check() }` — без изменений (авто-проверка уже есть).
(c) В `stateBlock`, ветку `.available`: в forced-режиме заголовок/подзаголовок гейта и сразу качаем:
```swift
            case .available:
                title(forced ? L.gateUpdateTitle : L.fwAvailable)
                sub(forced ? L.gateUpdateSub : L.fwTransition(current, release?.tag ?? "—"))
                fwButton(L.fwUpdate, prominent: true) { Task { await download() } }
```
(d) В ветку `.upToDate`: в forced-режиме экран не нужен (машинка уже актуальна — координатор не должен был сюда зайти), но на всякий случай сразу зовём onDone:
```swift
            case .upToDate:
                title(L.fwUpToDate); sub(L.fwVersionLine(current))
                if forced { Color.clear.onAppear { onDone?() } }
                else { fwButton(L.fwRecheck, prominent: false) { Task { await check() } } }
```
(e) В ветку `.done`: в forced-режиме после успеха — сигнал координатору:
```swift
            case .done:
                title(L.fwDoneTitle); sub(L.fwDoneSub(current))
                if forced { Color.clear.onAppear { onDone?() } }
```
(f) В forced-режиме `.downloaded` (нужно подключиться к машинке для заливки) — у нас уже на сети машинки (фаза updateRequired идёт ПОСЛЕ connectToCar), значит `status.online` true → кнопка «Залить» активна. Логику не меняем.

- [ ] **Step 3: Build (вместе с Task 5 UpdateCheckView)**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -6
```
Expected: SUCCEEDED.

- [ ] **Step 4: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/AppFlow.swift ios/ESP32Car/FirmwareView.swift
git commit -m "feat(ios): AppFlow launch coordinator + FirmwareView forced mode"
```

---

## Task 7: Корень `ESP32CarApp` + проверка

**Files:** Modify `ios/ESP32Car/ESP32CarApp.swift`.

- [ ] **Step 1: переписать корень** — switch по `flow.phase`:
```swift
import SwiftUI

@main
struct ESP32CarApp: App {
    @StateObject private var conn = CarConnection()
    @StateObject private var status = CarStatus()
    @StateObject private var flow = AppFlow()
    @Environment(\.scenePhase) private var phase
    @Environment(\.colorScheme) private var colorScheme
    private var p: Palette { Theme.current(colorScheme) }

    var body: some Scene {
        WindowGroup {
            root
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
                .task { await flow.startupCheck() }
                .onChange(of: phase) { newPhase in
                    if newPhase == .active { conn.resume(); status.start() }
                    else { conn.pause(); status.stop() }
                }
        }
    }

    @ViewBuilder private var root: some View {
        switch flow.phase {
        case .checkInternet, .checkUpdate, .downloading, .checkFailed:
            UpdateCheckView(palette: p, phase: flow.phase, client: flow.client) { flow.retry() }
        case .noInternet:
            NoInternetView(palette: p) { flow.retry() }
        case .connectToCar:
            ZStack {
                NoCarPlaceholder(palette: p)
                ConnectView()
            }
            .onAppear { conn.start(); status.start() }
            .onChange(of: status.online) { _ in tryCarConnected() }
            .onChange(of: status.fw) { _ in tryCarConnected() }
        case .updateRequired:
            NavigationStack {
                FirmwareView(palette: p, status: status, forced: true, onDone: { flow.updateFinished() })
            }
            .onAppear { conn.start(); status.start() }
        case .drive:
            ZStack {
                DriveView(conn: conn, status: status)
                if !status.online { ConnectView() }
            }
        }
    }

    private func tryCarConnected() {
        if status.online, status.fw != nil { flow.carConnected(carFw: status.fw) }
    }
}

/// Plain background shown behind the radar ConnectView while waiting for the car.
private struct NoCarPlaceholder: View {
    let palette: Palette
    var body: some View { palette.bg.ignoresSafeArea() }
}
```
ПРИМЕЧАНИЕ: `DriveView` сам стартует conn/status в onAppear — повторные `start()` идемпотентны (guard внутри). На фазе `connectToCar` мы стартуем их, чтобы `/status`-бутстрап опознал машинку и заполнил `status.fw`.

- [ ] **Step 2: Build + grep**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -8
grep -rn '[А-Яа-яЁё]' --include='*.swift' ESP32Car && echo LEAK || echo "(чисто)"
```
Expected: SUCCEEDED, чисто.

- [ ] **Step 3: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/ESP32CarApp.swift
git commit -m "feat(ios): launch gate wired into app root (internet → update → connect → gate → drive)"
```

---

## Task 8: Проверка в симуляторе

- [ ] **Step 1: норма (нет версионного релиза на GitHub → гейт пропускается).** Мок запущен (fw `v1.0+9000`),
  `POST /calib/save`. Продакшн-сборка → запуск. Mac на интернете → `internetReachable` true → latest на GitHub
  = легаси `v1.0` (без `+`) → `needsDownload`=false → `connectToCar` → мок опознан → `mustUpdate`=false →
  **drive**. Скриншот `/tmp/gate_drive.png` (главный экран, не залип на гейте).
- [ ] **Step 2: экран «Нет интернета»** — харнесс: временно в `ESP32CarApp.task` заменить на
  `flow.phase = .noInternet` (или отключить сеть Mac) → скриншот `/tmp/gate_nointernet.png` (Wi-Fi-glyph пульсирует).
  Откатить харнесс (`grep TEMP` чисто).
- [ ] **Step 3: форс-обновление** — харнесс: `flow.latestTag = "v1.0+99999"` + `flow.phase = .updateRequired`
  с моком (online) → скриншот `/tmp/gate_forced.png` («Требуется обновление», кнопка «Обновить», без «Закрыть»).
  Откатить харнесс. Дерево чистое.
- [ ] **Step 4:** host-тесты прошивки не затронуты; `swiftc /tmp/gate.swift && /tmp/gate` зелёный; продакшн в симуляторе.

---

## Self-Review заметки

- **Покрытие спеки:** стейт-машина (AppFlow, T6); экран «Нет интернета» Wi-Fi-glyph (T4); проверка/скачивание/
  ошибка (UpdateCheckView, T5); радар-подключение (ConnectView переиспользован, T7); форс-обновление без «Закрыть»
  (FirmwareView forced, T6); кэш .bin+номер (T2); сравнение numeric (mustUpdate, T1); строгий режим A (нет
  интернета → noInternet всегда, T6 startupCheck); краевые (легаси без номера → needsDownload/mustUpdate=false;
  старая прошивка → mustUpdate=true; API fail → checkFailed; симулятор не залипает, T8).
- **Тип-консистентность:** `UpdateClient.needsDownload(latestBuild:cachedBuild:hasCachedFile:)`,
  `mustUpdate(carFw:latestTag:)`, `internetReachable()`, `cachedBinURL/cachedBuild/cachedTag/hasCachedFile/recordCache`;
  `AppFlow.Phase`/`startupCheck()`/`carConnected(carFw:)`/`updateFinished()`/`retry()`/`client`/`latestTag`;
  `FirmwareView(palette:status:forced:onDone:)`; `UpdateCheckView(palette:phase:client:onRetry)`;
  `NoInternetView(palette:onRetry)`. `L.gate*`, `L.fwRetry` (переиспользован).
- **Замечания:** Task 5 и Task 6 собираются вместе (UpdateCheckView ссылается на AppFlow.Phase) — реализатор
  создаёт оба до общей сборки. Реальный e2e «форс-обновление» на железе проверяется при первом релизе через
  release.sh (ассистент по запросу). `palette.warn` — янтарный из Theme.