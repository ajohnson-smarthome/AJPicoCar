# Car Dimensions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a «Размеры машинки» screen (track + wheelbase between wheel centres), stored on the car via a new `/dims` endpoint, as a mandatory wizard step 1 and a Settings row; the measured **track** replaces the hardcoded `0.13` in the donut/simulation math.

**Architecture:** Firmware `dims`/`dims_api` mirror `wheel`/`wheel_api` (NVS + `GET/POST /dims`). iOS `DimsClient` + `CarDimensionsView` (animated reference-car diagram + two steppers). The pure donut functions take `trackM` as a parameter; `Tricks.donutTrackFallbackM = 0.13` is the single named fallback used at the `/dims` fetch sites. Wheelbase is stored + drawn only.

**Tech Stack:** ESP-IDF 5.4 (C), SwiftUI (Swift 6), `swiftc` host tests, `enum L` localization, aiohttp mock.

**Spec:** `docs/superpowers/specs/2026-06-17-car-dimensions-design.md`

**Branch:** `feat/car-dimensions`

---

## File Structure

- `main/dims.{c,h}` — **create**: NVS param store (`track_mm`, `wheelbase_mm`), mirror of `wheel.{c,h}`.
- `main/dims_api.{c,h}` — **create**: `GET/POST /dims`, mirror of `wheel_api.{c,h}`.
- `main/CMakeLists.txt`, `main/main.c` — **modify**: register sources + `dims_init()`/`dims_api_start()`.
- `tools/mock_car/mock_car.py` — **modify**: `GET/POST /dims`.
- `ios/ESP32Car/DimsClient.swift` — **create**: `/dims` GET/POST client (mirror `WheelClient`).
- `ios/ESP32Car/Tricks.swift` — **modify**: donut functions take `trackM`; `donutTrackFallbackM`.
- `ios/ESP32CarTests/TrickSimTests.swift` — **modify**: update donut tests + track sensitivity.
- `ios/ESP32Car/TrickSimView.swift`, `DriveView.swift`, `TrickEditorView.swift` — **modify**: thread track.
- `ios/ESP32Car/CarDimsDiagram.swift` — **create**: animated top-down car + dimension lines.
- `ios/ESP32Car/CarDimensionsView.swift` — **create**: the screen (diagram + steppers, wizard).
- `ios/ESP32Car/SettingsView.swift` — **modify**: «Размеры машинки» row above «Колесо и моторы».
- `ios/ESP32Car/L.swift`, `Resources/ru.lproj/Localizable.strings` — **modify**: dims strings.

---

### Task 1: Firmware `dims` module (NVS param store)

**Files:**
- Create: `main/dims.h`, `main/dims.c`
- Modify: `main/CMakeLists.txt`, `main/main.c`

- [ ] **Step 1: Create `main/dims.h`**

```c
#ifndef DIMS_H
#define DIMS_H

#include <stdint.h>

// Distances between wheel centres (mm). Validated by dims_set + the /dims API.
#define DIMS_TRACK_MIN_MM       60
#define DIMS_TRACK_MAX_MM       300
#define DIMS_WHEELBASE_MIN_MM   90
#define DIMS_WHEELBASE_MAX_MM   360

// track_mm = lateral (left↔right wheel centres); wheelbase_mm = longitudinal (front↔rear).
typedef struct {
    uint16_t track_mm;
    uint16_t wheelbase_mm;
} dims_params_t;

// Load from NVS (or defaults: track 130, wheelbase 210). Call once at boot.
void dims_init(void);
// Copy current params out.
void dims_get(dims_params_t *out);
// Validate/clamp and store in RAM (the /dims API persists to NVS).
void dims_set(const dims_params_t *in);

#endif // DIMS_H
```

- [ ] **Step 2: Create `main/dims.c`**

```c
#include "dims.h"
#include "esp_log.h"
#include "nvs.h"

static const char *TAG = "dims";

static dims_params_t s_params = { .track_mm = 130, .wheelbase_mm = 210 };

static uint16_t clamp_u16(uint16_t v, uint16_t lo, uint16_t hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

void dims_set(const dims_params_t *in) {
    if (!in) return;
    s_params.track_mm     = clamp_u16(in->track_mm, DIMS_TRACK_MIN_MM, DIMS_TRACK_MAX_MM);
    s_params.wheelbase_mm = clamp_u16(in->wheelbase_mm, DIMS_WHEELBASE_MIN_MM, DIMS_WHEELBASE_MAX_MM);
}

void dims_get(dims_params_t *out) {
    if (out) *out = s_params;
}

void dims_init(void) {
    nvs_handle_t h;
    if (nvs_open("car", NVS_READONLY, &h) == ESP_OK) {
        uint16_t v;
        if (nvs_get_u16(h, "track_mm", &v) == ESP_OK)     s_params.track_mm = clamp_u16(v, DIMS_TRACK_MIN_MM, DIMS_TRACK_MAX_MM);
        if (nvs_get_u16(h, "wheelbase_mm", &v) == ESP_OK) s_params.wheelbase_mm = clamp_u16(v, DIMS_WHEELBASE_MIN_MM, DIMS_WHEELBASE_MAX_MM);
        nvs_close(h);
    }
    ESP_LOGI(TAG, "dims track=%u mm wheelbase=%u mm", s_params.track_mm, s_params.wheelbase_mm);
}
```

- [ ] **Step 3: Register the source in `main/CMakeLists.txt`**

In the `SRCS` list, append `"dims.c"` right after `"wheel.c"` (before `"wheel_api.c"`):
```
... "telemetry.c" "wheel.c" "dims.c" "wheel_api.c"
```

- [ ] **Step 4: Wire `dims_init()` in `main/main.c`**

Add the include near the others (after `#include "ramp_api.h"` block — anywhere in the include list):
```c
#include "dims.h"
```
And call `dims_init()` right after the existing `wheel_init();` line:
```c
    wheel_init();                          // load wheel/encoder params (NVS or defaults)
    dims_init();                           // load car dimensions (NVS or defaults)
```

