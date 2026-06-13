# Телеметрия по WebSocket — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Машинка пушит живую телеметрию по `/ws` (5 Гц); апп берёт её из WS + один бутстрап `GET /status`; поллинг убран; живость по свежести кадров. Управление/watchdog/REST не меняются.

**Architecture:** Чистый форматтер `telemetry_fields()` (inline в `telemetry.h`, host-тест) + модуль `telemetry.c` (сбор данных + 5 Гц esp_timer → `ws_control_send`). `ws_control` запоминает сокет клиента и шлёт async. iOS: `CarConnection` парсит входящие WS-кадры → `CarStatus.apply()`; `CarStatus` делает один бутстрап `/status`, живость по свежести.

**Tech Stack:** ESP-IDF 5.4 (esp_http_server WS async, esp_timer), cc host-тест, Swift 6 / SwiftUI, aiohttp мок. Ветка `ws-telemetry`. SDK `iphonesimulator26.2`, `iPhone 17`.

---

## File Structure

| Файл | Изменение |
|---|---|
| `main/telemetry.h` *(new)* | `telemetry_t` + чистый `telemetry_fields()` (inline) + декларации `telemetry_gather/json/start` |
| `main/telemetry.c` *(new)* | сбор данных (rssi/fps/trips/uptime/heap/calibrated) + 5 Гц таймер → пуш |
| `test/test_telemetry.c` *(new)* + Makefile | host-тест `telemetry_fields` |
| `main/ws_control.{c,h}` | запомнить сокет клиента + `ws_control_send()` |
| `main/status_api.c` | переиспользует `telemetry_gather`+`telemetry_fields` (DRY), оставляет device/fw |
| `main/main.c`, `main/CMakeLists.txt` | `telemetry_start()` + SRCS |
| `tools/mock_car/mock_car.py` | 5 Гц пуш телеметрии в `/ws` |
| iOS: `Telemetry.swift` *(new, или в ControlModel)*, `CarConnection.swift`, `CarStatus.swift`, `DriveView.swift`, `L.swift`, `ru.lproj`, `ESP32CarTests` | парсер + WS-приём + бутстрап + свежесть + пилюля |

---

## Task 1: Чистый форматтер `telemetry_fields` (TDD)

**Files:** Create `main/telemetry.h`, `test/test_telemetry.c`; Modify `test/Makefile`.

- [ ] **Step 1: `main/telemetry.h`**
```c
#ifndef TELEMETRY_H
#define TELEMETRY_H

#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include "esp_err.h"

// Live telemetry snapshot (changing fields only; device/fw stay in /status bootstrap).
typedef struct {
    int      rssi;        // dBm, 0 = no data
    int      ws_fps;      // control frames/sec
    uint32_t wdt_trips;   // watchdog auto-stops since boot
    long     uptime_s;    // seconds
    uint32_t heap;        // free heap, bytes
    bool     calibrated;  // valid calibration present
} telemetry_t;

// Pure: format the live fields (NO surrounding braces) into buf. Returns length, or -1 on truncation.
// Shared by the WS push ("{<fields>}") and /status ("{\"device\":..,\"fw\":..,<fields>}").
static inline int telemetry_fields(char *buf, size_t n, const telemetry_t *t) {
    int r = snprintf(buf, n,
        "\"rssi\":%d,\"ws_fps\":%d,\"wdt_trips\":%u,\"uptime_s\":%ld,\"heap\":%u,\"calibrated\":%s",
        t->rssi, t->ws_fps, (unsigned)t->wdt_trips, t->uptime_s, (unsigned)t->heap,
        t->calibrated ? "true" : "false");
    if (r < 0 || r >= (int)n) return -1;
    return r;
}

#ifndef TELEMETRY_HOST_TEST
void      telemetry_gather(telemetry_t *out);  // read live values (IDF)
int       telemetry_json(char *buf, size_t n); // gather + "{<fields>}" for the WS push
esp_err_t telemetry_start(void);               // start the 5 Hz push timer
#endif

#endif // TELEMETRY_H
```

