# iOS-приложение, Фаза 1 (нативный пульт) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Нативное SwiftUI-приложение, которое рулит машинкой по WebSocket `t,y` (поток 10 Гц) — тач-джойстики (аркада/танк), геймпад, haptics — поверх существующей прошивки без изменений.

**Architecture:** Проект `ios/` собирается XcodeGen из `project.yml` (ориентация залочена в landscape, Info.plist с Local Network + ATS). Чистая математика схем в `ControlModel` (юнит-тесты на симуляторе). `CarConnection` (`ObservableObject`) держит `URLSessionWebSocketTask` + таймер 10 Гц + авто-reconnect. SwiftUI-вью: `DriveView` (джойстики/шкала газа/переключатель/статус), `ConnectView` (оверлей при потере связи), `JoystickView`. Геймпад (`GameController`) и `Haptics` (`CoreHaptics`) — отдельные модули.

**Tech Stack:** Swift 6 / SwiftUI, XcodeGen, `URLSessionWebSocketTask`, `GameController`, `CoreHaptics`, XCTest (симулятор). Подпись/установка на iPhone — Xcode (бесплатный personal team, переподписка раз в 7 дней).

**Разделение труда:** Swift пишем и собираем под симулятор здесь (`xcodebuild`). Реальную езду пользователь проверяет на iPhone (Xcode → Signing своим Apple ID → Run). Симулятор **не достучится** до машинки (она — WiFi-точка) — он только для компиляции/UI/юнит-тестов.

---

## File Structure

| Файл | Ответственность |
|---|---|
| `ios/project.yml` | XcodeGen: таргеты app+tests, bundle id, iOS 16, landscape, Info.plist (Local Network, ATS) |
| `ios/ESP32Car/ESP32CarApp.swift` | `@main` App + корневой `ContentView` (роутинг по состоянию связи) |
| `ios/ESP32Car/ControlModel.swift` | **чистая** математика схем `(stick)→(t,y)` + формат кадра |
| `ios/ESP32Car/CarConnection.swift` | WebSocket + поток 10 Гц + reachability/reconnect (`ObservableObject`) |
| `ios/ESP32Car/JoystickView.swift` | drag-джойстик, репорт `(x,y)∈[-1,1]` |
| `ios/ESP32Car/DriveView.swift` | пульт: статус, переключатель, джойстики/шкала газа, сведение в `t,y` |
| `ios/ESP32Car/ConnectView.swift` | оверлей «подключись к ESP32-Car» при потере связи |
| `ios/ESP32Car/Gamepad.swift` | `GameController` → оси (`ObservableObject`) |
| `ios/ESP32Car/Haptics.swift` | `CoreHaptics` — лёгкий тик |
| `ios/ESP32CarTests/ControlModelTests.swift` | юнит-тесты математики схем |

**Прошивка/`main/` — не трогаем.**

---

## Task 1: XcodeGen-проект + скелет (сборка под симулятор)

**Files:**
- Create: `ios/project.yml`, `ios/ESP32Car/ESP32CarApp.swift`, `ios/ESP32CarTests/SmokeTests.swift`
- Modify: `.gitignore`

- [ ] **Step 1: Установить XcodeGen**

Run:
```bash
brew install xcodegen && xcodegen --version
```
Expected: версия печатается (например `2.x`).

- [ ] **Step 2: Создать `ios/project.yml`**
```yaml
name: ESP32Car
options:
  bundleIdPrefix: com.adamjohnson
  deploymentTarget:
    iOS: "16.0"
  createIntermediateGroups: true
settings:
  base:
    MARKETING_VERSION: "1.0"
    CURRENT_PROJECT_VERSION: "1"
targets:
  ESP32Car:
    type: application
    platform: iOS
    sources:
      - ESP32Car
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.adamjohnson.esp32car
        TARGETED_DEVICE_FAMILY: "1"
        GENERATE_INFOPLIST_FILE: "NO"
        INFOPLIST_FILE: ESP32Car/Info.plist
    info:
      path: ESP32Car/Info.plist
      properties:
        CFBundleDisplayName: ESP32-Car
        UILaunchScreen: {}
        UIApplicationSceneManifest:
          UIApplicationSupportsMultipleScenes: false
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationLandscapeLeft
          - UIInterfaceOrientationLandscapeRight
        NSLocalNetworkUsageDescription: "Connects to the ESP32-Car over local Wi-Fi to drive it."
        NSAppTransportSecurity:
          NSAllowsLocalNetworking: true
  ESP32CarTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - ESP32CarTests
    dependencies:
      - target: ESP32Car
schemes:
  ESP32Car:
    build:
      targets:
        ESP32Car: all
        ESP32CarTests: [test]
    test:
      targets:
        - ESP32CarTests
```

