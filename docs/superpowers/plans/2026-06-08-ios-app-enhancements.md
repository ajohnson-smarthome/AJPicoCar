# iOS-апгрейд (темы + телеметрия + /status) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Развить нативный пульт: добавить firmware `GET /status`, точную проверку «мы на сети машинки», тёплые светлую/тёмную темы, кастомный переключатель схем и телеметрию (пинг, L/R %, анимация колёс «стрелка+свечение», статус) в раскладке B1.

**Architecture:** Прошивка получает аддитивный `status_api` (`GET /status` с подписью `device:"esp32-car"`). iOS: `Theme` (две тёплые палитры по `colorScheme`), `CarStatus` (опрос `/status` → online/ping/поля), `SchemeToggle` (кастомный сегмент), `WheelsView` (диаграмма + анимация колёс из команды), переработанный `DriveView` (B1 + темы + телеметрия). `ControlModel` получает чистый `sides(t,y)`.

**Tech Stack:** ESP-IDF (C), Swift 6 / SwiftUI, URLSession, XCTest/native-swift. Сборка iOS — `xcodebuild` под симулятор-SDK (рантайма симулятора нет; реальный тест на iPhone).

---

## File Structure

| Файл | Ответственность |
|---|---|
| `main/status_api.h/.c` *(new)* | `GET /status` → JSON (device/fw/uptime/calibrated/heap) |
| `main/main.c`, `main/CMakeLists.txt` | + `status_api_start()`, + исходник |
| `ios/ESP32Car/Theme.swift` *(new)* | `Palette` + тёплые dark/light + аксессор |
| `ios/ESP32Car/ControlModel.swift` | + `sides(t:y:)` (борта) |
| `ios/ESP32CarTests/ControlModelTests.swift` | + тест `sides` |
| `ios/ESP32Car/CarStatus.swift` *(new)* | опрос `/status`: online, ping, uptime, calibrated, fw |
| `ios/ESP32Car/SchemeToggle.swift` *(new)* | кастомный сегмент-контрол под темы |
| `ios/ESP32Car/WheelsView.swift` *(new)* | машинка сверху + анимация колёс (стрелка+свечение) |
| `ios/ESP32Car/DriveView.swift` | раскладка B1 + темы + телеметрия |
| `ios/ESP32Car/ESP32CarApp.swift` | + `CarStatus`, гейт по `online` |

---

## Task 1: Прошивка — эндпоинт `GET /status`

**Files:** Create `main/status_api.h`, `main/status_api.c`; Modify `main/main.c`, `main/CMakeLists.txt`.

- [ ] **Step 1: `main/status_api.h`**
```c
#ifndef STATUS_API_H
#define STATUS_API_H
#include "esp_err.h"
// Register GET /status (a signed JSON identifying this car + light telemetry).
esp_err_t status_api_start(void);
#endif // STATUS_API_H
```

- [ ] **Step 2: `main/status_api.c`**
```c
#include "status_api.h"
#include <stdio.h>
#include "esp_http_server.h"
#include "esp_timer.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_check.h"
#include "http_server.h"
#include "calibration.h"
#include "motors.h"

static const char *TAG = "status_api";
#define FW_VERSION "1.0"

static esp_err_t status_get(httpd_req_t *req) {
    motors_config_t tmp;
    bool calibrated = calibration_load(&tmp);
    long uptime_s = (long)(esp_timer_get_time() / 1000000);
    uint32_t heap = (uint32_t)esp_get_free_heap_size();

    char buf[160];
    int n = snprintf(buf, sizeof(buf),
        "{\"device\":\"esp32-car\",\"fw\":\"%s\",\"uptime_s\":%ld,\"calibrated\":%s,\"heap\":%u}",
        FW_VERSION, uptime_s, calibrated ? "true" : "false", (unsigned)heap);
    httpd_resp_set_type(req, "application/json");
    return httpd_resp_send(req, buf, n);
}

esp_err_t status_api_start(void) {
    httpd_handle_t server = http_server_get_handle();
    if (server == NULL) { ESP_LOGE(TAG, "http server not started"); return ESP_FAIL; }
    httpd_uri_t u = { .uri = "/status", .method = HTTP_GET, .handler = status_get };
    ESP_RETURN_ON_ERROR(httpd_register_uri_handler(server, &u), TAG, "reg /status");
    ESP_LOGI(TAG, "status endpoint registered");
    return ESP_OK;
}
```