- [ ] **Step 2: `test/test_telemetry.c`**
```c
#define TELEMETRY_HOST_TEST
#include "../main/telemetry.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>

int main(void) {
    char buf[160];
    telemetry_t t = { .rssi = -55, .ws_fps = 10, .wdt_trips = 2,
                      .uptime_s = 123, .heap = 198000, .calibrated = true };
    int n = telemetry_fields(buf, sizeof(buf), &t);
    assert(n > 0);
    assert(strcmp(buf,
        "\"rssi\":-55,\"ws_fps\":10,\"wdt_trips\":2,\"uptime_s\":123,\"heap\":198000,\"calibrated\":true") == 0);

    // calibrated=false path
    t.calibrated = false; t.rssi = 0;
    n = telemetry_fields(buf, sizeof(buf), &t);
    assert(n > 0 && strstr(buf, "\"calibrated\":false") && strstr(buf, "\"rssi\":0"));

    // truncation → -1
    assert(telemetry_fields(buf, 8, &t) == -1);

    printf("test_telemetry: all passed\n");
    return 0;
}
```

- [ ] **Step 3: `test/Makefile`** — добавить `test_telemetry` по образцу `test_trim` (в all/run/clean, без extra-объектов).

- [ ] **Step 4: Run** `cd test && make clean >/dev/null && make run` — Expected: `test_telemetry: all passed` (+ остальные 7).

- [ ] **Step 5: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add main/telemetry.h test/test_telemetry.c test/Makefile
git commit -m "feat: pure telemetry_fields formatter + host test"
```

---

## Task 2: `ws_control` — сокет клиента + async-отправка

**Files:** Modify `main/ws_control.c`, `main/ws_control.h`.

- [ ] **Step 1: `main/ws_control.h`** — добавить декларацию:
```c
// Send a text frame to the currently-connected WS client (no-op if none).
// Clears the stored client on send failure. Safe to call from a timer/task.
esp_err_t ws_control_send(const char *data, size_t len);
```

- [ ] **Step 2: `main/ws_control.c`** — после `static volatile uint32_t s_frames = 0;` добавить:
```c
static volatile int s_client_fd = -1;   // single phone client; last connect wins
```
В `ws_handler`, в ветке handshake, запомнить сокет:
```c
    if (req->method == HTTP_GET) {
        s_client_fd = httpd_req_to_sockfd(req);
        ESP_LOGI(TAG, "ws client connected (fd=%d)", s_client_fd);
        return ESP_OK;
    }
```
В конец файла добавить отправку:
```c
esp_err_t ws_control_send(const char *data, size_t len) {
    int fd = s_client_fd;
    if (fd < 0) return ESP_OK;  // no client — nothing to do
    httpd_handle_t server = http_server_get_handle();
    if (server == NULL) return ESP_FAIL;
    httpd_ws_frame_t frame = {
        .type = HTTPD_WS_TYPE_TEXT,
        .payload = (uint8_t *)data,
        .len = len,
    };
    esp_err_t e = httpd_ws_send_frame_async(server, fd, &frame);
    if (e != ESP_OK) s_client_fd = -1;  // client gone — stop pushing until next connect
    return e;
}
```

- [ ] **Step 3: Build** (IDF). Expected: `Project build complete`.
```bash
mkdir -p /tmp/py313bin && ln -sf /opt/homebrew/bin/python3.13 /tmp/py313bin/python3
cd /Users/adamjohnson/VSCode/esp32-p4-car && export PATH=/tmp/py313bin:$PATH && source ~/esp/esp-idf/export.sh >/dev/null 2>&1
idf.py build 2>&1 | grep -iE "Project build complete|error:" | grep -viE "rv32|march|reent" | tail -2
```

- [ ] **Step 4: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add main/ws_control.c main/ws_control.h
git commit -m "feat: ws_control remembers client socket + async ws_control_send"
```

---

## Task 3: `telemetry.c` (сбор + 5 Гц пуш) + DRY в `status_api`

**Files:** Create `main/telemetry.c`; Modify `main/status_api.c`, `main/main.c`, `main/CMakeLists.txt`.