- [ ] **Step 3: Создать `ios/ESP32Car/ESP32CarApp.swift` (минимальный)**
```swift
import SwiftUI

@main
struct ESP32CarApp: App {
    var body: some Scene {
        WindowGroup {
            Text("ESP32-Car")
                .font(.title)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.ignoresSafeArea())
        }
    }
}
```

- [ ] **Step 4: Создать `ios/ESP32CarTests/SmokeTests.swift`**
```swift
import XCTest

final class SmokeTests: XCTestCase {
    func testSmoke() {
        XCTAssertEqual(1 + 1, 2)
    }
}
```

- [ ] **Step 5: Сгенерировать проект**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate
```
Expected: `Created project at .../ios/ESP32Car.xcodeproj`.

- [ ] **Step 6: Выбрать доступный симулятор и собрать**

Run:
```bash
xcrun simctl list devices available | grep -i iphone | head -3
```
Возьми имя доступного iPhone (например `iPhone 16`). Затем собери:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`. (Если `iPhone 16` недоступен — подставь имя из списка.)

- [ ] **Step 7: Добавить артефакты Xcode в `.gitignore`**

Append to `.gitignore`:
```
ios/build/
ios/ESP32Car.xcodeproj/
ios/DerivedData/
*.xcuserstate
```
(`.xcodeproj` генерируется XcodeGen из `project.yml` — версионируем YAML, не проект.)

- [ ] **Step 8: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/project.yml ios/ESP32Car/ESP32CarApp.swift ios/ESP32CarTests/SmokeTests.swift .gitignore
git commit -m "feat(ios): XcodeGen project skeleton (landscape, Local Network + ATS)"
```

---

## Task 2: `ControlModel` — чистая математика схем (TDD)

**Files:**
- Create: `ios/ESP32Car/ControlModel.swift`
- Create: `ios/ESP32CarTests/ControlModelTests.swift`

- [ ] **Step 1: Написать падающий тест `ios/ESP32CarTests/ControlModelTests.swift`**
```swift
import XCTest
@testable import ESP32Car

final class ControlModelTests: XCTestCase {
    private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-6 }

    func testArcadeForward() {           // up = -y screen → throttle +1
        let r = ControlModel.arcade(stickX: 0, stickY: -1)
        XCTAssertTrue(close(r.t, 1) && close(r.y, 0))
    }
    func testArcadeTurn() {               // right = +x → yaw +1
        let r = ControlModel.arcade(stickX: 1, stickY: 0)
        XCTAssertTrue(close(r.t, 0) && close(r.y, 1))
    }
    func testTankForward() {              // both sticks up → forward
        let r = ControlModel.tank(leftStickY: -1, rightStickY: -1)
        XCTAssertTrue(close(r.t, 1) && close(r.y, 0))
    }
    func testTankSpin() {                 // left up, right down → spin
        let r = ControlModel.tank(leftStickY: -1, rightStickY: 1)
        XCTAssertTrue(close(r.t, 0) && close(r.y, 1))
    }
    func testClamp() {
        XCTAssertEqual(ControlModel.clamp(2.5), 1)
        XCTAssertEqual(ControlModel.clamp(-2.5), -1)
        XCTAssertEqual(ControlModel.clamp(0.3), 0.3)
    }
    func testFrame() {
        XCTAssertEqual(ControlModel.frame(t: 0.5, y: -1), "0.50,-1.00")
    }
}
```

- [ ] **Step 2: Запустить тест — убедиться, что не компилируется (нет ControlModel)**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodebuild test -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -8
```
Expected: ошибка компиляции — `cannot find 'ControlModel' in scope`. (Это TDD red.)