- [ ] **Step 3: Wire into `main/main.c`**
Add include after `#include "calib_api.h"`:
```c
#include "status_api.h"
```
In `app_main`, after `ESP_ERROR_CHECK(calib_api_start());`, insert:
```c
    ESP_ERROR_CHECK(status_api_start());
```

- [ ] **Step 4: Add to `main/CMakeLists.txt`**
Add `"status_api.c"` to the `SRCS` list (keep everything else).

- [ ] **Step 5: Build**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && export PATH=/tmp/py313bin:$PATH && source ~/esp/esp-idf/export.sh && idf.py build 2>&1 | tail -5
```
Expected: `Project build complete`.

- [ ] **Step 6: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add main/status_api.h main/status_api.c main/main.c main/CMakeLists.txt
git commit -m "feat: add GET /status endpoint (car signature + uptime/calibrated/heap)"
```

---

## Task 2: iOS `Theme` (тёплые палитры)

**Files:** Create `ios/ESP32Car/Theme.swift`.

- [ ] **Step 1: Создать `ios/ESP32Car/Theme.swift`**
```swift
import SwiftUI

struct Palette {
    let bg: Color, panel: Color, line: Color, text: Color, muted: Color, accent: Color, idleWheel: Color
}

enum Theme {
    static let dark = Palette(
        bg:        Color(red: 0.067, green: 0.059, blue: 0.047),
        panel:     Color(red: 0.106, green: 0.090, blue: 0.067),
        line:      Color(red: 0.169, green: 0.145, blue: 0.110),
        text:      Color(red: 0.702, green: 0.675, blue: 0.624),
        muted:     Color(red: 0.420, green: 0.388, blue: 0.337),
        accent:    Color(red: 0.290, green: 0.871, blue: 0.502),
        idleWheel: Color(red: 0.227, green: 0.353, blue: 0.267))
    static let light = Palette(
        bg:        Color(red: 0.957, green: 0.941, blue: 0.910),
        panel:     Color(red: 1.000, green: 0.992, blue: 0.972),
        line:      Color(red: 0.910, green: 0.875, blue: 0.812),
        text:      Color(red: 0.416, green: 0.388, blue: 0.353),
        muted:     Color(red: 0.647, green: 0.612, blue: 0.557),
        accent:    Color(red: 0.082, green: 0.502, blue: 0.239),
        idleWheel: Color(red: 0.812, green: 0.890, blue: 0.824))
    static func current(_ scheme: ColorScheme) -> Palette { scheme == .dark ? dark : light }
}
```

- [ ] **Step 2: Compile-check**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`. (If SDK name differs use `xcodebuild -showsdks | grep simulator`.)

- [ ] **Step 3: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/Theme.swift && git commit -m "feat(ios): warm light/dark palettes"
```

---

## Task 3: iOS `ControlModel.sides()` + тест

**Files:** Modify `ios/ESP32Car/ControlModel.swift`, `ios/ESP32CarTests/ControlModelTests.swift`.

- [ ] **Step 1: Добавить тест в `ControlModelTests.swift`** (before the final `}`):
```swift
    func testSidesForward() {
        let s = ControlModel.sides(t: 1, y: 0)
        XCTAssertTrue(close(s.left, 1) && close(s.right, 1))
    }
    func testSidesSpin() {
        let s = ControlModel.sides(t: 0, y: 1)
        XCTAssertTrue(close(s.left, 1) && close(s.right, -1))
    }
    func testSidesArcNormalized() {
        let s = ControlModel.sides(t: 0.5, y: 0.5)   // l=1,r=0
        XCTAssertTrue(close(s.left, 1) && close(s.right, 0))
    }
```