- [ ] **Step 5: Verify it compiles (host syntax check — no full IDF build needed here)**

Run: `cd /Users/adamjohnson/VSCode/esp32-p4-car && cc -fsyntax-only -I main main/dims.c 2>&1 | head -5 || echo "note: needs IDF headers (nvs.h/esp_log.h) — a full idf.py build verifies; syntax of dims.c logic is self-contained"`
Expected: errors only about missing `nvs.h`/`esp_log.h` (IDF headers), NOT about the dims logic. (The board build in Task 13 is the real gate.)

- [ ] **Step 6: Commit**

```bash
git add main/dims.h main/dims.c main/CMakeLists.txt main/main.c
git commit -m "feat(fw): dims module — NVS track/wheelbase param store"
```

---

### Task 2: Firmware `dims_api` (`GET/POST /dims`)

**Files:**
- Create: `main/dims_api.h`, `main/dims_api.c`
- Modify: `main/CMakeLists.txt`, `main/main.c`

- [ ] **Step 1: Create `main/dims_api.h`**

```c
#ifndef DIMS_API_H
#define DIMS_API_H

#include "esp_err.h"

// Register GET/POST /dims on the shared httpd. Call after http_server_start().
esp_err_t dims_api_start(void);

#endif // DIMS_API_H
```

- [ ] **Step 2: Create `main/dims_api.c`**

```c
#include "dims_api.h"
#include <stdio.h>
#include "esp_http_server.h"
#include "esp_log.h"
#include "esp_check.h"
#include "nvs.h"
#include "http_server.h"
#include "dims.h"

static const char *TAG = "dims_api";

static esp_err_t dims_get_handler(httpd_req_t *req) {
    dims_params_t d;
    dims_get(&d);
    char buf[64];
    int n = snprintf(buf, sizeof(buf),
                     "{\"track_mm\":%u,\"wheelbase_mm\":%u}", d.track_mm, d.wheelbase_mm);
    httpd_resp_set_type(req, "application/json");
    return httpd_resp_send(req, buf, n);
}

static esp_err_t dims_post_handler(httpd_req_t *req) {
    char body[32] = {0};
    int len = httpd_req_recv(req, body, sizeof(body) - 1);
    if (len <= 0) return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "empty");
    // Body is two ints: "<track_mm> <wheelbase_mm>" (no JSON parser dependency).
    int track = -1, base = -1;
    if (sscanf(body, "%d %d", &track, &base) != 2 ||
        track < DIMS_TRACK_MIN_MM || track > DIMS_TRACK_MAX_MM ||
        base < DIMS_WHEELBASE_MIN_MM || base > DIMS_WHEELBASE_MAX_MM) {
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "need: <60..300> <90..360>");
    }
    dims_params_t d = { .track_mm = (uint16_t)track, .wheelbase_mm = (uint16_t)base };
    dims_set(&d);
    nvs_handle_t h;
    if (nvs_open("car", NVS_READWRITE, &h) == ESP_OK) {
        nvs_set_u16(h, "track_mm", d.track_mm);
        nvs_set_u16(h, "wheelbase_mm", d.wheelbase_mm);
        esp_err_t e = nvs_commit(h);
        if (e != ESP_OK) ESP_LOGW(TAG, "dims save failed: %s", esp_err_to_name(e));
        nvs_close(h);
    }
    return httpd_resp_sendstr(req, "ok");
}

esp_err_t dims_api_start(void) {
    httpd_handle_t server = http_server_get_handle();
    if (server == NULL) { ESP_LOGE(TAG, "http server not started"); return ESP_FAIL; }
    httpd_uri_t g = { .uri = "/dims", .method = HTTP_GET,  .handler = dims_get_handler };
    httpd_uri_t p = { .uri = "/dims", .method = HTTP_POST, .handler = dims_post_handler };
    ESP_RETURN_ON_ERROR(httpd_register_uri_handler(server, &g), TAG, "reg GET /dims");
    ESP_RETURN_ON_ERROR(httpd_register_uri_handler(server, &p), TAG, "reg POST /dims");
    return ESP_OK;
}
```

- [ ] **Step 3: Register the source in `main/CMakeLists.txt`**

Append `"dims_api.c"` right after `"wheel_api.c"`:
```
... "wheel.c" "dims.c" "wheel_api.c" "dims_api.c"
```

- [ ] **Step 4: Wire `dims_api_start()` in `main/main.c`**

Add the include:
```c
#include "dims_api.h"
```
And call it right after the existing `ESP_ERROR_CHECK(wheel_api_start());` line:
```c
    ESP_ERROR_CHECK(wheel_api_start());
    ESP_ERROR_CHECK(dims_api_start());
```

(Handler count 15 → 17, under the `max_uri_handlers = 20` limit.)

- [ ] **Step 5: Commit**

```bash
git add main/dims_api.h main/dims_api.c main/CMakeLists.txt main/main.c
git commit -m "feat(fw): GET/POST /dims endpoint (track/wheelbase, NVS)"
```

---

### Task 3: Mock car `/dims`

**Files:**
- Modify: `tools/mock_car/mock_car.py`

- [ ] **Step 1: Add the `/dims` state + handlers**

Find the `STATE` dict (it contains a `"wheel"` entry) and add a `"dims"` entry alongside it:
```python
    "dims": {"track_mm": 130, "wheelbase_mm": 210},
```
Add these handlers right after `wheel_post`:
```python
async def dims_get(request):
    return web.json_response(STATE["dims"])


async def dims_post(request):
    body = (await request.text()).strip()
    try:
        track, base = (int(x) for x in body.split())
        if not (60 <= track <= 300 and 90 <= base <= 360):
            raise ValueError
    except ValueError:
        return web.Response(status=400, text="need: <track> <wheelbase>")
    STATE["dims"] = {"track_mm": track, "wheelbase_mm": base}
    print(f"dims: {STATE['dims']}")
    return web.Response(text="ok")
```
Add the routes in `app.add_routes([...])` after the `/wheel` routes:
```python
        web.get("/dims", dims_get),
        web.post("/dims", dims_post),
```
And update the startup print line to mention `/dims`:
```python
    print("mock car on http://127.0.0.1:8080  (/status, /ws, /calib*, /ramp, /trim, /wheel, /dims, /ota)")
```

