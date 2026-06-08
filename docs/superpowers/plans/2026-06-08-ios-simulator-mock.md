# Запуск iOS-аппа в симуляторе против mock-машинки — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Запускать iOS-приложение пульта в iOS-симуляторе на Mac без машинки и телефона — через localhost mock-сервер и автопереключение адреса.

**Architecture:** Маленький aiohttp mock (`tools/mock_car/`) повторяет `GET /status` + `WS /ws` на `127.0.0.1:8080`. Новый `CarHost` в аппе через `#if targetEnvironment(simulator)` направляет `CarConnection`/`CarStatus` на localhost в симуляторе и на `192.168.4.1` на устройстве. Рантайм симулятора ставится разово.

**Tech Stack:** Python 3 + aiohttp; Swift 6 / SwiftUI; xcodebuild / xcrun simctl. Ветка `ios-app-phase1`.

---

## File Structure

| Файл | Ответственность |
|---|---|
| `tools/mock_car/mock_car.py` *(new)* | aiohttp: `GET /status` + `WS /ws` на 127.0.0.1:8080 |
| `tools/mock_car/requirements.txt` *(new)* | `aiohttp` |
| `tools/mock_car/README.md` *(new)* | как поднять venv и запустить |
| `ios/ESP32Car/CarHost.swift` *(new)* | адреса по `#if targetEnvironment(simulator)` |
| `ios/ESP32Car/CarConnection.swift` | использовать `CarHost.wsURL` |
| `ios/ESP32Car/CarStatus.swift` | использовать `CarHost.statusURL` |

---

## Task 1: Mock-сервер «фейковая машинка»

**Files:** Create `tools/mock_car/mock_car.py`, `tools/mock_car/requirements.txt`, `tools/mock_car/README.md`.

- [ ] **Step 1: `tools/mock_car/requirements.txt`**
```
aiohttp>=3.9
```

- [ ] **Step 2: `tools/mock_car/mock_car.py`**
```python
#!/usr/bin/env python3
"""Minimal mock of the ESP32-Car firmware HTTP/WS API for running the iOS app
in the simulator without hardware. Serves GET /status and WS /ws on 127.0.0.1:8080."""
import time
from aiohttp import web, WSMsgType

START = time.monotonic()

async def status(request):
    return web.json_response({
        "device": "esp32-car",
        "fw": "mock",
        "uptime_s": int(time.monotonic() - START),
        "calibrated": True,
        "heap": 200000,
    })

async def ws(request):
    wsr = web.WebSocketResponse()
    await wsr.prepare(request)
    print("ws: client connected")
    async for msg in wsr:
        if msg.type == WSMsgType.TEXT:
            print(f"ws rx: {msg.data}")     # the app's "t,y" frames; we just log them
        elif msg.type == WSMsgType.ERROR:
            print(f"ws error: {wsr.exception()}")
    print("ws: client disconnected")
    return wsr

def main():
    app = web.Application()
    app.add_routes([web.get("/status", status), web.get("/ws", ws)])
    print("mock car on http://127.0.0.1:8080  (GET /status, WS /ws)")
    web.run_app(app, host="127.0.0.1", port=8080)

if __name__ == "__main__":
    main()
```

- [ ] **Step 3: `tools/mock_car/README.md`**
```markdown
# Mock car (for running the iOS app in the Simulator without hardware)

Mimics the firmware's `GET /status` and `WS /ws` on `http://127.0.0.1:8080`.

## Run
```bash
cd tools/mock_car
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python mock_car.py
```

The iOS app, when built for the **Simulator**, talks to `127.0.0.1:8080` automatically
(see `CarHost.swift`). On a real device it talks to `192.168.4.1`. The server logs each
`t,y` frame the app sends.
```

- [ ] **Step 4: Create venv, install, smoke-test**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/tools/mock_car
python3 -m venv .venv && .venv/bin/pip install -q -r requirements.txt
.venv/bin/python mock_car.py & echo $! > /tmp/mock_car.pid
sleep 2
curl -s http://127.0.0.1:8080/status; echo
kill "$(cat /tmp/mock_car.pid)" 2>/dev/null
```
Expected: a JSON line like `{"device": "esp32-car", "fw": "mock", "uptime_s": 1, "calibrated": true, "heap": 200000}`.

- [ ] **Step 5: Ignore the venv**
Append to `.gitignore`:
```
tools/mock_car/.venv/
```

- [ ] **Step 6: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add tools/mock_car/mock_car.py tools/mock_car/requirements.txt tools/mock_car/README.md .gitignore
git commit -m "feat(tools): mock car server (/status + /ws) for simulator dev"
```

---

## Task 2: `CarHost` + развод адресов в клиентах

**Files:** Create `ios/ESP32Car/CarHost.swift`; Modify `ios/ESP32Car/CarConnection.swift`, `ios/ESP32Car/CarStatus.swift`.

- [ ] **Step 1: Создать `ios/ESP32Car/CarHost.swift`**
```swift
import Foundation