- [ ] **Step 2: Native check `/tmp/sides_check.swift`** (add to a fresh harness — reuse `swiftc`):
```swift
import Foundation
func near(_ a: Double, _ b: Double) -> Bool { abs(a-b) < 1e-9 }
func run() {
    let f = ControlModel.sides(t: 1, y: 0); precondition(near(f.left,1) && near(f.right,1), "fwd")
    let s = ControlModel.sides(t: 0, y: 1); precondition(near(s.left,1) && near(s.right,-1), "spin")
    let a = ControlModel.sides(t: 0.5, y: 0.5); precondition(near(a.left,1) && near(a.right,0), "arc")
    print("sides checks: all passed")
}
```
And `/tmp/sides_main.swift`:
```swift
run()
```
Run (red — `sides` not defined yet):
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && swiftc ios/ESP32Car/ControlModel.swift /tmp/sides_check.swift /tmp/sides_main.swift -o /tmp/sides_check 2>&1 | tail -3
```
Expected: error `cannot find 'sides' in scope` (TDD red).

- [ ] **Step 3: Add `sides` to `ios/ESP32Car/ControlModel.swift`** (inside `enum ControlModel`, after `tank`):
```swift
    /// Mixer: throttle/yaw -> normalized left/right side speeds in [-1,1] (mirrors the firmware).
    static func sides(t: Double, y: Double) -> (left: Double, right: Double) {
        var l = t + y, r = t - y
        let m = Swift.max(abs(l), abs(r), 1)
        l /= m; r /= m
        return (l, r)
    }
```

- [ ] **Step 4: Native check passes**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && swiftc ios/ESP32Car/ControlModel.swift /tmp/sides_check.swift /tmp/sides_main.swift -o /tmp/sides_check && /tmp/sides_check
```
Expected: `sides checks: all passed`.

- [ ] **Step 5: App still compiles**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/ControlModel.swift ios/ESP32CarTests/ControlModelTests.swift
git commit -m "feat(ios): ControlModel.sides() for telemetry (native-verified)"
```

---

## Task 4: iOS `CarStatus` (опрос `/status`)

**Files:** Create `ios/ESP32Car/CarStatus.swift`.

- [ ] **Step 1: Создать `ios/ESP32Car/CarStatus.swift`**
```swift
import Foundation

@MainActor
final class CarStatus: ObservableObject {
    @Published var online = false
    @Published var pingMs: Int?
    @Published var uptimeS: Int?
    @Published var calibrated: Bool?
    @Published var fw: String?

    private let url = URL(string: "http://192.168.4.1/status")!
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    private func poll() {
        let started = Date()
        var req = URLRequest(url: url)
        req.timeoutInterval = 2
        req.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            var ok = false; var up: Int?; var cal: Bool?; var fwv: String?
            if let data,
               let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               (j["device"] as? String) == "esp32-car" {
                ok = true
                up = j["uptime_s"] as? Int
                cal = j["calibrated"] as? Bool
                fwv = j["fw"] as? String
            }
            Task { @MainActor in
                guard let self else { return }
                self.online = ok
                self.pingMs = ok ? ms : nil
                self.uptimeS = up
                self.calibrated = cal
                self.fw = fwv
            }
        }.resume()
    }
}
```

- [ ] **Step 2: Compile-check**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/CarStatus.swift && git commit -m "feat(ios): CarStatus polls /status (online, ping, telemetry fields)"
```

---

## Task 5: iOS `SchemeToggle` (кастомный сегмент)

**Files:** Create `ios/ESP32Car/SchemeToggle.swift`.

