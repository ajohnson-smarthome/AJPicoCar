# Телеметрия связи — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `/status` отдаёт `rssi` (AP-сторона), `ws_fps`, `wdt_trips`; палочки сигнала в аппе переходят на реальный RSSI (пинг — fallback); при wdt-срабатываниях в статус-строке появляется «⚠ обрывов: N».

**Architecture:** Атомарные volatile-счётчики в `ws_control`/`watchdog` + геттеры; `status_api` читает RSSI из `esp_wifi_ap_get_sta_list` и считает fps по дельте между опросами. iOS: перегрузка `ControlModel.signalLevel` (TDD), парсинг в `CarStatus`, условный элемент в `DriveView.statusBar`.

**Tech Stack:** ESP-IDF 5.4 (esp_wifi, esp_timer), Swift 6, нативный swiftc-тест. Ветка `telemetry`. SDK `iphonesimulator26.2`, `iPhone 17`, мок.

---

## File Structure

| Файл | Изменение |
|---|---|
| `main/ws_control.{c,h}` | счётчик кадров + `ws_control_frames()` |
| `main/watchdog.{c,h}` | счётчик срабатываний + `watchdog_trips()` |
| `main/status_api.c` | `rssi`/`ws_fps`/`wdt_trips` в JSON |
| `tools/mock_car/mock_car.py` | новые поля `/status` |
| iOS: `ControlModel.swift` (+тест), `CarStatus.swift`, `DriveView.swift`, `L.swift`, `ru.lproj` | RSSI-палочки + ⚠ |

---

## Task 1: Счётчики в прошивке

**Files:** Modify `main/ws_control.c`, `main/ws_control.h`, `main/watchdog.c`, `main/watchdog.h`.

- [ ] **Step 1: `main/ws_control.h`** — добавить `#include <stdint.h>` и декларацию:
```c
// Total valid control frames received since boot (atomic u32 on this single-core target).
uint32_t ws_control_frames(void);
```

- [ ] **Step 2: `main/ws_control.c`** — после `static const char *TAG = "ws";` добавить:
```c
static volatile uint32_t s_frames = 0;

uint32_t ws_control_frames(void) { return s_frames; }
```
И в `ws_handler`, в ветке успешного парсинга (рядом с `watchdog_feed();`), добавить `s_frames++;`:
```c
    if (control_parse_ty((const char *)buf, &t, &y) == 0) {
        s_frames++;
        watchdog_feed();
        car_drive(t, y);
    }
```

- [ ] **Step 3: `main/watchdog.h`** — добавить декларацию:
```c
// How many times the watchdog auto-stopped the car since boot.
uint32_t watchdog_trips(void);
```

- [ ] **Step 4: `main/watchdog.c`** — после `static TimerHandle_t s_timer = NULL;` добавить:
```c
static volatile uint32_t s_trips = 0;

uint32_t watchdog_trips(void) { return s_trips; }
```
И в `wdt_cb`, рядом с `car_stop();`, добавить `s_trips++;`:
```c
        ESP_LOGW(TAG, "no control frame for >%ums — stopping car", (unsigned)s_timeout_ms);
        s_trips++;
        car_stop();
```

- [ ] **Step 5: Build**
```bash
mkdir -p /tmp/py313bin && ln -sf /opt/homebrew/bin/python3.13 /tmp/py313bin/python3
cd /Users/adamjohnson/VSCode/esp32-p4-car && export PATH=/tmp/py313bin:$PATH && source ~/esp/esp-idf/export.sh >/dev/null 2>&1
idf.py build 2>&1 | grep -iE "Project build complete|error:" | grep -viE "rv32|march" | tail -3
```
Expected: `Project build complete`. Хост-тесты не трогаем (watchdog_stale без изменений), но прогнать `cd test && make run` — все зелёные.

- [ ] **Step 6: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add main/ws_control.c main/ws_control.h main/watchdog.c main/watchdog.h
git commit -m "feat: frame and watchdog-trip counters for link telemetry"
```

---

## Task 2: `/status` — rssi / ws_fps / wdt_trips

**Files:** Modify `main/status_api.c`.

- [ ] **Step 1: Инклюды** — добавить к существующим:
```c
#include "esp_wifi.h"
#include "ws_control.h"
#include "watchdog.h"
```
(`esp_timer.h` уже подключён.)

- [ ] **Step 2: Хелперы** — перед `status_get` добавить:
```c
// RSSI of the first (and only) connected softAP client; 0 = no data.
static int ap_client_rssi(void) {
    wifi_sta_list_t sta;
    if (esp_wifi_ap_get_sta_list(&sta) != ESP_OK || sta.num == 0) return 0;
    return sta.sta[0].rssi;
}