- [ ] **Step 3: Реализовать `ios/ESP32Car/ControlModel.swift`**
```swift
import Foundation

enum Scheme: String { case arcade, tank }

/// Pure mapping from joystick axes to the firmware's (throttle, yaw) in [-1,1].
/// Screen Y is positive downward, so "up" is a negative stick Y.
enum ControlModel {
    static func clamp(_ v: Double) -> Double { min(1, max(-1, v)) }

    /// One stick: up = throttle, left/right = yaw.
    static func arcade(stickX: Double, stickY: Double) -> (t: Double, y: Double) {
        (clamp(-stickY), clamp(stickX))
    }

    /// Two vertical sticks: each drives its side. left/right side = -stickY.
    static func tank(leftStickY: Double, rightStickY: Double) -> (t: Double, y: Double) {
        let l = -leftStickY, r = -rightStickY
        return (clamp((l + r) / 2), clamp((l - r) / 2))
    }

    /// Wire frame "t,y" with two decimals, matching the web pad / firmware parser.
    static func frame(t: Double, y: Double) -> String {
        String(format: "%.2f,%.2f", clamp(t), clamp(y))
    }
}
```

- [ ] **Step 4: Запустить тесты — PASS**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodebuild test -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -8
```
Expected: `** TEST SUCCEEDED **` (ControlModelTests + SmokeTests прошли).

- [ ] **Step 5: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/ControlModel.swift ios/ESP32CarTests/ControlModelTests.swift
git commit -m "feat(ios): ControlModel scheme math with unit tests"
```

---

## Task 3: `CarConnection` — WebSocket + поток 10 Гц

**Files:**
- Create: `ios/ESP32Car/CarConnection.swift`

- [ ] **Step 1: Создать `ios/ESP32Car/CarConnection.swift`**
```swift
import Foundation

@MainActor
final class CarConnection: ObservableObject {
    enum State { case connecting, connected, offline }
    @Published private(set) var state: State = .connecting

    private let url = URL(string: "ws://192.168.4.1/ws")!
    private var task: URLSessionWebSocketTask?
    private var timer: Timer?
    private var command = "0.00,0.00"
    private var started = false

    /// Latest driving intent; streamed at 10 Hz while connected.
    func setCommand(_ s: String) { command = s }

    func start() {
        guard !started else { return }
        started = true
        connect()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard state == .connected, let task else { return }
        task.send(.string(command)) { [weak self] err in
            if err != nil { Task { @MainActor in self?.drop() } }
        }
    }

    private func connect() {
        state = .connecting
        let t = URLSession.shared.webSocketTask(with: url)
        task = t
        t.resume()
        t.sendPing { [weak self] err in
            Task { @MainActor in
                guard let self, self.task === t else { return }
                self.state = (err == nil) ? .connected : .offline
                if err != nil { self.scheduleReconnect() }
            }
        }
        receive(on: t)
    }

    private func receive(on t: URLSessionWebSocketTask) {
        t.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.task === t else { return }
                switch result {
                case .success: self.receive(on: t)
                case .failure: self.drop()
                }
            }
        }
    }

    private func drop() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        state = .offline
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            Task { @MainActor in
                guard let self, self.state == .offline else { return }
                self.connect()
            }
        }
    }
}
```

- [ ] **Step 2: Собрать**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -4
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/CarConnection.swift
git commit -m "feat(ios): CarConnection WebSocket client with 10 Hz stream and reconnect"
```

---

## Task 4: `JoystickView` + `DriveView` (аркада/танк/шкала газа) + роутинг

**Files:**
- Create: `ios/ESP32Car/JoystickView.swift`, `ios/ESP32Car/DriveView.swift`, `ios/ESP32Car/ConnectView.swift`
- Modify: `ios/ESP32Car/ESP32CarApp.swift`

- [ ] **Step 1: Создать `ios/ESP32Car/JoystickView.swift`**
```swift
import SwiftUI