- [ ] **Step 1: `main/telemetry.c`**
```c
#include "telemetry.h"
#include "esp_timer.h"
#include "esp_heap_caps.h"
#include "esp_wifi.h"
#include "esp_log.h"
#include "calibration.h"
#include "motors.h"
#include "ws_control.h"
#include "watchdog.h"

static const char *TAG = "telemetry";
#define PUSH_PERIOD_US 200000   // 5 Hz

static int ap_client_rssi(void) {
    wifi_sta_list_t sta;
    if (esp_wifi_ap_get_sta_list(&sta) != ESP_OK || sta.num == 0) return 0;
    return sta.sta[0].rssi;
}

// WS frames/sec between consecutive gather() calls (0 on first call or after a >10s gap).
static int ws_fps_now(void) {
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

void telemetry_gather(telemetry_t *out) {
    motors_config_t tmp;
    out->rssi       = ap_client_rssi();
    out->ws_fps     = ws_fps_now();
    out->wdt_trips  = watchdog_trips();
    out->uptime_s   = (long)(esp_timer_get_time() / 1000000);
    out->heap       = (uint32_t)esp_get_free_heap_size();
    out->calibrated = calibration_load(&tmp);
}

int telemetry_json(char *buf, size_t n) {
    telemetry_t t;
    telemetry_gather(&t);
    char fields[160];
    if (telemetry_fields(fields, sizeof(fields), &t) < 0) return -1;
    int r = snprintf(buf, n, "{%s}", fields);
    return (r < 0 || r >= (int)n) ? -1 : r;
}

static void push_cb(void *arg) {
    (void)arg;
    char buf[200];
    int n = telemetry_json(buf, sizeof(buf));
    if (n > 0) ws_control_send(buf, (size_t)n);
}

esp_err_t telemetry_start(void) {
    const esp_timer_create_args_t args = { .callback = push_cb, .name = "telemetry" };
    esp_timer_handle_t h;
    esp_err_t e = esp_timer_create(&args, &h);
    if (e != ESP_OK) return e;
    e = esp_timer_start_periodic(h, PUSH_PERIOD_US);
    if (e == ESP_OK) ESP_LOGI(TAG, "telemetry push started (5 Hz)");
    return e;
}
```

- [ ] **Step 2: `main/status_api.c`** — переписать на переиспользование (DRY). Заменить тело `status_get` и убрать локальные `ap_client_rssi`/`ws_fps_since_last_poll` (они теперь в telemetry.c):
```c
#include "status_api.h"
#include <stdio.h>
#include "esp_http_server.h"
#include "esp_log.h"
#include "esp_check.h"
#include "esp_app_desc.h"
#include "http_server.h"
#include "telemetry.h"

static const char *TAG = "status_api";

static esp_err_t status_get(httpd_req_t *req) {
    telemetry_t t;
    telemetry_gather(&t);
    char fields[160];
    if (telemetry_fields(fields, sizeof(fields), &t) < 0) {
        return httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "telemetry");
    }
    const char *fw = esp_app_get_description()->version;
    char buf[224];
    int n = snprintf(buf, sizeof(buf), "{\"device\":\"esp32-car\",\"fw\":\"%s\",%s}", fw, fields);
    if (n < 0 || n >= (int)sizeof(buf)) n = (int)sizeof(buf) - 1;
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

- [ ] **Step 3: `main/main.c`** — `#include "telemetry.h"`; после `ESP_ERROR_CHECK(trim_api_start());` (или после `watchdog_init`) добавить `ESP_ERROR_CHECK(telemetry_start());`.

- [ ] **Step 4: `main/CMakeLists.txt`** — добавить `"telemetry.c"` в SRCS.

- [ ] **Step 5: Build + host tests** (команда из Task 2 Step 3) + `cd test && make run | tail -1`. Expected: `Project build complete` и host-тесты зелёные.

- [ ] **Step 6: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add main/telemetry.c main/status_api.c main/main.c main/CMakeLists.txt
git commit -m "feat: telemetry.c (5 Hz WS push) + /status reuses telemetry builder (DRY)"
```

---

## Task 4: Мок — 5 Гц пуш в `/ws`

**Files:** Modify `tools/mock_car/mock_car.py`.

- [ ] **Step 1:** прочитать текущий ws-хендлер; обернуть приём управления и добавить фоновый пушер
  (сохранить существующий парсинг `t,y`). Каноничный паттерн aiohttp:
```python
import asyncio, json, time