// WS frames/sec between two consecutive /status polls (0 on first call or after a >10s gap).
static int ws_fps_since_last_poll(void) {
    static uint32_t last_frames = 0;
    static int64_t last_us = 0;
    uint32_t frames = ws_control_frames();
    int64_t now = esp_timer_get_time();
    int fps = 0;
    if (last_us != 0) {
        int64_t dt = now - last_us;
        if (dt > 0 && dt < 10 * 1000000LL) {
            fps = (int)(((int64_t)(uint32_t)(frames - last_frames) * 1000000LL) / dt);
        }
    }
    last_frames = frames;
    last_us = now;
    return fps;
}
```

- [ ] **Step 3: `status_get`** — увеличить буфер и дополнить JSON:
```c
    char buf[224];
    int n = snprintf(buf, sizeof(buf),
        "{\"device\":\"esp32-car\",\"fw\":\"%s\",\"uptime_s\":%ld,\"calibrated\":%s,\"heap\":%u,"
        "\"rssi\":%d,\"ws_fps\":%d,\"wdt_trips\":%u}",
        fw, uptime_s, calibrated ? "true" : "false", (unsigned)heap,
        ap_client_rssi(), ws_fps_since_last_poll(), (unsigned)watchdog_trips());
```
(остальное в функции без изменений).

- [ ] **Step 4: Build** (команда из Task 1 Step 5). Expected: `Project build complete`.

- [ ] **Step 5: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add main/status_api.c
git commit -m "feat: /status reports rssi, ws_fps, wdt_trips"
```

---

## Task 3: Мок

**Files:** Modify `tools/mock_car/mock_car.py`.

- [ ] **Step 1:** в хендлере `/status` добавить в JSON-ответ поля `"rssi": -58, "ws_fps": 10, "wdt_trips": STATE.get("wdt_trips", 0)` и добавить `"wdt_trips": 0` в STATE (чтобы можно было менять в тестах руками).

- [ ] **Step 2: Smoke**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/tools/mock_car
pkill -f mock_car.py 2>/dev/null; sleep 1; nohup .venv/bin/python -u mock_car.py >/tmp/mock_car.log 2>&1 & disown; sleep 2
curl -s http://127.0.0.1:8080/status; echo
```
Expected: JSON содержит `"rssi": -58, "ws_fps": 10, "wdt_trips": 0`.

- [ ] **Step 3: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add tools/mock_car/mock_car.py && git commit -m "feat(tools): mock /status link telemetry fields"
```

---

## Task 4: iOS — RSSI-палочки + ⚠ (TDD для signalLevel)

**Files:** Modify `ios/ESP32Car/ControlModel.swift`, `ios/ESP32CarTests/ControlModelTests.swift`, `ios/ESP32Car/CarStatus.swift`, `ios/ESP32Car/DriveView.swift`, `ios/ESP32Car/L.swift`, `ios/ESP32Car/Resources/ru.lproj/Localizable.strings`.

- [ ] **Step 1: Native red** — `/tmp/sig2_check.swift`:
```swift
import Foundation
func run() {
    // RSSI thresholds
    precondition(ControlModel.signalLevel(online: true, rssi: -45, pingMs: 500) == 4, "rssi excellent")
    precondition(ControlModel.signalLevel(online: true, rssi: -55, pingMs: 500) == 3, "rssi good")
    precondition(ControlModel.signalLevel(online: true, rssi: -65, pingMs: 500) == 2, "rssi ok")
    precondition(ControlModel.signalLevel(online: true, rssi: -80, pingMs: 10) == 1, "rssi weak overrides ping")
    // fallback to ping when rssi is nil
    precondition(ControlModel.signalLevel(online: true, rssi: nil, pingMs: 10) == 4, "ping fallback")
    // offline
    precondition(ControlModel.signalLevel(online: false, rssi: -45, pingMs: 10) == 0, "offline")
    print("signal2 checks: all passed")
}
```
и `/tmp/main2.swift` с `run()`. Запуск:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && swiftc ios/ESP32Car/ControlModel.swift /tmp/sig2_check.swift /tmp/main2.swift -o /tmp/sig2 2>&1 | tail -2
```
Expected: ошибка «no member/argument signalLevel(online:rssi:pingMs:)».

- [ ] **Step 2: Реализация** — в `ControlModel` после существующей `signalLevel(online:pingMs:)` добавить:
```swift
    /// RSSI-based link level when the car reports its AP-side RSSI; falls back to ping.
    static func signalLevel(online: Bool, rssi: Int?, pingMs: Int?) -> Int {
        guard online else { return 0 }
        if let r = rssi, r != 0 {
            if r >= -50 { return 4 }
            if r >= -60 { return 3 }
            if r >= -70 { return 2 }
            return 1
        }
        return signalLevel(online: online, pingMs: pingMs)
    }