struct JoystickView: View {
    var vertical: Bool = false
    var size: CGFloat = 132
    /// Reports normalized (x, y) in [-1, 1]; screen Y positive downward. (0,0) on release.
    var onChange: (Double, Double) -> Void

    @State private var knob: CGSize = .zero

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.09))
                .overlay(Circle().strokeBorder(Color(white: 0.16)))
            Circle().fill(Color(red: 0.29, green: 0.87, blue: 0.5))
                .frame(width: 56, height: 56)
                .offset(knob)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let r = size / 2
                    var dx = g.location.x - r
                    var dy = g.location.y - r
                    if vertical { dx = 0 }
                    let d = (dx * dx + dy * dy).squareRoot()
                    if d > r { dx = dx / d * r; dy = dy / d * r }
                    knob = CGSize(width: dx, height: dy)
                    onChange(Double(dx / r), Double(dy / r))
                }
                .onEnded { _ in
                    knob = .zero
                    onChange(0, 0)
                }
        )
    }
}
```

- [ ] **Step 2: Создать `ios/ESP32Car/DriveView.swift`**
```swift
import SwiftUI

struct DriveView: View {
    @ObservedObject var conn: CarConnection
    @AppStorage("scheme") private var schemeRaw = Scheme.arcade.rawValue

    // touch axis state
    @State private var arcX = 0.0, arcY = 0.0
    @State private var leftY = 0.0, rightY = 0.0

    private var scheme: Scheme { Scheme(rawValue: schemeRaw) ?? .arcade }

    private func push() {
        let c: (t: Double, y: Double)
        if scheme == .arcade { c = ControlModel.arcade(stickX: arcX, stickY: arcY) }
        else { c = ControlModel.tank(leftStickY: leftY, rightStickY: rightY) }
        conn.setCommand(ControlModel.frame(t: c.t, y: c.y))
    }
    private var throttle: Double {
        scheme == .arcade ? ControlModel.clamp(-arcY)
                          : ControlModel.tank(leftStickY: leftY, rightStickY: rightY).t
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // status + scheme toggle
            VStack {
                HStack(spacing: 10) {
                    StatusPill(state: conn.state)
                    Picker("", selection: $schemeRaw) {
                        Text("Arcade").tag(Scheme.arcade.rawValue)
                        Text("Tank").tag(Scheme.tank.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
                .padding(.top, 8)
                Spacer()
            }

            // controls
            if scheme == .arcade {
                HStack {
                    ThrottleBar(value: throttle).padding(.leading, 30)
                    Spacer()
                    JoystickView { x, y in arcX = x; arcY = y; push() }
                        .padding(.trailing, 24)
                }
                .padding(.bottom, 24)
                .frame(maxHeight: .infinity, alignment: .bottom)
            } else {
                HStack {
                    JoystickView(vertical: true) { _, y in leftY = y; push() }.padding(.leading, 24)
                    Spacer()
                    JoystickView(vertical: true) { _, y in rightY = y; push() }.padding(.trailing, 24)
                }
                .padding(.bottom, 24)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .opacity(conn.state == .offline ? 0.4 : 1)
        .onAppear { conn.start() }
    }
}

private struct StatusPill: View {
    let state: CarConnection.State
    private var text: String {
        switch state { case .connecting: "connecting…"; case .connected: "connected"; case .offline: "reconnecting…" }
    }
    private var color: Color {
        switch state { case .connecting: .yellow; case .connected: Color(red:0.29,green:0.87,blue:0.5); case .offline: .red }
    }
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.system(size: 12)).foregroundStyle(.gray)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color(white: 0.06)).clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(white: 0.13)))
    }
}

private struct ThrottleBar: View {
    let value: Double  // -1..1
    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack(alignment: .center) {
                RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.09))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.13)))
                Rectangle().fill(Color(red:0.29,green:0.87,blue:0.5))
                    .frame(height: CGFloat(abs(value)) * h / 2)
                    .offset(y: value >= 0 ? -CGFloat(abs(value)) * h / 4 : CGFloat(abs(value)) * h / 4)
            }
        }
        .frame(width: 16, height: 122)
    }
}
```

- [ ] **Step 3: Создать `ios/ESP32Car/ConnectView.swift`**
```swift
import SwiftUI
import UIKit