- [ ] **Step 1: Создать `ios/ESP32Car/SchemeToggle.swift`**
```swift
import SwiftUI

struct SchemeToggle: View {
    @Binding var scheme: String
    let palette: Palette

    var body: some View {
        HStack(spacing: 0) {
            seg("Arcade", "arcade")
            seg("Tank", "tank")
        }
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(palette.line))
    }

    private func seg(_ label: String, _ value: String) -> some View {
        Text(label)
            .font(.system(size: 13))
            .padding(.horizontal, 13).padding(.vertical, 6)
            .foregroundStyle(scheme == value ? palette.accent : palette.muted)
            .background(scheme == value ? palette.panel : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture { scheme = value }
    }
}
```

- [ ] **Step 2: Compile-check** (same xcodebuild command as Task 4 Step 2). Expected `** BUILD SUCCEEDED **`.
- [ ] **Step 3: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/SchemeToggle.swift && git commit -m "feat(ios): custom themed scheme toggle (visible on both themes)"
```

---

## Task 6: iOS `WheelsView` (анимация колёс)

**Files:** Create `ios/ESP32Car/WheelsView.swift`.

- [ ] **Step 1: Создать `ios/ESP32Car/WheelsView.swift`**
```swift
import SwiftUI

/// Top-down car with 4 wheels. left/right are side speeds in [-1,1]
/// (FL/RL = left, FR/RR = right). Arrow = direction, brightness/glow = |speed|.
struct WheelsView: View {
    let left: Double
    let right: Double
    let palette: Palette

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13).fill(palette.panel)
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(palette.line))
                .frame(width: 46, height: 74)
            RoundedRectangle(cornerRadius: 5).fill(palette.bg.opacity(0.6))
                .frame(width: 24, height: 12).offset(y: -6)

            wheel(left).offset(x: -30, y: -33)
            wheel(left).offset(x: -30, y: 33)
            wheel(right).offset(x: 30, y: -33)
            wheel(right).offset(x: 30, y: 33)
        }
        .frame(width: 84, height: 104)
    }

    private func wheel(_ v: Double) -> some View {
        let s = min(abs(v), 1)
        let active = s > 0.05
        return RoundedRectangle(cornerRadius: 5)
            .fill(active ? palette.accent.opacity(0.4 + 0.6 * s) : palette.idleWheel)
            .frame(width: 16, height: 26)
            .overlay(
                Image(systemName: v >= 0 ? "arrow.up" : "arrow.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.bg)
                    .opacity(active ? 1 : 0)
            )
            .shadow(color: active ? palette.accent.opacity(s) : .clear, radius: 8 * s)
            .animation(.easeOut(duration: 0.12), value: v)
    }
}
```

- [ ] **Step 2: Compile-check** (xcodebuild). Expected `** BUILD SUCCEEDED **`.
- [ ] **Step 3: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/WheelsView.swift && git commit -m "feat(ios): top-down wheels view with direction arrow + speed glow"
```

---

## Task 7: iOS `DriveView` — раскладка B1 + темы + телеметрия

**Files:** Replace `ios/ESP32Car/DriveView.swift`; Modify `ios/ESP32Car/ESP32CarApp.swift`, `ios/ESP32Car/ConnectView.swift`.