async def ws_handler(request):
    ws = web.WebSocketResponse()
    await ws.prepare(request)

    async def pusher():
        while not ws.closed:
            payload = {
                "rssi": STATE.get("rssi", -58),
                "ws_fps": 10,
                "wdt_trips": STATE.get("wdt_trips", 0),
                "uptime_s": int(time.time() - START_TIME),
                "heap": 200000,
                "calibrated": STATE.get("calibrated", False),
            }
            try:
                await ws.send_str(json.dumps(payload))
            except Exception:
                break
            await asyncio.sleep(0.2)   # 5 Hz

    push_task = asyncio.create_task(pusher())
    try:
        async for msg in ws:
            if msg.type == web.WSMsgType.TEXT:
                # existing control handling: parse "t,y" and apply
                pass
    finally:
        push_task.cancel()
    return ws
```
Добавить `START_TIME = time.time()` в начало (если ещё нет). Сохранить прежнюю обработку входящих `t,y`.

- [ ] **Step 2: Smoke**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/tools/mock_car
pkill -f mock_car.py 2>/dev/null; sleep 1; nohup .venv/bin/python -u mock_car.py >/tmp/mock_car.log 2>&1 & disown; sleep 2
python3 - <<'PY'
import asyncio, aiohttp
async def main():
    async with aiohttp.ClientSession() as s:
        async with s.ws_connect("http://127.0.0.1:8080/ws") as ws:
            for _ in range(3):
                m = await asyncio.wait_for(ws.receive(), timeout=2)
                print("got:", m.data)
asyncio.run(main())
PY
```
Expected: 3 JSON-кадра с `rssi/ws_fps/calibrated` за ~0.6 с.

- [ ] **Step 3: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add tools/mock_car/mock_car.py && git commit -m "feat(tools): mock pushes telemetry over /ws at 5 Hz"
```

---

## Task 5: iOS — приём телеметрии по WS, бутстрап `/status`, свежесть

**Files:** Modify `ios/ESP32Car/ControlModel.swift` (Telemetry struct+parse), `ios/ESP32Car/CarConnection.swift`, `ios/ESP32Car/CarStatus.swift`, `ios/ESP32Car/DriveView.swift`, `ios/ESP32Car/L.swift`, `ios/ESP32Car/Resources/ru.lproj/Localizable.strings`, `ios/ESP32CarTests/ControlModelTests.swift`.

- [ ] **Step 1 (TDD red): `Telemetry` + parse в `ControlModel.swift`** — добавить:
```swift
struct Telemetry {
    var rssi: Int?
    var wsFps: Int?
    var wdtTrips: Int?
    var uptimeS: Int?
    var heap: Int?
    var calibrated: Bool?

    /// Parse a WS telemetry frame; nil if not JSON or missing the core shape.
    static func parse(_ json: String) -> Telemetry? {
        guard let data = json.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        // Require at least one known field so random text isn't accepted.
        guard j["rssi"] != nil || j["uptime_s"] != nil || j["calibrated"] != nil else { return nil }
        var t = Telemetry()
        if let r = j["rssi"] as? Int, r != 0 { t.rssi = r }
        t.wsFps = j["ws_fps"] as? Int
        t.wdtTrips = j["wdt_trips"] as? Int
        t.uptimeS = j["uptime_s"] as? Int
        t.heap = j["heap"] as? Int
        t.calibrated = j["calibrated"] as? Bool
        return t
    }
}
```
Тест-харнесс `/tmp/tele_check.swift`:
```swift
import Foundation
func run() {
    let ok = Telemetry.parse("{\"rssi\":-55,\"ws_fps\":10,\"wdt_trips\":2,\"uptime_s\":123,\"heap\":198000,\"calibrated\":true}")!
    precondition(ok.rssi == -55 && ok.wsFps == 10 && ok.wdtTrips == 2 && ok.uptimeS == 123 && ok.calibrated == true)
    precondition(Telemetry.parse("{\"rssi\":0,\"calibrated\":false}")!.rssi == nil)  // 0 -> nil
    precondition(Telemetry.parse("not json") == nil)
    precondition(Telemetry.parse("{\"foo\":1}") == nil)                              // no known field
    print("telemetry parse: all passed")
}
```
+ `/tmp/tele_main.swift` с `run()`. Запуск:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && swiftc ios/ESP32Car/ControlModel.swift /tmp/tele_check.swift /tmp/tele_main.swift -o /tmp/tele 2>&1 | tail -2 && /tmp/tele
```
Expected: `telemetry parse: all passed`.

