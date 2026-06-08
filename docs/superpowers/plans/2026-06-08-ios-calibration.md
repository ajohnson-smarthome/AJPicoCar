# iOS мастер калибровки — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Реальный мастер калибровки в iOS-приложении (как в вебе): Spin пары → тап колеса → направление → 4× → Save через REST `/calib*`, с авто-предложением при некалиброванной машинке.

**Architecture:** Mock-сервер получает `/calib*` (флаг calibrated). Чистый `ControlModel.calibSaveBody` (хост-тест). `CalibClient` — async REST. `CalibrationView` — мастер (диаграмма + 4 колеса). `SettingsView` ведёт на него; `DriveView` авто-предлагает при `calibrated=false`. Прошивка не трогается.

**Tech Stack:** Python/aiohttp (mock); Swift 6 / SwiftUI (async/await, `.sheet`/`NavigationStack`); XCTest + нативный `swiftc`. Ветка `ios-calibration`. Симулятор-SDK `iphonesimulator26.2`, устройство `iPhone 17`.

---

## File Structure

| Файл | Ответственность |
|---|---|
| `tools/mock_car/mock_car.py` | + флаг `calibrated` + `GET /calib`, `POST /calib/spin`, `POST /calib/save` |
| `ios/ESP32Car/ControlModel.swift` | + `enum Corner` + `calibSaveBody(_:)` |
| `ios/ESP32CarTests/ControlModelTests.swift` | + тест `calibSaveBody` |
| `ios/ESP32Car/CalibClient.swift` *(new)* | async REST `/calib*` |
| `ios/ESP32Car/CalibrationView.swift` *(new)* | мастер калибровки |
| `ios/ESP32Car/SettingsView.swift` | «Калибровка» → `CalibrationView` (вместо стаба) |
| `ios/ESP32Car/DriveView.swift` | авто-лист при `status.calibrated == false` |

---

## Task 1: Mock `/calib*`

**Files:** Modify `tools/mock_car/mock_car.py`.

- [ ] **Step 1: Заменить `tools/mock_car/mock_car.py` целиком**
```python
#!/usr/bin/env python3
"""Minimal mock of the ESP32-Car firmware HTTP/WS API for running the iOS app
in the simulator without hardware. Serves /status, /ws, and /calib* on 127.0.0.1:8080."""
import time
from aiohttp import web, WSMsgType

START = time.monotonic()
STATE = {"calibrated": False}


async def status(request):
    return web.json_response({
        "device": "esp32-car",
        "fw": "mock",
        "uptime_s": int(time.monotonic() - START),
        "calibrated": STATE["calibrated"],
        "heap": 200000,
    })


async def ws(request):
    wsr = web.WebSocketResponse()
    await wsr.prepare(request)
    print("ws: client connected")
    async for msg in wsr:
        if msg.type == WSMsgType.TEXT:
            print(f"ws rx: {msg.data}")
        elif msg.type == WSMsgType.ERROR:
            print(f"ws error: {wsr.exception()}")
    print("ws: client disconnected")
    return wsr


async def calib(request):
    return web.json_response({"calibrated": STATE["calibrated"]})


async def calib_spin(request):
    print(f"calib/spin: {await request.text()}")
    return web.Response(text="ok")


async def calib_save(request):
    body = await request.text()
    print(f"calib/save: {body}")
    STATE["calibrated"] = True
    return web.Response(text="ok")


def main():
    app = web.Application()
    app.add_routes([
        web.get("/status", status),
        web.get("/ws", ws),
        web.get("/calib", calib),
        web.post("/calib/spin", calib_spin),
        web.post("/calib/save", calib_save),
    ])
    print("mock car on http://127.0.0.1:8080  (/status, /ws, /calib*)")
    web.run_app(app, host="127.0.0.1", port=8080)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Smoke-test**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/tools/mock_car
pkill -f mock_car.py 2>/dev/null; sleep 1
nohup .venv/bin/python -u mock_car.py > /tmp/mock_car.log 2>&1 & disown; sleep 2
echo "calib:"; curl -s http://127.0.0.1:8080/calib; echo
echo "save:"; curl -s -X POST --data "0:1,1:-1,2:1,3:-1" http://127.0.0.1:8080/calib/save; echo
echo "calib after save:"; curl -s http://127.0.0.1:8080/calib; echo
```
Expected: `{"calibrated": false}`, then `ok`, then `{"calibrated": true}`.