```

- [ ] **Step 3: Native green** — `swiftc ... && /tmp/sig2` → `signal2 checks: all passed`. Зеркало в XCTest (`ControlModelTests.swift`, перед закрывающей `}`):
```swift
    func testSignalLevelRssi() {
        XCTAssertEqual(ControlModel.signalLevel(online: true, rssi: -45, pingMs: 500), 4)
        XCTAssertEqual(ControlModel.signalLevel(online: true, rssi: -55, pingMs: 500), 3)
        XCTAssertEqual(ControlModel.signalLevel(online: true, rssi: -65, pingMs: 500), 2)
        XCTAssertEqual(ControlModel.signalLevel(online: true, rssi: -80, pingMs: 10), 1)
        XCTAssertEqual(ControlModel.signalLevel(online: true, rssi: nil, pingMs: 10), 4)
        XCTAssertEqual(ControlModel.signalLevel(online: false, rssi: -45, pingMs: 10), 0)
    }
```

- [ ] **Step 4: `CarStatus.swift`** — добавить published-поля после `fw`:
```swift
    @Published var rssi: Int?
    @Published var wdtTrips: Int?
    @Published var wsFps: Int?
```
В `poll()` расширить локальные переменные и парсинг:
```swift
            var ok = false; var up: Int?; var cal: Bool?; var fwv: String?
            var rs: Int?; var trips: Int?; var fps: Int?
            ...
                fwv = j["fw"] as? String
                if let r = j["rssi"] as? Int, r != 0 { rs = r }
                trips = j["wdt_trips"] as? Int
                fps = j["ws_fps"] as? Int
```
и в MainActor-блоке при `ok`:
```swift
                    self.rssi = rs
                    self.wdtTrips = trips
                    self.wsFps = fps
```

- [ ] **Step 5: Строка** — `Localizable.strings`: `"drive.wdtTrips" = "обрывов: %d";`
`L.swift`: `static func driveWdtTrips(_ n: Int) -> String { s("drive.wdtTrips", n) }`

- [ ] **Step 6: `DriveView.swift`**:
- `signalLevel` computed → `ControlModel.signalLevel(online: status.online, rssi: status.rssi, pingMs: status.pingMs)`
- в `statusBar`, после `statusItem("cpu", ...)` добавить:
```swift
            if let trips = status.wdtTrips, trips > 0 {
                statusItem("exclamationmark.triangle", L.driveWdtTrips(trips), p.warn)
            }
```

- [ ] **Step 7: Build + grep**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -6
grep -rn '[А-Яа-яЁё]' --include='*.swift' ESP32Car && echo LEAK || echo "(чисто)"
```
Expected: SUCCEEDED + чисто.

- [ ] **Step 8: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/ControlModel.swift ios/ESP32CarTests/ControlModelTests.swift ios/ESP32Car/CarStatus.swift ios/ESP32Car/DriveView.swift ios/ESP32Car/L.swift ios/ESP32Car/Resources
git commit -m "feat(ios): signal bars from real AP-side RSSI (ping fallback) + watchdog-trips warning"
```

---

## Task 5: Проверка в симуляторе

- [ ] **Step 1:** мок с `rssi:-58` → продакшн-сборка, главный экран: палочки = 3 (а не 4 от пинга ~2 мс) — доказательство, что RSSI в деле. Скриншот.
- [ ] **Step 2:** временно поставить в мок `"wdt_trips": 3` (правка STATE), перезапуск мока+аппа → в статус-строке появился «⚠ обрывов: 3». Скриншот. Вернуть 0, проверить исчезновение. Откатить правки мока, если временные.
- [ ] **Step 3:** дерево чистое, продакшн в симуляторе.

---

## Self-Review заметки

- **Покрытие спеки:** счётчики+геттеры (T1); rssi/ws_fps/wdt_trips в `/status`, буфер 224, fps-дельта с 10с-гардом (T2); мок (T3); RSSI-перегрузка signalLevel −50/−60/−70 + fallback + хост/XCTest, CarStatus (0→nil), палочки на RSSI, условный ⚠ (T4); проверка обоих поведений (T5).
- **Тип-консистентность:** `ws_control_frames(void)->uint32_t`, `watchdog_trips(void)->uint32_t` (h↔c↔status_api); `signalLevel(online:rssi:pingMs:)`; `status.rssi/wdtTrips/wsFps`; `L.driveWdtTrips`.
- **Замечания:** fps по дельте между опросами `/status` (апп опрашивает каждые 1.5 с — окно ок); несколько клиентов `/status` исказят fps друг другу — у нас клиент один, ок. `rssi:0` = «нет данных» (трактуется nil).