- [ ] **Step 2: XCTest-зеркало** — в `ios/ESP32CarTests/ControlModelTests.swift` перед закрывающей `}`:
```swift
    func testTelemetryParse() {
        let ok = Telemetry.parse("{\"rssi\":-55,\"ws_fps\":10,\"wdt_trips\":2,\"uptime_s\":123,\"heap\":198000,\"calibrated\":true}")!
        XCTAssertEqual(ok.rssi, -55); XCTAssertEqual(ok.uptimeS, 123); XCTAssertEqual(ok.calibrated, true)
        XCTAssertNil(Telemetry.parse("{\"rssi\":0}")!.rssi)
        XCTAssertNil(Telemetry.parse("nope"))
        XCTAssertNil(Telemetry.parse("{\"foo\":1}"))
    }
```

- [ ] **Step 3: `CarConnection.swift`** — добавить колбэк и парсинг входящих кадров:
```swift
    /// Called on the main actor for each telemetry frame pushed by the car.
    var onTelemetry: ((Telemetry) -> Void)?
```
В `receive(on:)` ветку `.success` заменить, чтобы парсить текст:
```swift
                switch result {
                case .success(let message):
                    if case .string(let s) = message, let t = Telemetry.parse(s) {
                        self.onTelemetry?(t)
                    }
                    self.receive(on: t2)   // re-arm; see rename note below
                case .failure: self.drop()
                }
```
ВАЖНО: в текущем коде параметр замыкания называется `t` (URLSessionWebSocketTask). Переименовать его в `t2` в сигнатуре `receive(on t2: URLSessionWebSocketTask)` и во всех `self.task === t2` / `self.receive(on: t2)`, чтобы не конфликтовать с `Telemetry t`. (Сделать это согласованно по всему методу `receive`.)

- [ ] **Step 4: `CarStatus.swift`** — заменить сетевой поллинг на бутстрап + apply + свежесть:
```swift
import Foundation

@MainActor
final class CarStatus: ObservableObject {
    @Published var online = false
    @Published var uptimeS: Int?
    @Published var calibrated: Bool?
    @Published var fw: String?
    @Published var rssi: Int?
    @Published var wdtTrips: Int?
    @Published var wsFps: Int?

    private let url = URL(string: CarHost.statusURL)!
    private var freshTimer: Timer?
    private var lastFrame = Date.distantPast
    private let staleAfter: TimeInterval = 1.0

    /// One-shot bootstrap probe: identity + fw + initial calibrated. Then liveness comes from WS.
    func start() {
        bootstrap()
        guard freshTimer == nil else { return }
        freshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.online && Date().timeIntervalSince(self.lastFrame) > self.staleAfter {
                    self.online = false   // WS telemetry went stale → offline
                }
            }
        }
    }

    func stop() { freshTimer?.invalidate(); freshTimer = nil }
    deinit { freshTimer?.invalidate() }

    /// Apply a telemetry frame pushed over WS.
    func apply(_ t: Telemetry) {
        lastFrame = Date()
        online = true
        if let v = t.rssi { rssi = v } else { rssi = nil }
        wsFps = t.wsFps
        wdtTrips = t.wdtTrips
        uptimeS = t.uptimeS
        if let c = t.calibrated { calibrated = c }
    }

    private func bootstrap() {
        var req = URLRequest(url: url)
        req.timeoutInterval = 2
        req.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            var ok = false; var cal: Bool?; var fwv: String?; var up: Int?
            if let data,
               let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               (j["device"] as? String) == "esp32-car" {
                ok = true; cal = j["calibrated"] as? Bool; fwv = j["fw"] as? String; up = j["uptime_s"] as? Int
            }
            Task { @MainActor in
                guard let self else { return }
                if ok { self.online = true; self.calibrated = cal; self.fw = fwv; self.uptimeS = up; self.lastFrame = Date() }
            }
        }.resume()
    }
}
```