- [ ] **Step 2: Verify the mock starts**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/tools/mock_car
pkill -f mock_car.py 2>/dev/null; sleep 1
nohup .venv/bin/python -u mock_car.py >/tmp/mock_car.log 2>&1 & sleep 2
curl -s http://127.0.0.1:8080/dims
```
Expected: `{"track_mm": 130, "wheelbase_mm": 210}`

- [ ] **Step 3: Commit**

```bash
git add tools/mock_car/mock_car.py
git commit -m "test(mock): serve GET/POST /dims"
```

---

### Task 4: iOS `DimsClient`

**Files:**
- Create: `ios/ESP32Car/DimsClient.swift`

- [ ] **Step 1: Create `ios/ESP32Car/DimsClient.swift`**

```swift
import Foundation

/// Reads/writes the car's physical dimensions via GET/POST /dims.
/// GET returns JSON; POST sends two space-separated ints (mirrors the firmware).
struct DimsClient {
    struct Params: Equatable {
        var trackMm: Int
        var wheelbaseMm: Int
    }

    func get() async -> Params? {
        guard let url = URL(string: CarHost.httpBase + "/dims") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let track = j["track_mm"] as? Int,
              let base = j["wheelbase_mm"] as? Int else { return nil }
        return Params(trackMm: track, wheelbaseMm: base)
    }