- [ ] **Step 3: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add tools/mock_car/mock_car.py
git commit -m "feat(tools): mock /calib endpoints (calibrated flag, spin/save)"
```

---

## Task 2: `Corner` + `calibSaveBody` (TDD)

**Files:** Modify `ios/ESP32Car/ControlModel.swift`, `ios/ESP32CarTests/ControlModelTests.swift`.

- [ ] **Step 1: Native check `/tmp/calib_check.swift`**
```swift
import Foundation
func run() {
    let a: [Corner: (pair: Int, sign: Int)] = [.fl: (0, 1), .fr: (1, -1), .rl: (2, 1), .rr: (3, -1)]
    let s = ControlModel.calibSaveBody(a)
    precondition(s == "0:1,1:-1,2:1,3:-1", "got \(s)")
    print("calib body check: passed")
}
```
And `/tmp/main.swift` containing `run()`.

- [ ] **Step 2: Run native check — FAIL (no symbols)**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && swiftc ios/ESP32Car/ControlModel.swift /tmp/calib_check.swift /tmp/main.swift -o /tmp/calib_check 2>&1 | tail -3
```
Expected: error `cannot find 'Corner'` / `no member 'calibSaveBody'`.

- [ ] **Step 3: Add to `ios/ESP32Car/ControlModel.swift`**
At file scope (next to `enum Scheme`):
```swift
enum Corner: String, CaseIterable { case fl, fr, rl, rr }
```
Inside `enum ControlModel`, after `frame`:
```swift
    /// Build the /calib/save body "p:s,p:s,p:s,p:s" in FL,FR,RL,RR order.
    /// Missing corners default to (0, 1) — the wizard only calls this when all 4 are set.
    static func calibSaveBody(_ a: [Corner: (pair: Int, sign: Int)]) -> String {
        Corner.allCases.map { c in
            let v = a[c] ?? (pair: 0, sign: 1)
            return "\(v.pair):\(v.sign)"
        }.joined(separator: ",")
    }
```

- [ ] **Step 4: Run native check — PASS**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && swiftc ios/ESP32Car/ControlModel.swift /tmp/calib_check.swift /tmp/main.swift -o /tmp/calib_check && /tmp/calib_check
```
Expected: `calib body check: passed`.

- [ ] **Step 5: Mirror into XCTest** — append before the final `}` of the class in `ios/ESP32CarTests/ControlModelTests.swift`:
```swift
    func testCalibSaveBody() {
        let a: [Corner: (pair: Int, sign: Int)] = [.fl: (0, 1), .fr: (1, -1), .rl: (2, 1), .rr: (3, -1)]
        XCTAssertEqual(ControlModel.calibSaveBody(a), "0:1,1:-1,2:1,3:-1")
    }
```

- [ ] **Step 6: App compiles**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -4
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/ControlModel.swift ios/ESP32CarTests/ControlModelTests.swift
git commit -m "feat(ios): Corner + calibSaveBody (FL,FR,RL,RR order) + test"
```

---

## Task 3: `CalibClient` (async REST)

**Files:** Create `ios/ESP32Car/CalibClient.swift`.

- [ ] **Step 1: Создать `ios/ESP32Car/CalibClient.swift`**
```swift
import Foundation

/// REST client for the car's calibration endpoints (uses CarHost's base address,
/// so it talks to the localhost mock in the simulator and 192.168.4.1 on device).
@MainActor
final class CalibClient {
    private var base: String { CarHost.httpBase }

    func fetchCalibrated() async -> Bool {
        guard let url = URL(string: base + "/calib") else { return false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return (j["calibrated"] as? Bool) ?? false
            }
        } catch {}
        return false
    }

    func spin(pair: Int, dir: Int) async {
        await post("/calib/spin", body: "\(pair),\(dir)")
    }

    @discardableResult
    func save(body: String) async -> Bool {
        await post("/calib/save", body: body)
    }

    @discardableResult
    private func post(_ path: String, body: String) async -> Bool {
        guard let url = URL(string: base + path) else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body.data(using: .utf8)
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }
}
```