- [ ] **Step 1: Replace `ios/ESP32Car/DriveView.swift` ENTIRELY**
```swift
import SwiftUI

struct DriveView: View {
    @ObservedObject var conn: CarConnection
    @ObservedObject var status: CarStatus
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("scheme") private var schemeRaw = Scheme.arcade.rawValue

    @State private var arcX = 0.0
    @State private var arcY = 0.0
    @State private var leftY = 0.0
    @State private var rightY = 0.0
    @State private var curT = 0.0
    @State private var curY = 0.0

    @StateObject private var pad = Gamepad()
    @State private var haptics = Haptics()

    init(conn: CarConnection, status: CarStatus) {
        _conn = ObservedObject(wrappedValue: conn)
        _status = ObservedObject(wrappedValue: status)
    }

    private var scheme: Scheme { Scheme(rawValue: schemeRaw) ?? .arcade }
    private var p: Palette { Theme.current(colorScheme) }

    private func push() {
        let c: (t: Double, y: Double)
        if pad.connected {
            if scheme == .arcade { c = ControlModel.arcade(stickX: pad.leftX, stickY: -pad.leftY) }
            else { c = ControlModel.tank(leftStickY: -pad.leftY, rightStickY: -pad.rightY) }
        } else if scheme == .arcade {
            c = ControlModel.arcade(stickX: arcX, stickY: arcY)
        } else {
            c = ControlModel.tank(leftStickY: leftY, rightStickY: rightY)
        }
        curT = c.t; curY = c.y
        conn.setCommand(ControlModel.frame(t: c.t, y: c.y))
    }

    private var sides: (left: Double, right: Double) { ControlModel.sides(t: curT, y: curY) }

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()

            // top bar
            VStack {
                HStack {
                    HStack(spacing: 7) {
                        Circle().fill(status.online ? p.accent : Color.orange).frame(width: 8, height: 8)
                        Text(status.online ? "connected · \(status.pingMs ?? 0) ms" : "searching…")
                            .font(.system(size: 12)).foregroundStyle(p.muted)
                    }
                    Spacer()
                    SchemeToggle(scheme: $schemeRaw, palette: p)
                }
                .padding(.horizontal, 18).padding(.top, 8)
                Spacer()
            }

            // center: L · car · R
            HStack(spacing: 34) {
                sideLabel("L", sides.left)
                WheelsView(left: sides.left, right: sides.right, palette: p)
                sideLabel("R", sides.right)
            }

            // bottom-center small info
            VStack {
                Spacer()
                Text(statusLine).font(.system(size: 10)).foregroundStyle(p.muted).padding(.bottom, 20)
            }

            // joysticks
            if scheme == .arcade {
                HStack {
                    Spacer()
                    JoystickView(palette: p) { x, y in
                        if arcX == 0 && arcY == 0 && (x != 0 || y != 0) { haptics.tick() }
                        arcX = x; arcY = y; push()
                    }
                    .padding(.trailing, 24)
                }
                .padding(.bottom, 16)
                .frame(maxHeight: .infinity, alignment: .bottom)
            } else {
                HStack {
                    JoystickView(vertical: true, palette: p) { _, y in leftY = y; push() }.padding(.leading, 24)
                    Spacer()
                    JoystickView(vertical: true, palette: p) { _, y in rightY = y; push() }.padding(.trailing, 24)
                }
                .padding(.bottom, 16)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .onAppear { conn.start(); status.start() }
        .onReceive(pad.$leftX) { _ in push() }
        .onReceive(pad.$leftY) { _ in push() }
        .onReceive(pad.$rightY) { _ in push() }
        .onReceive(pad.$connected) { _ in push() }
    }

    private var statusLine: String {
        let up = status.uptimeS.map { "up \($0)s" } ?? "up —"
        let cal = (status.calibrated ?? false) ? "calib ✓" : "calib ✗"
        let fw = status.fw.map { "fw \($0)" } ?? "fw —"
        return "\(up) · \(cal) · \(fw)"
    }

    private func sideLabel(_ name: String, _ v: Double) -> some View {
        VStack(spacing: 2) {
            Text(name).font(.system(size: 13)).foregroundStyle(p.accent)
            Text("\(Int(v * 100))%").font(.system(size: 15, weight: .semibold)).foregroundStyle(p.accent)
        }
    }
}
```

- [ ] **Step 2: Update `ios/ESP32Car/JoystickView.swift`** to accept a palette
Replace the file ENTIRELY:
```swift
import SwiftUI

struct JoystickView: View {
    var vertical: Bool = false
    var size: CGFloat = 122
    var palette: Palette
    var onChange: (Double, Double) -> Void

    @State private var knob: CGSize = .zero

    var body: some View {
        ZStack {
            Circle().fill(palette.panel).overlay(Circle().strokeBorder(palette.line))
            Circle().fill(palette.accent).frame(width: 50, height: 50).offset(knob)
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
                .onEnded { _ in knob = .zero; onChange(0, 0) }
        )
    }
}
```