    @discardableResult
    func set(_ p: Params) async -> Bool {
        guard let url = URL(string: CarHost.httpBase + "/dims") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = "\(p.trackMm) \(p.wheelbaseMm)".data(using: .utf8)
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add ios/ESP32Car/DimsClient.swift
git commit -m "feat(ios): DimsClient — GET/POST /dims"
```

---

### Task 5: Localization for the dimensions screen

**Files:**
- Modify: `ios/ESP32Car/Resources/ru.lproj/Localizable.strings`, `ios/ESP32Car/L.swift`

- [ ] **Step 1: Add the strings** (append after the `wheel.*` block in `Localizable.strings`)

```
"dims.title"          = "Размеры машинки";
"dims.track"          = "Колея";
"dims.base"           = "База";
"dims.trackHint"      = "поперёк";
"dims.baseHint"       = "вдоль";
```

- [ ] **Step 2: Add the accessors** to `L.swift` (after the `wheelNext` accessor)

```swift
    static var dimsTitle: String { s("dims.title") }
    static var dimsTrack: String { s("dims.track") }
    static var dimsBase: String { s("dims.base") }
    static var dimsTrackHint: String { s("dims.trackHint") }
    static var dimsBaseHint: String { s("dims.baseHint") }
```

(The wizard step indicator reuses the existing generic `L.wheelStep(_:_:)` = «шаг %d из %d».)

- [ ] **Step 3: Commit**

```bash
git add ios/ESP32Car/L.swift ios/ESP32Car/Resources/ru.lproj/Localizable.strings
git commit -m "feat(ios): localization for the car-dimensions screen"
```

---

### Task 6: Thread `trackM` through the donut math + callers

**Files:**
- Modify: `ios/ESP32Car/Tricks.swift`, `ios/ESP32CarTests/TrickSimTests.swift`,
  `ios/ESP32Car/TrickSimView.swift`, `ios/ESP32Car/DriveView.swift`, `ios/ESP32Car/TrickEditorView.swift`

This task is one cohesive refactor (the pure signature change forces all callers), verified by BOTH the
swiftc host tests and an `xcodebuild`. Commit once at the end.

- [ ] **Step 1: Update the host-test driver `/tmp/main.swift`** (pass `trackM`, add a sensitivity check)

```swift
import Foundation
func approx(_ a: Double, _ b: Double, _ tol: Double, _ w: String) { assert(abs(a - b) <= tol, "\(w): \(a) vs \(b)") }
let T = Tricks.donutTrackFallbackM   // 0.13, the default track
// Round-trip at the default track: simulate the timed donut → swept revolutions ≈ requested.
for v in [0.4, 0.578, 0.9] {
    for diaCm in [30.0, 50.0, 120.0] {
        for n in [1, 2, 5] {
            let trick = Tricks.donutTrick(diameterCm: diaCm, circles: n, vmaxMS: v, trackM: T)
            let r = TrickSim.simulate(steps: trick.steps, vmaxMS: v, trackM: T, carLenM: 0.25, carWidM: 0.15)
            approx(r.turnRad / (2 * Double.pi), Double(n), 0.05, "rev d\(diaCm) n\(n) v\(v)")
        }
    }
}
// Default-track ms unchanged from before (50 cm, nominal vmax, 2 circles).
let y50 = Tricks.donutSides(diameterCm: 50, trackM: T).y
assert(Tricks.donutDurationMs(circles: 2, y: y50, vmaxMS: Tricks.donutNominalVmaxMS, trackM: T) == 6848, "ms")
// Track sensitivity: a narrower track → a different side ratio for the same diameter,
// and the round-trip radius scales with the supplied track.
assert(Tricks.donutSides(diameterCm: 50, trackM: 0.10).y != Tricks.donutSides(diameterCm: 50, trackM: 0.13).y, "tk-sides")
for tk in [0.10, 0.13, 0.16] {
    let s = Tricks.donutSides(diameterCm: 60, trackM: tk)
    let sides = ControlModel.sides(t: s.t, y: s.y)
    let R = tk * (sides.left + sides.right) / (2 * (sides.left - sides.right))
    approx(R, 0.60 / 2, 0.01, "R tk\(tk)")
}
// donutDurationMs scales linearly with track.
assert(Tricks.donutDurationMs(circles: 1, y: 0.2, vmaxMS: 0.5, trackM: 0.26)
       == 2 * Tricks.donutDurationMs(circles: 1, y: 0.2, vmaxMS: 0.5, trackM: 0.13), "ms-linear")
print("donut track: all passed")
```

- [ ] **Step 2: Run it to verify it FAILS (old signatures)**

Run: `cd /Users/adamjohnson/VSCode/esp32-p4-car && swiftc ios/ESP32Car/ControlModel.swift ios/ESP32Car/TrickSim.swift ios/ESP32Car/Tricks.swift /tmp/main.swift -o /tmp/dt`
Expected: FAIL — `donutSides`/`donutTrick`/`donutDurationMs` don't accept `trackM`; `donutTrackFallbackM` undefined.

- [ ] **Step 3: Edit `ios/ESP32Car/Tricks.swift`** — track becomes a parameter

Replace the constant line:
```swift
    static let donutTrackM = 0.13
```
with:
```swift
    /// Assumed track (m) while /dims is unavailable (pre-fetch / offline). Equals the firmware
    /// default (130 mm). The pure donut functions take `trackM` explicitly — this is only the
    /// fallback supplied at the fetch sites.
    static let donutTrackFallbackM = 0.13
```
Replace `donutSides`:
```swift
    static func donutSides(diameterCm: Double) -> (t: Double, y: Double) {
        let R = Swift.max(0.001, diameterCm / 100 / 2)
        let T = donutTrackM
        var r = (2 * R - T) / (2 * R + T)
        r = Swift.min(0.9, Swift.max(0.0, r))
        return ((1 + r) / 2, (1 - r) / 2)
    }
```
with:
```swift
    static func donutSides(diameterCm: Double, trackM: Double) -> (t: Double, y: Double) {
        let R = Swift.max(0.001, diameterCm / 100 / 2)
        let T = trackM
        var r = (2 * R - T) / (2 * R + T)
        r = Swift.min(0.9, Swift.max(0.0, r))
        return ((1 + r) / 2, (1 - r) / 2)
    }
```
Delete the no-circles `donutTrick(diameterCm:)` overload entirely (the editor no longer uses it):
```swift
    /// The donut maneuver for a given circle diameter — same id/name/icon, the single step's
    /// (t, y) derived from `donutSides`. Real duration is layered on by `withDurations`.
    static func donutTrick(diameterCm: Double) -> Trick {
        let (t, y) = donutSides(diameterCm: diameterCm)
        return Trick(id: donut.id, nameKey: donut.nameKey, icon: donut.icon,
                     steps: [TrickStep(t: t, y: y, ms: 5000)])
    }
```
Replace `donutDurationMs`:
```swift
    static func donutDurationMs(circles: Int, y: Double, vmaxMS: Double) -> Int {
        guard vmaxMS > 0, y > 0 else { return 0 }
        let n = Double(Swift.max(donutCirclesMin, circles))
        return Int((1000 * n * Double.pi * donutTrackM / (vmaxMS * y)).rounded())
    }
```
with:
```swift
    static func donutDurationMs(circles: Int, y: Double, vmaxMS: Double, trackM: Double) -> Int {
        guard vmaxMS > 0, y > 0 else { return 0 }
        let n = Double(Swift.max(donutCirclesMin, circles))
        return Int((1000 * n * Double.pi * trackM / (vmaxMS * y)).rounded())
    }
```
Replace the circles `donutTrick`:
```swift
    static func donutTrick(diameterCm: Double, circles: Int, vmaxMS: Double) -> Trick {
        let (t, y) = donutSides(diameterCm: diameterCm)
        let ms = donutDurationMs(circles: circles, y: y, vmaxMS: vmaxMS)
        return Trick(id: donut.id, nameKey: donut.nameKey, icon: donut.icon,
                     steps: [TrickStep(t: t, y: y, ms: ms)])
    }
```
with:
```swift
    static func donutTrick(diameterCm: Double, circles: Int, vmaxMS: Double, trackM: Double) -> Trick {
        let (t, y) = donutSides(diameterCm: diameterCm, trackM: trackM)
        let ms = donutDurationMs(circles: circles, y: y, vmaxMS: vmaxMS, trackM: trackM)
        return Trick(id: donut.id, nameKey: donut.nameKey, icon: donut.icon,
                     steps: [TrickStep(t: t, y: y, ms: ms)])
    }
```

- [ ] **Step 4: Run the host check to verify it PASSES**

Run: `cd /Users/adamjohnson/VSCode/esp32-p4-car && swiftc ios/ESP32Car/ControlModel.swift ios/ESP32Car/TrickSim.swift ios/ESP32Car/Tricks.swift /tmp/main.swift -o /tmp/dt && /tmp/dt`
Expected: `donut track: all passed`

- [ ] **Step 5: Update XCTest in `ios/ESP32CarTests/TrickSimTests.swift`**

Replace the three donut methods (`testDonutCirclesRoundTrip`, `testDonutDurationGuards`, `testDonutTrickCircles`)
and the diameter-era `testDonutSidesRoundTrip`/`testDonutTrick` with these (all pass `trackM`; the
no-circles `donutTrick` is gone):
```swift
    func testDonutSidesRoundTrip() {
        let T = Tricks.donutTrackFallbackM
        let d = Tricks.donutSides(diameterCm: 50, trackM: T)
        XCTAssertEqual(d.t, 0.794, accuracy: 0.01)
        XCTAssertEqual(d.y, 0.206, accuracy: 0.01)
        for diaCm in [30.0, 60.0, 120.0] {
            let s = Tricks.donutSides(diameterCm: diaCm, trackM: T)
            let sides = ControlModel.sides(t: s.t, y: s.y)
            let R = T * (sides.left + sides.right) / (2 * (sides.left - sides.right))
            XCTAssertEqual(R, diaCm / 100 / 2, accuracy: 0.005)
        }
    }
    func testDonutTrackSensitivity() {
        XCTAssertNotEqual(Tricks.donutSides(diameterCm: 50, trackM: 0.10).y,
                          Tricks.donutSides(diameterCm: 50, trackM: 0.13).y)
        for tk in [0.10, 0.13, 0.16] {
            let s = Tricks.donutSides(diameterCm: 60, trackM: tk)
            let sides = ControlModel.sides(t: s.t, y: s.y)
            let R = tk * (sides.left + sides.right) / (2 * (sides.left - sides.right))
            XCTAssertEqual(R, 0.30, accuracy: 0.01)
        }
    }
    func testDonutCirclesRoundTrip() {
        for v in [0.4, 0.578, 0.9] {
            for diaCm in [30.0, 50.0, 120.0] {
                for n in [1, 2, 5] {
                    let trick = Tricks.donutTrick(diameterCm: diaCm, circles: n, vmaxMS: v,
                                                  trackM: Tricks.donutTrackFallbackM)
                    let r = TrickSim.simulate(steps: trick.steps, vmaxMS: v,
                                              trackM: Tricks.donutTrackFallbackM, carLenM: 0.25, carWidM: 0.15)
                    XCTAssertEqual(r.turnRad / (2 * Double.pi), Double(n), accuracy: 0.05)
                }
            }
        }
    }
    func testDonutDurationGuards() {
        let T = Tricks.donutTrackFallbackM
        let y50 = Tricks.donutSides(diameterCm: 50, trackM: T).y
        XCTAssertEqual(Tricks.donutDurationMs(circles: 2, y: y50, vmaxMS: Tricks.donutNominalVmaxMS, trackM: T), 6848)
        XCTAssertEqual(Tricks.donutDurationMs(circles: 2, y: 0.2, vmaxMS: 0, trackM: T), 0)
        XCTAssertEqual(Tricks.donutDurationMs(circles: 2, y: 0, vmaxMS: 0.5, trackM: T), 0)
        XCTAssertEqual(Tricks.donutDurationMs(circles: 1, y: 0.2, vmaxMS: 0.5, trackM: 0.26),
                       2 * Tricks.donutDurationMs(circles: 1, y: 0.2, vmaxMS: 0.5, trackM: 0.13))
    }
    func testDonutTrickCircles() {
        let t = Tricks.donutTrick(diameterCm: 50, circles: 2, vmaxMS: 0.578, trackM: Tricks.donutTrackFallbackM)
        XCTAssertEqual(t.id, Tricks.donut.id)
        XCTAssertEqual(t.steps.count, 1)
    }
```

- [ ] **Step 6: Update `ios/ESP32Car/TrickSimView.swift`** — fetch `/dims`, build the donut from values

Change the stored properties (add `donutDiameterCm` + a `track` state):
```swift
    let trick: Trick
    let durs: [Int]
    let palette: Palette
    var donutDiameterCm: Double? = nil
    var donutCircles: Int? = nil
    @State private var wheel: WheelClient.Params?
    @State private var track = Tricks.donutTrackFallbackM
```
Replace `steps` (build the whole donut step from diameter+circles+track+vmax):
```swift
    private var steps: [TrickStep] {
        if trick.id == Tricks.donut.id, let dia = donutDiameterCm, let n = donutCircles, let v = vmaxMS {
            return Tricks.donutTrick(diameterCm: dia, circles: n, vmaxMS: v, trackM: track).steps
        }
        let d = durs.isEmpty ? Tricks.baseDurations(trick) : durs
        return Tricks.withDurations(trick, d).steps
    }
```
Replace the `sim` `trackM:` argument to use the fetched track:
```swift
    private var sim: TrickSim.Result? {
        guard let v = vmaxMS else { return nil }
        return TrickSim.simulate(steps: steps, vmaxMS: v, trackM: track,
                                 carLenM: Self.carLenM, carWidM: Self.carWidM)
    }
```
And extend the `.task` that loads `/wheel` to also load `/dims` (find `.task { wheel = await WheelClient().get() }` and replace it):
```swift
        .task {
            wheel = await WheelClient().get()
            if let d = await DimsClient().get() { track = Double(d.trackMm) / 1000 }
        }
```

- [ ] **Step 7: Update `ios/ESP32Car/DriveView.swift`** — track from `/dims` for the streamed donut

In `startTrick(_:)`, the donut branch currently builds:
```swift
                let vmax = await donutVmaxMS()
                if Task.isCancelled { return }                 // cancelled during the /wheel fetch → bail cleanly
                trick = Tricks.donutTrick(diameterCm: Double(TrickSettings.donutDiameterCm()),
                                          circles: TrickSettings.donutCircles(), vmaxMS: vmax)
```
Replace with (also fetch the track):
```swift
                let vmax = await donutVmaxMS()
                let track = await donutTrackM()
                if Task.isCancelled { return }                 // cancelled during the fetches → bail cleanly
                trick = Tricks.donutTrick(diameterCm: Double(TrickSettings.donutDiameterCm()),
                                          circles: TrickSettings.donutCircles(), vmaxMS: vmax, trackM: track)
```
And add this helper right after the existing `donutVmaxMS()` function:
```swift
    /// Track (m) from the car's /dims, with the nominal fallback.
    private func donutTrackM() async -> Double {
        guard let d = await DimsClient().get() else { return Tricks.donutTrackFallbackM }
        return Double(d.trackMm) / 1000
    }
```

- [ ] **Step 8: Update `ios/ESP32Car/TrickEditorView.swift`** — pass diameter + circles (not a pre-built trick)

Find the donut-branch `TrickSimView(...)` call:
```swift
                            TrickSimView(trick: Tricks.donutTrick(diameterCm: Double(diameterCm)),
                                         durs: durs, palette: p, donutCircles: circles)
```
Replace with:
```swift
                            TrickSimView(trick: Tricks.donut, durs: durs, palette: p,
                                         donutDiameterCm: Double(diameterCm), donutCircles: circles)
```

- [ ] **Step 9: Build the iOS target**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate >/dev/null
xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -6
```
Expected: `** BUILD SUCCEEDED **`. Fix any compile error minimally and report it.

- [ ] **Step 10: Commit**

```bash
git add ios/ESP32Car/Tricks.swift ios/ESP32CarTests/TrickSimTests.swift ios/ESP32Car/TrickSimView.swift ios/ESP32Car/DriveView.swift ios/ESP32Car/TrickEditorView.swift
git commit -m "feat(ios): donut/sim use the measured track from /dims (fallback 0.13)"
```

---

### Task 7: `CarDimsDiagram` — animated top-down car + dimension lines

**Files:**
- Create: `ios/ESP32Car/CarDimsDiagram.swift`

- [ ] **Step 1: Create `ios/ESP32Car/CarDimsDiagram.swift`**

```swift
import SwiftUI

/// Top-down car sized from track (lateral, mm) + wheelbase (longitudinal, mm), with dimension
/// lines + labels between the wheel centres. Same silhouette/style as DriveDiagram (rounded body,
/// dark corner wheels with a chevron tread, windshield strip at the front). Wheels + body animate
/// when a value changes; the default 130/210 renders the canonical 36×74 silhouette.
struct CarDimsDiagram: View {
    let trackMm: Int
    let wheelbaseMm: Int
    let palette: Palette
    private var p: Palette { palette }

    // DriveDiagram reference proportions, scaled by K. The default 130/210 maps onto wheel
    // track 38 / wheelbase 42 and body 36×74, so it matches the on-screen car.
    private let K = 1.5
    private var trackPx: Double { Double(trackMm) * (38.0 / 130.0) * K }
    private var basePx: Double  { Double(wheelbaseMm) * (42.0 / 210.0) * K }
    private var bodyW: Double   { trackPx * (36.0 / 38.0) }
    private var bodyL: Double   { basePx * (74.0 / 42.0) }
    private var wheelW: Double  { 12.0 * K }
    private var wheelH: Double  { 20.0 * K }

    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2, cy = geo.size.height / 2
            let tHalf = trackPx / 2, bHalf = basePx / 2
            ZStack {
                // wheels (under the body) at the 4 wheel-centres
                ForEach(0..<4, id: \.self) { i in
                    wheel
                        .position(x: cx + (i % 2 == 0 ? -tHalf : tHalf),
                                  y: cy + (i < 2 ? -bHalf : bHalf))
                }
                // body + windshield
                RoundedRectangle(cornerRadius: bodyW * 11 / 36)
                    .fill(p.panel)
                    .overlay(RoundedRectangle(cornerRadius: bodyW * 11 / 36).stroke(p.metal, lineWidth: 1.5))
                    .frame(width: bodyW, height: bodyL)
                    .position(x: cx, y: cy)
                RoundedRectangle(cornerRadius: 3)
                    .fill(p.bg.opacity(0.85))
                    .frame(width: bodyW * 22 / 36, height: bodyL * 9 / 74)
                    .position(x: cx, y: cy - bodyL / 2 + bodyL * 11 / 74)
                // wheel-centre dots
                ForEach(0..<4, id: \.self) { i in
                    Circle().fill(p.accent).frame(width: 5, height: 5)
                        .position(x: cx + (i % 2 == 0 ? -tHalf : tHalf),
                                  y: cy + (i < 2 ? -bHalf : bHalf))
                }
                // TRACK dimension (above the car)
                dimLine(horizontal: true, length: trackPx, color: p.accent)
                    .position(x: cx, y: cy - bHalf - wheelH / 2 - 16)
                label("\(L.dimsTrack) \(trackMm) \(L.mmUnit)", color: p.accent)
                    .position(x: cx, y: cy - bHalf - wheelH / 2 - 28)
                // BASE dimension (right of the car)
                dimLine(horizontal: false, length: basePx, color: p.metal.opacity(0.9))
                    .position(x: cx + bodyW / 2 + 22, y: cy)
                label("\(L.dimsBase) \(wheelbaseMm) \(L.mmUnit)", color: p.metal.opacity(0.9))
                    .rotationEffect(.degrees(90))
                    .position(x: cx + bodyW / 2 + 38, y: cy)
            }
            .animation(.easeInOut(duration: 0.28), value: trackMm)
            .animation(.easeInOut(duration: 0.28), value: wheelbaseMm)
        }
        .frame(height: 220)
    }

    private var wheel: some View {
        Canvas { ctx, size in
            let wp = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 3)
            ctx.fill(wp, with: .color(.black.opacity(0.85)))
            ctx.stroke(wp, with: .color(p.metal), lineWidth: 1)
            for oy in [size.height * 0.32, size.height * 0.62] {
                var c = Path()
                c.move(to: CGPoint(x: size.width * 0.2, y: oy + 3))
                c.addLine(to: CGPoint(x: size.width * 0.5, y: oy - 2))
                c.addLine(to: CGPoint(x: size.width * 0.8, y: oy + 3))
                ctx.stroke(c, with: .color(p.bg), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: wheelW, height: wheelH)
    }

    /// A dimension bar (capped line). `horizontal` → width=length, else height=length.
    private func dimLine(horizontal: Bool, length: Double, color: Color) -> some View {
        ZStack {
            Rectangle().fill(color)
                .frame(width: horizontal ? length : 1.5, height: horizontal ? 1.5 : length)
            // end caps
            Rectangle().fill(color).frame(width: horizontal ? 1.5 : 8, height: horizontal ? 8 : 1.5)
                .offset(x: horizontal ? -length / 2 : 0, y: horizontal ? 0 : -length / 2)
            Rectangle().fill(color).frame(width: horizontal ? 1.5 : 8, height: horizontal ? 8 : 1.5)
                .offset(x: horizontal ? length / 2 : 0, y: horizontal ? 0 : length / 2)
        }
    }

    private func label(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 13, weight: .bold)).foregroundStyle(color).monospacedDigit()
    }
}
```

- [ ] **Step 2: Build the iOS target**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate >/dev/null
xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -4
```
Expected: `** BUILD SUCCEEDED **` (the view is unused for now — it compiles standalone).

- [ ] **Step 3: Commit**

```bash
git add ios/ESP32Car/CarDimsDiagram.swift
git commit -m "feat(ios): CarDimsDiagram — animated top-down car with dimension lines"
```

---

### Task 8: `CarDimensionsView` — the screen (diagram + steppers, wizard)

**Files:**
- Create: `ios/ESP32Car/CarDimensionsView.swift`

- [ ] **Step 1: Create `ios/ESP32Car/CarDimensionsView.swift`**

```swift
import SwiftUI

/// «Размеры машинки» — track + wheelbase between wheel centres, stored on the car via /dims.
/// Two uses: a Settings menu item (wizard == false, back chevron) and step 1 of the mandatory
/// calibration wizard (wizard == true, "Далее" → WheelParamsView). No system nav bar (matches
/// SplitScreen siblings) — draws its own header. The track feeds the donut/simulation math.
struct CarDimensionsView: View {
    let palette: Palette
    var wizard: Bool = false
    @Environment(\.dismiss) private var dismiss
    private var p: Palette { palette }

    @State private var trackMm = 130
    @State private var wheelbaseMm = 210
    @State private var lastSaved: DimsClient.Params?

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 18) {
                        CarDimsDiagram(trackMm: trackMm, wheelbaseMm: wheelbaseMm, palette: p)
                            .padding(.top, 4)
                        card
                    }
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 20)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if let d = await DimsClient().get() {
                trackMm = d.trackMm; wheelbaseMm = d.wheelbaseMm; lastSaved = d
            }
        }
    }

    private var header: some View {
        HStack {
            if wizard {
                Text(L.wheelStep(1, 3)).font(.system(size: 13)).foregroundStyle(p.muted)
                    .frame(width: 70, alignment: .leading)
            } else {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(p.accent).frame(width: 70, alignment: .leading)
            }
            Spacer()
            Text(L.dimsTitle).font(.system(size: 17, weight: .semibold)).foregroundStyle(p.text)
            Spacer()
            Group {
                if wizard {
                    NavigationLink { WheelParamsView(palette: p, wizard: true) } label: {
                        Text(L.wheelNext).font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(p.accent)
                } else {
                    Color.clear.frame(width: 70, height: 1)
                }
            }
            .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)
    }

    private var card: some View {
        VStack(spacing: 0) {
            stepperRow(L.dimsTrack, L.dimsTrackHint, value: $trackMm, range: 60...300)
            Rectangle().fill(p.metal.opacity(0.25)).frame(height: 1)
            stepperRow(L.dimsBase, L.dimsBaseHint, value: $wheelbaseMm, range: 90...360)
        }
        .background(p.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(p.metal.opacity(0.4), lineWidth: 1))
    }

    private func stepperRow(_ title: String, _ hint: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14)).foregroundStyle(p.text)
                Text(hint).font(.system(size: 11)).foregroundStyle(p.muted)
            }
            Spacer()
            stepButton("minus") { value.wrappedValue = Swift.max(range.lowerBound, value.wrappedValue - 5); save() }
                .disabled(value.wrappedValue <= range.lowerBound)
            Text("\(value.wrappedValue) \(L.mmUnit)").font(.system(size: 15, weight: .semibold))
                .foregroundStyle(p.accent).monospacedDigit().frame(width: 72)
            stepButton("plus") { value.wrappedValue = Swift.min(range.upperBound, value.wrappedValue + 5); save() }
                .disabled(value.wrappedValue >= range.upperBound)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private func stepButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(p.accent).frame(width: 38, height: 32)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(p.accent.opacity(0.4)))
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let pms = DimsClient.Params(trackMm: trackMm, wheelbaseMm: wheelbaseMm)
        guard pms != lastSaved else { return }
        lastSaved = pms
        Task { await DimsClient().set(pms) }
    }
}
```

- [ ] **Step 2: Build the iOS target**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate >/dev/null
xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -4
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/ESP32Car/CarDimensionsView.swift
git commit -m "feat(ios): CarDimensionsView — track/wheelbase steppers + live diagram"
```