- [ ] **Step 2: Regenerate + compile-check**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -4
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/CalibClient.swift
git commit -m "feat(ios): CalibClient async REST (/calib, spin, save)"
```

---

## Task 4: `CalibrationView` (мастер)

**Files:** Create `ios/ESP32Car/CalibrationView.swift`.

- [ ] **Step 1: Создать `ios/ESP32Car/CalibrationView.swift`**
```swift
import SwiftUI

struct CalibrationView: View {
    let palette: Palette
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var assign: [Corner: (pair: Int, sign: Int)] = [:]
    @State private var pending: Corner?
    @State private var saving = false
    @State private var msg = "Нажми Spin и смотри, какое колесо крутится."
    private let client = CalibClient()

    var body: some View {
        ZStack {
            palette.bg.ignoresSafeArea()
            VStack(spacing: 14) {
                Text("Шаг \(min(step + 1, 4))/4").font(.headline).foregroundStyle(palette.text)
                diagram
                HStack(spacing: 10) {
                    Button("▶ Spin") { spin() }
                        .buttonStyle(.borderedProminent).tint(palette.accent).disabled(step >= 4)
                    if pending != nil {
                        Button("↑ вперёд") { assignDir(1) }.tint(palette.accent)
                        Button("↓ назад") { assignDir(-1) }.tint(palette.warn)
                    }
                    Button("✔ Save") { save() }.disabled(step < 4 || saving)
                }
                Text(msg).font(.footnote).foregroundStyle(palette.muted).multilineTextAlignment(.center)
            }
            .padding()
        }
        .navigationTitle("Калибровка")
        .navigationBarTitleDisplayMode(.inline)
        .tint(palette.accent)
    }

    private var diagram: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(palette.panel)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.line))
                .frame(width: 92, height: 132)
            ForEach(Corner.allCases, id: \.self) { wheelButton($0) }
        }
        .frame(width: 170, height: 170)
    }

    private func wheelButton(_ c: Corner) -> some View {
        let assigned = assign[c] != nil
        let isPending = pending == c
        let fill = assigned ? palette.accent : (isPending ? palette.warn : palette.idleWheel)
        return Button { tap(c) } label: {
            Text(assigned ? "✓" : c.label)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 32, height: 42)
                .background(fill)
                .foregroundStyle(palette.bg)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .disabled(assigned)
        .offset(x: c.dx, y: c.dy)
    }

    private func spin() {
        Task { await client.spin(pair: step, dir: 1) }
        msg = "Кручу мотор \(step + 1)… тапни колесо, что крутится."
    }
    private func tap(_ c: Corner) {
        guard assign[c] == nil else { return }
        pending = c
        msg = "Куда крутилось колесо \(c.label)?"
    }
    private func assignDir(_ sign: Int) {
        guard let c = pending else { return }
        assign[c] = (pair: step, sign: sign)
        pending = nil
        step += 1
        msg = step < 4 ? "Жми Spin для следующего мотора." : "Все 4 размечены — жми Save."
    }
    private func save() {
        saving = true
        Task {
            let ok = await client.save(body: ControlModel.calibSaveBody(assign))
            saving = false
            if ok { dismiss() } else { msg = "Сохранение не прошло — повтори." }
        }
    }
}

private extension Corner {
    var label: String { rawValue.uppercased() }
    var dx: CGFloat { (self == .fl || self == .rl) ? -54 : 54 }
    var dy: CGFloat { (self == .fl || self == .fr) ? -46 : 46 }
}
```

- [ ] **Step 2: Regenerate + compile-check**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -6
```
Expected: `** BUILD SUCCEEDED **`. Fix any Swift errors and rebuild.

- [ ] **Step 3: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/CalibrationView.swift
git commit -m "feat(ios): CalibrationView wizard (spin/tap-wheel/direction/save)"
```

---

## Task 5: Встроить — Settings + авто-предложение в DriveView

**Files:** Modify `ios/ESP32Car/SettingsView.swift`, `ios/ESP32Car/DriveView.swift`.

- [ ] **Step 1: `SettingsView.swift` — «Калибровка» → реальный экран**
Replace the `NavigationLink { CalibrationStub(palette: palette) } label: { ... }` so the destination is `CalibrationView`:
```swift
                    NavigationLink {
                        CalibrationView(palette: palette)
                    } label: {
                        Label("Калибровка", systemImage: "gearshape.2")
                            .foregroundStyle(palette.text)
                    }
                    .listRowBackground(palette.panel)