- [ ] **Step 3: Update `ios/ESP32Car/ConnectView.swift`** (theme-aware + network message)
Replace ENTIRELY:
```swift
import SwiftUI
import UIKit

struct ConnectView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var p: Palette { Theme.current(colorScheme) }
    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Машинка не найдена").font(.title3).foregroundStyle(p.text)
                Text("Подключись к Wi-Fi «ESP32-Car»\n(пароль drive1234) в Настройках,\nзатем вернись в приложение.")
                    .multilineTextAlignment(.center).foregroundStyle(p.muted)
                Button("Открыть Настройки") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(p.panel).foregroundStyle(p.accent)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(p.line))
            }
        }
    }
}
```

- [ ] **Step 4: Update `ios/ESP32Car/ESP32CarApp.swift`** (add CarStatus, gate on online)
Replace ENTIRELY:
```swift
import SwiftUI

@main
struct ESP32CarApp: App {
    @StateObject private var conn = CarConnection()
    @StateObject private var status = CarStatus()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            ZStack {
                DriveView(conn: conn, status: status)
                if !status.online { ConnectView() }
            }
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            .onAppear { status.start() }
            .onChange(of: phase) { newPhase in
                if newPhase != .active { conn.pause() }
            }
        }
    }
}
```

- [ ] **Step 5: Build (whole app)**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -10
```
Expected: `** BUILD SUCCEEDED **`. Fix any Swift errors reported (e.g. multi-var `@State`, missing `palette:` args) and rebuild.

- [ ] **Step 6: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/DriveView.swift ios/ESP32Car/JoystickView.swift ios/ESP32Car/ConnectView.swift ios/ESP32Car/ESP32CarApp.swift
git commit -m "feat(ios): B1 layout, warm themes, telemetry (ping/sides/wheels/status), /status gate"
```

---

## Task 8: Прошивка + устройство (с пользователем)

**Files:** (проверка)

- [ ] **Step 1: Прошить машинку** (новый `/status`):
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && export PATH=/tmp/py313bin:$PATH && source ~/esp/esp-idf/export.sh && (pkill -f esp_bridge.py 2>/dev/null; idf.py -p /dev/cu.usbmodem* flash) 2>&1 | tail -3
```
- [ ] **Step 2:** С Mac на сети `ESP32-Car`: `curl http://192.168.4.1/status` → JSON с `"device":"esp32-car"`.
- [ ] **Step 3: iPhone** (Xcode → Run на устройство): проверить — вне сети машинки экран «Машинка не найдена» + Настройки; на сети → пульт; переключить системную тему iOS (тёмная/светлая) → палитра меняется; ping/L-R %/анимация колёс/статус живые; аркада/танк; геймпад/haptics.

---

## Self-Review заметки
- **Покрытие спеки:** `/status` (Task 1); тёплые темы (Task 2, 7); `sides` телеметрия (Task 3); опрос/ping/поля (Task 4); кастомный переключатель (Task 5); анимация колёс стрелка+свечение (Task 6); раскладка B1 + интеграция + гейт по `online` (Task 7); устройство (Task 8).
- **Тип-консистентность:** `Palette`/`Theme.current(_:)`; `ControlModel.sides(t:y:)`; `CarStatus.online/pingMs/uptimeS/calibrated/fw/start()`; `SchemeToggle(scheme:palette:)`; `WheelsView(left:right:palette:)`; `JoystickView(vertical:size:palette:onChange:)` (палитра добавлена — все вызовы в DriveView передают `palette: p`); `DriveView(conn:status:)`.
- **Источники данных честны:** L/R % и колёса — из команды (`curT/curY` → `sides`), не реальные RPM; ping/uptime/calib/fw — реальные из `/status`.
- **Сборка iOS** — `xcodebuild` под симулятор-SDK (рантайма нет); `ControlModel.sides` — нативный swiftc-тест; реальная проверка на iPhone (Task 8).
- **JoystickView** получил параметр `palette` — это меняет сигнатуру; все три вызова в DriveView обновлены (Step 1 передаёт `palette: p`).