---

### Task 9: Wizard wiring + Settings row

**Files:**
- Modify: `ios/ESP32Car/DriveView.swift`, `ios/ESP32Car/WheelParamsView.swift`, `ios/ESP32Car/SettingsView.swift`

- [ ] **Step 1: Make the mandatory sheet start at the dimensions step (`DriveView`)**

Find the sheet content:
```swift
        .sheet(isPresented: $showCalib) {
            NavigationStack {
                WheelParamsView(palette: p, wizard: true)   // step 1 → "Далее" → CalibrationView
            }
            .interactiveDismissDisabled(true)
        }
```
Replace the inner view with the dimensions step (now step 1 of 3):
```swift
        .sheet(isPresented: $showCalib) {
            NavigationStack {
                CarDimensionsView(palette: p, wizard: true)  // step 1 → Wheel → Calibration
            }
            .interactiveDismissDisabled(true)
        }
```

- [ ] **Step 2: Bump the wheel step indicator to 2 of 3 (`WheelParamsView`)**

In `ios/ESP32Car/WheelParamsView.swift`, change the wizard step label:
```swift
                Text(L.wheelStep(1, 2)).font(.system(size: 13)).foregroundStyle(p.muted)
```
to:
```swift
                Text(L.wheelStep(2, 3)).font(.system(size: 13)).foregroundStyle(p.muted)
```