```
Delete the now-unused `private struct CalibrationStub { ... }` from the bottom of `SettingsView.swift`.

- [ ] **Step 2: `DriveView.swift` — состояние авто-предложения**
Add near the other `@State` (after `@State private var showSettings = false`):
```swift
    @State private var showCalib = false
    @State private var didPromptCalib = false
```

- [ ] **Step 3: `DriveView.swift` — триггер + лист**
After the existing `.sheet(isPresented: $showSettings) { SettingsView(palette: p) }`, append:
```swift
        .onReceive(status.$calibrated) { cal in
            if cal == false && !didPromptCalib { didPromptCalib = true; showCalib = true }
        }
        .sheet(isPresented: $showCalib) {
            NavigationStack {
                CalibrationView(palette: p)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Позже") { showCalib = false } }
                    }
            }
        }
```

- [ ] **Step 4: Regenerate + compile-check**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -6
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/SettingsView.swift ios/ESP32Car/DriveView.swift
git commit -m "feat(ios): calibration entry — settings link + auto-prompt when uncalibrated"
```

---

## Task 6: Проверка в симуляторе

**Files:** (проверка — без изменений кода)

- [ ] **Step 1: Перезапустить мок (свежий флаг) + апп**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/tools/mock_car
pkill -f mock_car.py 2>/dev/null; sleep 1
nohup .venv/bin/python -u mock_car.py > /tmp/mock_car.log 2>&1 & disown
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios
xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | grep -iE "BUILD SUCCEEDED|FAILED" | head -1
xcrun simctl install booted "$(find /tmp/ddata/Build/Products -name ESP32Car.app | head -1)"
xcrun simctl terminate booted com.adamjohnson.esp32car 2>/dev/null
xcrun simctl launch booted com.adamjohnson.esp32car
```

- [ ] **Step 2: Визуально**
- старт → `calibrated=false` → авто-лист «Калибровка»;
- пройти 4 шага: Spin (в `/tmp/mock_car.log` строки `calib/spin: 0,1` …), тап колеса, направление; колёса помечаются ✓;
- Save → `calib/save: ...` в логе → лист закрывается → статус-строка `calib ✓`;
- повторно открыть через ⚙ → Настройки → «Калибровка»;
- обе темы.
Скриншот: `xcrun simctl io booted screenshot /tmp/calib.png`.

- [ ] **Step 3: На устройстве (с пользователем)**
Позже: реальная калибровка на iPhone (моторы крутятся, идентификация по физическому колесу) → Save → едет правильно.

---

## Self-Review заметки

- **Покрытие спеки:** mock `/calib*` + флаг (Task 1); `Corner`/`calibSaveBody` FL,FR,RL,RR + тест (Task 2); `CalibClient` REST (Task 3); `CalibrationView` Spin/тап/направление/Save (Task 4); вход — settings-ссылка + авто при `calibrated=false` один раз (Task 5); проверка (Task 6). Прошивка не трогается.
- **Тип-консистентность:** `Corner: String, CaseIterable {fl,fr,rl,rr}`; `calibSaveBody([Corner:(pair:Int,sign:Int)]) -> String`; `CalibClient.fetchCalibrated/spin(pair:dir:)/save(body:)`; `CalibrationView(palette:)`; `status.$calibrated` (Bool?, есть в `CarStatus`); `CarHost.httpBase`. Spin всегда dir=1; знак выбирается на шаге направления.
- **Тесты:** чистый `calibSaveBody` — нативно + XCTest; поток — визуально в симуляторе против мока (мотор-идентификация только на устройстве).
- **Замечания:** `fetchCalibrated` в `CalibClient` есть, но авто-предложение использует `status.$calibrated` (уже опрашивается) — `fetchCalibrated` оставлен на будущее/ручную проверку. Имя симулятора `iPhone 17`, bundle `com.adamjohnson.esp32car`.