- [ ] **Step 5: Строки + L** — `Localizable.strings`: изменить `"drive.connected"` на `"На связи"` (без `%d`). `L.swift`: заменить `static func driveConnected(_ ms: Int) -> String { s("drive.connected", ms) }` на `static var driveConnected: String { s("drive.connected") }`.

- [ ] **Step 6: `DriveView.swift`** — wiring + пилюля:
- В `.onAppear { conn.start(); status.start() }` добавить связывание: сделать `.onAppear { conn.onTelemetry = { status.apply($0) }; conn.start(); status.start() }`.
- `signalLevel` → `ControlModel.signalLevel(online: status.online, rssi: status.rssi, pingMs: nil)`.
- `linkUp` → `status.online` (свежесть уже внутри). Заменить `private var linkUp: Bool { status.online && conn.state == .connected }` на `private var linkUp: Bool { status.online }`.
- Текст пилюли (была `L.driveConnected(status.pingMs ?? 0)`):
```swift
                        Text(linkUp ? L.driveConnected : L.driveSearching)
```

- [ ] **Step 7: Build + grep**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -8
grep -rn '[А-Яа-яЁё]' --include='*.swift' ESP32Car && echo LEAK || echo "(чисто)"
grep -rn "pingMs" --include='*.swift' ESP32Car || echo "(pingMs убран)"
```
Expected: `** BUILD SUCCEEDED **`, кириллица чисто. (`pingMs` может остаться в `signalLevel`-сигнатуре ControlModel — это ок; в CarStatus его быть не должно.)

- [ ] **Step 8: Native parse re-run** — `swiftc ... && /tmp/tele` → `telemetry parse: all passed`.

- [ ] **Step 9: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/ControlModel.swift ios/ESP32Car/CarConnection.swift ios/ESP32Car/CarStatus.swift ios/ESP32Car/DriveView.swift ios/ESP32Car/L.swift ios/ESP32Car/Resources ios/ESP32CarTests/ControlModelTests.swift
git commit -m "feat(ios): receive telemetry over WS, bootstrap /status once, freshness liveness"
```

---

## Task 6: Проверка в симуляторе

- [ ] **Step 1:** host-тесты (`make run`, 8 зелёных) + `idf.py build` чисто.
- [ ] **Step 2:** мок (с 5 Гц пушем) запущен, `POST /calib/save` (calibrated=true). Продакшн-сборка
  в симулятор → главный экран: «На связи», палочки по RSSI, uptime/телеметрия **живые** (растут) —
  и это **без** `/status`-поллинга (проверить в `/tmp/mock_car.log`, что `/status` дёрнулся ~1 раз).
  Скриншот `/tmp/tele_drive.png`.
- [ ] **Step 3:** убить мок на ходу → апп уходит в офлайн за ~1 с (свежесть); поднять мок → снова живой.
- [ ] **Step 4:** дерево чистое, продакшн в симуляторе.

---

## Self-Review заметки

- **Покрытие спеки:** 5 Гц пуш (telemetry.c PUSH_PERIOD_US=200000, T3); WS-кадр JSON живых полей
  (telemetry_fields, T1); сокет клиента + async send (T2); DRY `/status`↔WS (telemetry_gather+fields, T3);
  бутстрап один раз + поллинг убран (CarStatus.start/bootstrap, T5); свежесть → online (freshTimer, T5);
  пилюля «На связи»/«Поиск» без мс (T5); мок 5 Гц (T4); тесты (T1/T5/T6). Управление/watchdog/REST не тронуты.
- **Тип-консистентность:** `telemetry_t`/`telemetry_fields(buf,n,*t)`/`telemetry_gather`/`telemetry_json`/
  `telemetry_start`; `ws_control_send(data,len)`; iOS `Telemetry.parse`/`CarConnection.onTelemetry`/
  `CarStatus.apply`/`L.driveConnected` (теперь var).
- **Замечания:** `ws_fps_now` static-state делят бутстрап-`/status` (1 раз) и 5 Гц таймер — один глитч-кадр
  на старте, fps косметический. `httpd_ws_send_frame_async` из esp_timer-таска безопасен (ставит в очередь
  httpd). Переименование `t`→`t2` в `receive(on:)` обязательно (конфликт с `Telemetry t`).