- [ ] **Step 3: Add the Settings row above «Колесо и моторы» (`SettingsView`)**

In `ios/ESP32Car/SettingsView.swift`, in the first `Section` (the `settingsGroupSetup` one), add this
`NavigationLink` immediately BEFORE the existing `WheelParamsView` link:
```swift
                        NavigationLink {
                            CarDimensionsView(palette: palette)
                        } label: {
                            Label(L.dimsTitle, systemImage: "ruler")
                                .foregroundStyle(palette.text)
                        }
                        .listRowBackground(palette.panel)
```

- [ ] **Step 4: Build the iOS target**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate >/dev/null
xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -4
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/ESP32Car/DriveView.swift ios/ESP32Car/WheelParamsView.swift ios/ESP32Car/SettingsView.swift
git commit -m "feat(ios): dimensions = wizard step 1/3 + Settings row above wheel/motors"
```

---

### Task 10: Build + simulator verification

**Files:** Temporary, reverted — `ios/ESP32Car/GalleryView.swift`.

- [ ] **Step 1: Re-run the donut host checks**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
swiftc ios/ESP32Car/ControlModel.swift ios/ESP32Car/TrickSim.swift ios/ESP32Car/Tricks.swift /tmp/main.swift -o /tmp/dt && /tmp/dt
```
(Recreate `/tmp/main.swift` from Task 6 Step 1 if absent.) Expected: `donut track: all passed`.