/// Single source of the car's address. Simulator builds talk to the localhost mock;
/// real-device builds talk to the car's softAP at 192.168.4.1.
enum CarHost {
    #if targetEnvironment(simulator)
    static let httpBase = "http://127.0.0.1:8080"
    static let wsURL    = "ws://127.0.0.1:8080/ws"
    #else
    static let httpBase = "http://192.168.4.1"
    static let wsURL    = "ws://192.168.4.1/ws"
    #endif
    static var statusURL: String { httpBase + "/status" }
}
```

- [ ] **Step 2: `CarConnection.swift` — использовать `CarHost.wsURL`**
In `ios/ESP32Car/CarConnection.swift`, replace the line
```swift
    private let url = URL(string: "ws://192.168.4.1/ws")!
```
with
```swift
    private let url = URL(string: CarHost.wsURL)!
```

- [ ] **Step 3: `CarStatus.swift` — использовать `CarHost.statusURL`**
In `ios/ESP32Car/CarStatus.swift`, replace the line
```swift
    private let url = URL(string: "http://192.168.4.1/status")!
```
with
```swift
    private let url = URL(string: CarHost.statusURL)!
```

- [ ] **Step 4: Compile-check (simulator SDK)**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -6
```
Expected: `** BUILD SUCCEEDED **`. (The `#if targetEnvironment(simulator)` branch compiles to the localhost addresses under the simulator SDK.)

- [ ] **Step 5: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/CarHost.swift ios/ESP32Car/CarConnection.swift ios/ESP32Car/CarStatus.swift
git commit -m "feat(ios): CarHost — simulator uses localhost mock, device uses 192.168.4.1"
```

---

## Task 3: Рантайм симулятора + запуск аппа против мока

**Files:** (настройка/проверка — без изменений кода)

- [ ] **Step 1: Скачать рантайм iOS-симулятора (разово, ~7 ГБ, долго)**
```bash
xcodebuild -downloadPlatform iOS 2>&1 | tail -5
```
Expected: успешная установка. Проверка: `xcrun simctl list runtimes | grep iOS` показывает iOS-рантайм; `xcrun simctl list devices available | grep -i iphone | head -3` показывает доступные iPhone.

- [ ] **Step 2: Поднять mock-сервер (в фоне)**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/tools/mock_car
.venv/bin/python mock_car.py > /tmp/mock_car.log 2>&1 & echo $! > /tmp/mock_car.pid
sleep 1 && curl -s http://127.0.0.1:8080/status; echo
```
Expected: JSON со `"device": "esp32-car"`.

- [ ] **Step 3: Собрать, поставить и запустить апп в симуляторе**
Выбрать доступный симулятор (например `iPhone 16`) и:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios
DEV='platform=iOS Simulator,name=iPhone 16'
xcodebuild build -scheme ESP32Car -destination "$DEV" -derivedDataPath /tmp/ddata 2>&1 | tail -3
xcrun simctl boot "iPhone 16" 2>/dev/null; open -a Simulator
APP=$(find /tmp/ddata/Build/Products -name "ESP32Car.app" | head -1)
xcrun simctl install booted "$APP"
xcrun simctl launch booted com.adamjohnson.esp32car
```
Expected: апп запускается в симуляторе, плашка становится **`connected · <ping> ms`** (мок отвечает на `/status`); в `/tmp/mock_car.log` появляются строки `ws rx: 0.00,0.00` (апп шлёт поток). Двигая стик мышью — L/R % и колёса реагируют; нижняя строка `up <n>s · calib ✓ · fw mock`.

- [ ] **Step 4: Проверить тему**
В симуляторе: Settings → Developer → Dark Appearance (или Features → Toggle Appearance в меню Simulator) → палитра аппа переключается между тёплой светлой и тёмной.

- [ ] **Step 5: Остановить мок (по желанию)**
```bash
kill "$(cat /tmp/mock_car.pid)" 2>/dev/null
```

---

## Self-Review заметки

- **Покрытие спеки:** рантайм симулятора (Task 3 Step 1); mock `/status`+`/ws` (Task 1); `CarHost` автопереключение + разводка в `CarConnection`/`CarStatus` (Task 2); запуск в симуляторе против мока + проверка темы (Task 3). Вне объёма (физика, `/calib`, имитация обрывов) — не включено.
- **Тип-консистентность:** `CarHost.wsURL` (исп. `CarConnection`), `CarHost.statusURL` (исп. `CarStatus`), `CarHost.httpBase`. Мок-ключи JSON (`device/fw/uptime_s/calibrated/heap`) совпадают с тем, что парсит `CarStatus` (`device`,`uptime_s`,`calibrated`,`fw`).
- **Регрессия на устройство:** `#else`-ветка = прежние `192.168.4.1`/`ws://192.168.4.1/ws`; реальная сборка на iPhone не меняется. Прошивка не трогается.
- **Порт:** мок на 8080; устройство — порт 80 (дефолт в URL). Симулятор-URL включают `:8080`.
- **Замечание по симулятору:** имя `iPhone 16` — подставить доступное из `xcrun simctl list devices available`. Bundle id `com.adamjohnson.esp32car` — из `project.yml`.