struct ConnectView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Машинка не найдена").font(.title3).foregroundStyle(.white)
                Text("Подключись к Wi-Fi «ESP32-Car»\n(пароль drive1234) в Настройках.")
                    .multilineTextAlignment(.center).foregroundStyle(.gray)
                Button("Открыть Настройки") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Color(white: 0.12)).foregroundStyle(Color(red:0.29,green:0.87,blue:0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}
```

- [ ] **Step 4: Обновить `ios/ESP32Car/ESP32CarApp.swift` (роутинг)**

Replace ENTIRELY:
```swift
import SwiftUI

@main
struct ESP32CarApp: App {
    @StateObject private var conn = CarConnection()
    var body: some Scene {
        WindowGroup {
            ZStack {
                DriveView(conn: conn)
                if conn.state == .offline { ConnectView() }
            }
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
        }
    }
}
```

- [ ] **Step 5: Собрать**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -4
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/JoystickView.swift ios/ESP32Car/DriveView.swift ios/ESP32Car/ConnectView.swift ios/ESP32Car/ESP32CarApp.swift
git commit -m "feat(ios): drive screen — joysticks (arcade/tank), throttle bar, status, connect overlay"
```

---

## Task 5: Геймпад (`GameController`) + Haptics (`CoreHaptics`)

**Files:**
- Create: `ios/ESP32Car/Gamepad.swift`, `ios/ESP32Car/Haptics.swift`
- Modify: `ios/ESP32Car/DriveView.swift`

- [ ] **Step 1: Создать `ios/ESP32Car/Gamepad.swift`**
```swift
import GameController

@MainActor
final class Gamepad: ObservableObject {
    @Published var connected = false
    // Stick axes, up = +1 (GameController convention).
    @Published var leftX = 0.0, leftY = 0.0, rightY = 0.0

    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(changed),
            name: .GCControllerDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changed),
            name: .GCControllerDidDisconnect, object: nil)
        attach(GCController.controllers().first)
    }
    @objc private func changed() { attach(GCController.controllers().first) }

    private func attach(_ c: GCController?) {
        connected = (c?.extendedGamepad != nil)
        guard let gp = c?.extendedGamepad else { return }
        gp.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            Task { @MainActor in self?.leftX = Double(x); self?.leftY = Double(y) }
        }
        gp.rightThumbstick.valueChangedHandler = { [weak self] _, _, y in
            Task { @MainActor in self?.rightY = Double(y) }
        }
    }
}
```

- [ ] **Step 2: Создать `ios/ESP32Car/Haptics.swift`**
```swift
import CoreHaptics

@MainActor
final class Haptics {
    private var engine: CHHapticEngine?
    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        try? engine?.start()
    }
    func tick() {
        guard let engine else { return }
        let ev = CHHapticEvent(eventType: .hapticTransient,
            parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                         CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)],
            relativeTime: 0)
        if let pattern = try? CHHapticPattern(events: [ev], parameters: []),
           let player = try? engine.makePlayer(with: pattern) {
            try? player.start(atTime: 0)
        }
    }
}
```

- [ ] **Step 3: Подключить геймпад+haptics в `DriveView`**

In `ios/ESP32Car/DriveView.swift`, add after `@AppStorage("scheme")...`:
```swift
    @StateObject private var pad = Gamepad()
    @State private var haptics = Haptics()
```
Replace the `push()` method with:
```swift
    private func push() {
        let c: (t: Double, y: Double)
        if pad.connected {
            // gamepad: up = +1, so negate to screen-Y convention used by the model
            if scheme == .arcade { c = ControlModel.arcade(stickX: pad.leftX, stickY: -pad.leftY) }
            else { c = ControlModel.tank(leftStickY: -pad.leftY, rightStickY: -pad.rightY) }
        } else if scheme == .arcade {
            c = ControlModel.arcade(stickX: arcX, stickY: arcY)
        } else {
            c = ControlModel.tank(leftStickY: leftY, rightStickY: rightY)
        }
        conn.setCommand(ControlModel.frame(t: c.t, y: c.y))
    }
```
Add a haptic tick on touch engage: in `JoystickView`'s `onChange` closures in `DriveView` body, call `haptics.tick()` once on press — simplest: in the arcade joystick closure change `{ x, y in arcX = x; arcY = y; push() }` to:
```swift
                    JoystickView { x, y in
                        if (arcX == 0 && arcY == 0) && (x != 0 || y != 0) { haptics.tick() }
                        arcX = x; arcY = y; push()
                    }
```
(Tank closures may stay without haptics for now.)
Also, while a gamepad is connected, drive it continuously: add `.onReceive(pad.$leftY) { _ in push() }` and `.onReceive(pad.$rightY) { _ in push() }` to the root `ZStack` in `body`.

- [ ] **Step 4: Собрать**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -4
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/Gamepad.swift ios/ESP32Car/Haptics.swift ios/ESP32Car/DriveView.swift
git commit -m "feat(ios): gamepad (GameController) input + CoreHaptics tick"
```

---

## Task 6: Установка на iPhone и реальная езда (с пользователем)

**Files:** (без изменений кода — установка/проверка)

- [ ] **Step 1: Открыть проект и подписать**

Пользователь:
```bash
open /Users/adamjohnson/VSCode/esp32-p4-car/ios/ESP32Car.xcodeproj
```
В Xcode: выбрать таргет `ESP32Car` → **Signing & Capabilities** → Team = свой Apple ID (Personal Team); при необходимости поменять Bundle Identifier на уникальный (например `com.<твой-id>.esp32car`).

- [ ] **Step 2: Установить на iPhone**

Воткнуть iPhone по USB, выбрать его как destination, нажать **Run** (▶). На телефоне: Настройки → Основные → VPN и управление устройством → доверять своему сертификату разработчика. (Подпись живёт 7 дней.)

- [ ] **Step 3: Проверить езду**

На iPhone: подключиться к Wi-Fi `ESP32-Car` (`drive1234`). Запустить приложение (landscape). При первом сетевом обращении — разрешить «доступ к локальной сети». Проверить:
- статус становится `connected`;
- **аркада:** правый стик рулит (вверх=газ, лево/право=поворот), слева шкала газа; **танк:** переключатель → два стика = борта;
- при уходе из сети/сворачивании — `reconnecting`, машина встаёт (watchdog);
- если есть геймпад (PS/Xbox/MFi) — подключить по Bluetooth, проверить стики;
- лёгкая тактильная отдача при нажатии (на устройстве с haptics).

(Машинка на подставке — моторы крутятся.)

---

## Self-Review заметки

- **Покрытие спеки:** XcodeGen-проект + Info.plist (Local Network, ATS), landscape-lock (Task 1); `ControlModel` математика схем + юнит-тесты (Task 2); `CarConnection` WS + 10 Гц + reconnect (Task 3); `JoystickView`/`DriveView` аркада(стик+шкала газа)/танк, статус-плашка, `ConnectView`-оверлей (Task 4); геймпад + haptics (Task 5); установка на iPhone + реальная езда (Task 6). Калибровка — Фаза 2 (отдельный план).
- **Тип-консистентность:** `ControlModel.arcade(stickX:stickY:)`/`tank(leftStickY:rightStickY:)`/`clamp`/`frame`; `CarConnection.State`/`setCommand`/`start`; `Scheme`/`@AppStorage("scheme")`; `Gamepad.connected/leftX/leftY/rightY`; `Haptics.tick()`.
- **Тесты:** чистая математика `ControlModel` гоняется `xcodebuild test` на симуляторе (red→green). Сеть/UI — сборка под симулятор + реальная езда на устройстве (Task 6).
- **Симулятор vs устройство:** симулятор не достучится до машинки (WiFi-AP) — компиляция/UI/юнит-тесты; реальная езда — на iPhone.
- **Имя симулятора:** в командах `iPhone 16` — подставить доступный из `xcrun simctl list devices available`.

## Что дальше (Фаза 2)

Нативная калибровка: REST-методы в `CarConnection` (`GET /calib`, `POST /calib/spin`, `POST /calib/save`) + `CalibrateView` (вид машинки сверху, как в веб-пульте) + гейтинг при старте.