- [ ] **Step 2: Ensure the mock serves /dims, then screenshot the dimensions screen**

Temporarily add a gallery frame (the dimensions wizard) + seed the index, build, install, launch:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
curl -s http://127.0.0.1:8080/dims >/dev/null 2>&1 || (cd tools/mock_car && nohup .venv/bin/python -u mock_car.py >/tmp/mock_car.log 2>&1 & sleep 2)
python3 - <<'PY'
p="ios/ESP32Car/GalleryView.swift"; s=open(p).read()
if 'index = 27' not in s: s=s.replace('    @State private var index = 0','    @State private var index = 27')
if 'CarDimensions' not in s:
    s=s.replace('            ("Recover",                 AnyView(NavigationStack { RecoverView(palette: p) })),\n        ]',
                '            ("Recover",                 AnyView(NavigationStack { RecoverView(palette: p) })),\n            ("CarDimensions wizard",    AnyView(NavigationStack { CarDimensionsView(palette: p, wizard: true) })),\n        ]')
open(p,"w").write(s); print("patched")
PY
cd ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -2
APP=$(find /tmp/ddata/Build/Products -name ESP32Car.app | head -1)
xcrun simctl boot "iPhone 17" 2>/dev/null; open -a Simulator
xcrun simctl install booted "$APP"; xcrun simctl terminate booted com.adamjohnson.esp32car 2>/dev/null
xcrun simctl launch booted com.adamjohnson.esp32car --args -gallery >/dev/null
sleep 4; xcrun simctl io booted screenshot /tmp/dims.png >/dev/null 2>&1
sips --rotate 90 /tmp/dims.png --out /tmp/dims_90.png >/dev/null 2>&1 && echo "screenshot /tmp/dims_90.png"
```
Eyeball `/tmp/dims_90.png` (rotate 270 if upside-down): «Размеры машинки» (шаг 1 из 3) shows the top-down
reference car with «Колея 130 мм» (top) + «База 210 мм» (right) dimension lines, and a card with two
steppers. Tapping − / + in the live app slides the wheels (verified separately if desired).

- [ ] **Step 3: Revert the temporary gallery edits**

Set `@State private var index` back to `0` and remove the `"CarDimensions wizard"` frame line. Confirm
`git diff --stat ios/ESP32Car/GalleryView.swift` shows NO changes.

- [ ] **Step 4: No commit** (verification only).

---

## Self-Review

**Spec coverage:**
- Firmware `dims` NVS store (track/wheelbase, clamp, defaults 130/210) → Task 1. ✅
- `GET/POST /dims` mirror of `/wheel`, app_main wiring, handlers 15→17 → Task 2. ✅
- Mock `/dims` for the simulator → Task 3. ✅
- `DimsClient` (GET/POST) → Task 4. ✅
- Localization «Размеры машинки»/«Колея»/«База»/hints; reuse `L.wheelStep` for the wizard badge → Task 5. ✅
- Track threads into donut geometry (`donutSides`/`donutDurationMs`/`donutTrick`) + sim `trackM`;
  `donutTrackFallbackM = 0.13` single named fallback at fetch sites (TrickSimView/DriveView);
  wheelbase NOT in the sim → Task 6. ✅
- Host tests: round-trip, default-track ms unchanged, track sensitivity, linear-in-track → Task 6. ✅
- Reference-car diagram with dimension lines, animated on change → Task 7. ✅
- Screen with two steppers (mm, step 5, ranges), `/dims` load + save-dedup, `wizard` mode → Task 8. ✅
- Wizard = Размеры (1/3) → Колесо и моторы (2/3) → Калибровка; Settings row above «Колесо и моторы» → Task 9. ✅
- Build + screenshot verification → Task 10. ✅
- Out of scope (wheelbase→sim drawing/kinematics, odometry) → untouched. ✅

**Placeholder scan:** none — full code in every code step. ✅

**Type/name consistency:** `dims_params_t{track_mm,wheelbase_mm}`, `dims_init/get/set`, `dims_api_start`
(Tasks 1–2) used in app_main; `DimsClient.Params{trackMm,wheelbaseMm}`/`get()`/`set(_)` (Task 4) used in
Tasks 6/8; `Tricks.donutTrackFallbackM` + `donutSides(diameterCm:trackM:)`/`donutDurationMs(circles:y:vmaxMS:trackM:)`/
`donutTrick(diameterCm:circles:vmaxMS:trackM:)` (Task 6) used in TrickSimView/DriveView; `TrickSimView`
gains `donutDiameterCm:` + `track` state (Task 6), called with `donutDiameterCm:` in TrickEditorView (Task 6
Step 8); `CarDimsDiagram(trackMm:wheelbaseMm:palette:)` (Task 7) used by `CarDimensionsView` (Task 8);
`L.dimsTitle/dimsTrack/dimsBase/dimsTrackHint/dimsBaseHint` (Task 5) used in Tasks 8/9; `L.wheelStep`/
`L.wheelNext`/`WheelParamsView(palette:wizard:)` already exist. The no-circles `donutTrick(diameterCm:)` is
removed in Task 6 and has no remaining callers (TrickEditorView switches to values). ✅
