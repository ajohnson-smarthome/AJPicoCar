# Wheel/Motor Speed-Calibration Params — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Store wheel diameter + encoder params (PPR · gear · quadrature → CPR) on the car (NVS + `/wheel` REST) and add an iOS «Колесо и моторы» editor reachable from Settings and as step 1 of the mandatory calibration wizard. On-board speed computation is deferred (separate spec, when encoder motors arrive).

**Architecture:** Firmware gets a small NVS-backed param store `wheel.{c,h}` (mirrors the `recovery` config pattern) plus `wheel_api.{c,h}` serving `GET /wheel` (JSON) and `POST /wheel` (space-separated ints, no JSON parser). iOS gets a pure `MotorPresets` table (host-tested), a `WheelClient`, and a `WheelParamsView` (two cards: Колёса / Моторы; model picked via native `Menu` autofills PPR/gear/quad; editing a field → «Свои параметры»). The view is wired into `SettingsView` and prepended to `DriveView`'s mandatory-calibration sheet as wizard step 1.

**Tech Stack:** ESP-IDF 5.4 (C, NVS, esp_http_server), SwiftUI (Swift 6), host tests via `cc` (firmware) and `swiftc` (iOS pure module), aiohttp mock car.

**Spec:** `docs/superpowers/specs/2026-06-16-wheel-motor-params-design.md`

**Branch:** `feat/wheel-params` (already created, spec committed there).

---

## File Structure

**Firmware (create):**
- `main/wheel.h` — `wheel_params_t`, bounds, `wheel_init/get/set`, pure `wheel_cpr` inline.
- `main/wheel.c` — RAM store + NVS load + clamp.
- `main/wheel_api.h` / `main/wheel_api.c` — `GET/POST /wheel`.
- `test/test_wheel.c` — host test for `wheel_cpr`.

**Firmware (modify):**
- `main/CMakeLists.txt` — add `wheel.c wheel_api.c` to SRCS.
- `main/main.c` — include + `wheel_init()` + `wheel_api_start()`.
- `main/http_server.c:23` — handler-count comment 13 → 15.
- `test/Makefile` — add `test_wheel`.

**iOS (create):**
- `ios/ESP32Car/MotorPresets.swift` — pure preset table + `cpr`/`match`.
- `ios/ESP32Car/WheelClient.swift` — `GET/POST /wheel`.
- `ios/ESP32Car/WheelParamsView.swift` — the editor screen.
- `ios/ESP32CarTests/MotorPresetsTests.swift` — XCTest mirror.

**iOS (modify):**
- `ios/ESP32Car/L.swift` — new tokens.
- `ios/ESP32Car/Resources/ru.lproj/Localizable.strings` — new strings.
- `ios/ESP32Car/SettingsView.swift` — «Колесо и моторы» menu row.
- `ios/ESP32Car/DriveView.swift:171-176` — wizard sheet root → `WheelParamsView`.

**Dev tooling (modify):**
- `tools/mock_car/mock_car.py` — `/wheel` GET/POST so the simulator exercises the screen.

---

### Task 1: Firmware `wheel.{c,h}` param store + host test

**Files:**
- Create: `main/wheel.h`, `main/wheel.c`, `test/test_wheel.c`
- Modify: `test/Makefile`

- [ ] **Step 1: Write `main/wheel.h`**

```c
#ifndef WHEEL_H
#define WHEEL_H

#include <stdint.h>
#include <stdbool.h>

// Param bounds (validated by wheel_set + the /wheel API).
#define WHEEL_D_MIN_MM        20
#define WHEEL_D_MAX_MM        150
#define WHEEL_PPR_MIN         1
#define WHEEL_PPR_MAX         1000
#define WHEEL_GEAR_X100_MIN   100      // 1:1
#define WHEEL_GEAR_X100_MAX   30000    // 1:300

// Wheel + encoder geometry. gear_x100 = gear ratio × 100 (1:21 → 2100; 1:9.6 → 960).
// quad = quadrature edge multiplier (1, 2, or 4). diameter in mm.
typedef struct {
    uint16_t diameter_mm;
    uint16_t ppr;        // encoder pulses per motor-shaft revolution (one channel)
    uint16_t gear_x100;
    uint8_t  quad;
} wheel_params_t;

// Load params from NVS (or defaults: 65 mm, 11 PPR, 1:21, ×4). Call once at boot.
void wheel_init(void);
// Copy current params out.
void wheel_get(wheel_params_t *out);
// Validate/clamp and store in RAM (the /wheel API persists to NVS).
void wheel_set(const wheel_params_t *in);

// Pure (host-tested): counts per OUTPUT-shaft revolution = ppr × gear × quad.
// Laid in for the future on-board speed calc (v = π·D·ticks_per_s / cpr); unused for now.
static inline float wheel_cpr(const wheel_params_t *w) {
    return (float)w->ppr * ((float)w->gear_x100 / 100.0f) * (float)w->quad;
}

#endif // WHEEL_H
```

- [ ] **Step 2: Write the failing host test `test/test_wheel.c`**

```c
#include "../main/wheel.h"
#include <assert.h>
#include <stdio.h>
#include <math.h>

static int feq(float a, float b) { return fabsf(a - b) < 1e-3f; }

int main(void) {
    // JGA25-370: 11 PPR · 1:21 · ×4 → 924
    wheel_params_t a = { .diameter_mm = 65, .ppr = 11, .gear_x100 = 2100, .quad = 4 };
    assert(feq(wheel_cpr(&a), 924.0f));
    // JGB37-520B: 11 PPR · 1:9 · ×4 → 396
    wheel_params_t b = { .diameter_mm = 65, .ppr = 11, .gear_x100 = 900, .quad = 4 };
    assert(feq(wheel_cpr(&b), 396.0f));
    // fractional gear 1:9.6, ×2 → 11 × 9.6 × 2 = 211.2
    wheel_params_t c = { .diameter_mm = 65, .ppr = 11, .gear_x100 = 960, .quad = 2 };
    assert(feq(wheel_cpr(&c), 211.2f));
    printf("test_wheel: all passed\n");
    return 0;
}
```

- [ ] **Step 3: Wire `test_wheel` into `test/Makefile`**

Add `test_wheel` to the `all:` line, the `run:` chain, and `clean:`, and add this target (after the `test_recovery` target):

```makefile
test_wheel: test_wheel.c
	$(CC) $(CFLAGS) -o $@ $^ $(LDLIBS)
```

The three edited lines become:
```makefile
all: test_mixer test_motors test_control_proto test_watchdog test_calibration test_ramp test_trim test_telemetry test_recovery test_wheel
```
```makefile
run: all
	./test_mixer && ./test_motors && ./test_control_proto && ./test_watchdog && ./test_calibration && ./test_ramp && ./test_trim && ./test_telemetry && ./test_recovery && ./test_wheel
```
```makefile
clean:
	rm -f test_mixer test_motors test_control_proto test_watchdog test_calibration test_ramp test_trim test_telemetry test_recovery test_wheel
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `cd test && make test_wheel`
Expected: FAIL — `wheel.h` exists (Step 1) so it compiles, but to prove the test runs, run `./test_wheel`. (If Step 1 was correct, this already passes; the "failing" state is when `wheel.h` is absent — confirm by `make clean && make test_wheel` only after `wheel.h` exists.) Expected once built: `test_wheel: all passed`.

- [ ] **Step 5: Write `main/wheel.c`**

```c
#include "wheel.h"
#include "esp_log.h"
#include "nvs.h"

static const char *TAG = "wheel";

static wheel_params_t s_params = {
    .diameter_mm = 65, .ppr = 11, .gear_x100 = 2100, .quad = 4,
};

static uint16_t clamp_u16(uint16_t v, uint16_t lo, uint16_t hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

void wheel_set(const wheel_params_t *in) {
    if (!in) return;
    s_params.diameter_mm = clamp_u16(in->diameter_mm, WHEEL_D_MIN_MM, WHEEL_D_MAX_MM);
    s_params.ppr         = clamp_u16(in->ppr, WHEEL_PPR_MIN, WHEEL_PPR_MAX);
    s_params.gear_x100   = clamp_u16(in->gear_x100, WHEEL_GEAR_X100_MIN, WHEEL_GEAR_X100_MAX);
    s_params.quad        = (in->quad == 1 || in->quad == 2 || in->quad == 4) ? in->quad : 4;
}

void wheel_get(wheel_params_t *out) {
    if (out) *out = s_params;
}

void wheel_init(void) {
    nvs_handle_t h;
    if (nvs_open("car", NVS_READONLY, &h) == ESP_OK) {
        uint16_t v; uint8_t b;
        if (nvs_get_u16(h, "wheel_d", &v) == ESP_OK)   s_params.diameter_mm = clamp_u16(v, WHEEL_D_MIN_MM, WHEEL_D_MAX_MM);
        if (nvs_get_u16(h, "enc_ppr", &v) == ESP_OK)   s_params.ppr = clamp_u16(v, WHEEL_PPR_MIN, WHEEL_PPR_MAX);
        if (nvs_get_u16(h, "gear_x100", &v) == ESP_OK) s_params.gear_x100 = clamp_u16(v, WHEEL_GEAR_X100_MIN, WHEEL_GEAR_X100_MAX);
        if (nvs_get_u8(h, "quad", &b) == ESP_OK && (b == 1 || b == 2 || b == 4)) s_params.quad = b;
        nvs_close(h);
    }
    ESP_LOGI(TAG, "wheel d=%u mm ppr=%u gear=%u/100 quad=%u (cpr %.0f)",
             s_params.diameter_mm, s_params.ppr, s_params.gear_x100, s_params.quad,
             (double)wheel_cpr(&s_params));
}
```

- [ ] **Step 6: Run host tests to verify they pass**

Run: `cd test && make run`
Expected: ends with `test_wheel: all passed` and all prior tests still pass.

- [ ] **Step 7: Commit**

```bash
git add main/wheel.h main/wheel.c test/test_wheel.c test/Makefile
git commit -m "feat(wheel): NVS-backed wheel/encoder param store + host-tested wheel_cpr"
```

---

### Task 2: Firmware `wheel_api.{c,h}` + app wiring

**Files:**
- Create: `main/wheel_api.h`, `main/wheel_api.c`
- Modify: `main/CMakeLists.txt`, `main/main.c`, `main/http_server.c`

- [ ] **Step 1: Write `main/wheel_api.h`**

```c
#ifndef WHEEL_API_H
#define WHEEL_API_H

#include "esp_err.h"

// Register GET/POST /wheel on the shared httpd. Call after http_server_start().
esp_err_t wheel_api_start(void);

#endif // WHEEL_API_H
```

- [ ] **Step 2: Write `main/wheel_api.c`**

```c
#include "wheel_api.h"
#include <stdio.h>
#include "esp_http_server.h"
#include "esp_log.h"
#include "esp_check.h"
#include "nvs.h"
#include "http_server.h"
#include "wheel.h"

static const char *TAG = "wheel_api";

static esp_err_t wheel_get_handler(httpd_req_t *req) {
    wheel_params_t w;
    wheel_get(&w);
    char buf[96];
    int n = snprintf(buf, sizeof(buf),
                     "{\"diameter_mm\":%u,\"ppr\":%u,\"gear_x100\":%u,\"quad\":%u}",
                     w.diameter_mm, w.ppr, w.gear_x100, w.quad);
    httpd_resp_set_type(req, "application/json");
    return httpd_resp_send(req, buf, n);
}

static esp_err_t wheel_post_handler(httpd_req_t *req) {
    char body[48] = {0};
    int len = httpd_req_recv(req, body, sizeof(body) - 1);
    if (len <= 0) return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "empty");
    // Body is four ints: "<diameter_mm> <ppr> <gear_x100> <quad>" (no JSON parser dependency).
    int d = -1, ppr = -1, gear = -1, quad = -1;
    if (sscanf(body, "%d %d %d %d", &d, &ppr, &gear, &quad) != 4 ||
        d < WHEEL_D_MIN_MM || d > WHEEL_D_MAX_MM ||
        ppr < WHEEL_PPR_MIN || ppr > WHEEL_PPR_MAX ||
        gear < WHEEL_GEAR_X100_MIN || gear > WHEEL_GEAR_X100_MAX ||
        (quad != 1 && quad != 2 && quad != 4)) {
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST,
                                   "need: <20..150> <1..1000> <100..30000> <1|2|4>");
    }
    wheel_params_t w = { .diameter_mm = (uint16_t)d, .ppr = (uint16_t)ppr,
                         .gear_x100 = (uint16_t)gear, .quad = (uint8_t)quad };
    wheel_set(&w);
    nvs_handle_t h;
    if (nvs_open("car", NVS_READWRITE, &h) == ESP_OK) {
        nvs_set_u16(h, "wheel_d", w.diameter_mm);
        nvs_set_u16(h, "enc_ppr", w.ppr);
        nvs_set_u16(h, "gear_x100", w.gear_x100);
        nvs_set_u8(h, "quad", w.quad);
        esp_err_t e = nvs_commit(h);
        if (e != ESP_OK) ESP_LOGW(TAG, "wheel save failed: %s", esp_err_to_name(e));
        nvs_close(h);
    }
    return httpd_resp_sendstr(req, "ok");
}

esp_err_t wheel_api_start(void) {
    httpd_handle_t server = http_server_get_handle();
    if (server == NULL) { ESP_LOGE(TAG, "http server not started"); return ESP_FAIL; }
    httpd_uri_t g = { .uri = "/wheel", .method = HTTP_GET,  .handler = wheel_get_handler };
    httpd_uri_t p = { .uri = "/wheel", .method = HTTP_POST, .handler = wheel_post_handler };
    ESP_RETURN_ON_ERROR(httpd_register_uri_handler(server, &g), TAG, "reg GET /wheel");
    ESP_RETURN_ON_ERROR(httpd_register_uri_handler(server, &p), TAG, "reg POST /wheel");
    return ESP_OK;
}
```

- [ ] **Step 3: Add the two sources to `main/CMakeLists.txt`**

In the `SRCS` list, append `"wheel.c" "wheel_api.c"` (end of the existing list, before the closing newline):

```cmake
    SRCS "ota_api.c" "main.c" "pca9685.c" "mixer.c" "motors.c" "car.c" "calibration.c" "wifi_ap.c" "http_server.c" "control_proto.c" "ws_control.c" "watchdog.c" "recovery.c" "calib_api.c" "status_api.c" "ramp.c" "ramp_api.c" "trim_api.c" "recovery_api.c" "telemetry.c" "wheel.c" "wheel_api.c"
```

- [ ] **Step 4: Wire into `main/main.c`**

Add the includes (after `#include "recovery_api.h"`, line 22):
```c
#include "wheel.h"
#include "wheel_api.h"
```

Add `wheel_init();` right after `car_init();` (line 80):
```c
    car_init();
    wheel_init();                          // load wheel/encoder params (NVS or defaults)
```

Add the API start among the `*_api_start()` calls, after `recovery_api_start()` (line 89):
```c
    ESP_ERROR_CHECK(recovery_api_start());
    ESP_ERROR_CHECK(wheel_api_start());
```

- [ ] **Step 5: Update the handler-count comment in `main/http_server.c`**

Change the comment at line 23 from:
```c
    // We register 13 URI handlers (/, /ws, /calib*3, /status, /ota, /ramp*2, /trim*2, /recover*2),
```
to:
```c
    // We register 15 URI handlers (/, /ws, /calib*3, /status, /ota, /ramp*2, /trim*2, /recover*2, /wheel*2),
```

- [ ] **Step 6: Build the firmware**

Run:
```bash
mkdir -p /tmp/py313bin && ln -sf /opt/homebrew/bin/python3.13 /tmp/py313bin/python3
export PATH=/tmp/py313bin:$PATH && source ~/esp/esp-idf/export.sh && idf.py build
```
Expected: `Project build complete.` No new warnings from `wheel.c`/`wheel_api.c`.

- [ ] **Step 7: Commit**

```bash
git add main/wheel_api.h main/wheel_api.c main/CMakeLists.txt main/main.c main/http_server.c
git commit -m "feat(wheel): GET/POST /wheel REST + boot wiring (handlers 13->15)"
```

---

### Task 3: iOS `MotorPresets.swift` (pure) + tests

**Files:**
- Create: `ios/ESP32Car/MotorPresets.swift`, `ios/ESP32CarTests/MotorPresetsTests.swift`

- [ ] **Step 1: Write the native swiftc check `/tmp/mp_check.swift`**

```swift
import Foundation
assert(MotorPresets.cpr(ppr: 11, gearX100: 2100, quad: 4) == 924)
assert(MotorPresets.cpr(ppr: 11, gearX100: 900, quad: 4) == 396)
assert(MotorPresets.cpr(ppr: 11, gearX100: 960, quad: 2) == 211.2)
assert(MotorPresets.match(ppr: 11, gearX100: 2100, quad: 4)?.name == "JGA25-370")
assert(MotorPresets.match(ppr: 11, gearX100: 900, quad: 4)?.name == "JGB37-520B")
assert(MotorPresets.match(ppr: 13, gearX100: 2100, quad: 4) == nil)
assert(Set(MotorPresets.all.map { $0.id }).count == MotorPresets.all.count)
print("MotorPresets: all passed")
```

- [ ] **Step 2: Run it to verify it fails (no `MotorPresets` yet)**

Run: `swiftc ios/ESP32Car/MotorPresets.swift /tmp/mp_check.swift -o /tmp/mp_check`
Expected: FAIL — `error: no such file or directory: 'ios/ESP32Car/MotorPresets.swift'`.

- [ ] **Step 3: Write `ios/ESP32Car/MotorPresets.swift`**

```swift
import Foundation

/// One known motor configuration. `gearX100` = gear ratio × 100 (matches firmware /wheel).
/// `rpm` is a label only (rated output speed) — it does not affect CPR.
struct MotorPreset: Identifiable, Equatable {
    let id: String       // stable key, e.g. "jga25-370-170"
    let name: String     // "JGA25-370"
    let rpm: Int         // rated output rpm, label only
    let ppr: Int         // encoder pulses per motor-shaft rev (one channel)
    let gearX100: Int
    let quad: Int        // 1 / 2 / 4
    var gear: Double { Double(gearX100) / 100 }
    var cpr: Double { Double(ppr) * gear * Double(quad) }
}

/// Starter presets (verify against the motor datasheet — these define CPR/speed).
/// The menu lists ONLY these; there is no "Other" item — editing any field just makes
/// `match` return nil (the UI then shows «Свои параметры»).
enum MotorPresets {
    static let all: [MotorPreset] = [
        MotorPreset(id: "jga25-370-170",  name: "JGA25-370",  rpm: 170,  ppr: 11, gearX100: 2100, quad: 4),
        MotorPreset(id: "jgb37-520b-1000", name: "JGB37-520B", rpm: 1000, ppr: 11, gearX100: 900,  quad: 4),
    ]

    /// Counts per output-shaft revolution = ppr × gear × quad.
    static func cpr(ppr: Int, gearX100: Int, quad: Int) -> Double {
        Double(ppr) * (Double(gearX100) / 100) * Double(quad)
    }

    /// The preset matching these exact numbers, or nil if the user hand-entered custom values.
    static func match(ppr: Int, gearX100: Int, quad: Int) -> MotorPreset? {
        all.first { $0.ppr == ppr && $0.gearX100 == gearX100 && $0.quad == quad }
    }
}
```

- [ ] **Step 4: Run the swiftc check to verify it passes**

Run: `swiftc ios/ESP32Car/MotorPresets.swift /tmp/mp_check.swift -o /tmp/mp_check && /tmp/mp_check`
Expected: `MotorPresets: all passed`

- [ ] **Step 5: Write the XCTest mirror `ios/ESP32CarTests/MotorPresetsTests.swift`**

```swift
import XCTest
@testable import ESP32Car

final class MotorPresetsTests: XCTestCase {
    func testCpr() {
        XCTAssertEqual(MotorPresets.cpr(ppr: 11, gearX100: 2100, quad: 4), 924, accuracy: 0.001)
        XCTAssertEqual(MotorPresets.cpr(ppr: 11, gearX100: 900, quad: 4), 396, accuracy: 0.001)
        XCTAssertEqual(MotorPresets.cpr(ppr: 11, gearX100: 960, quad: 2), 211.2, accuracy: 0.001)
    }
    func testPresetCpr() {
        XCTAssertEqual(MotorPresets.all.first { $0.id == "jga25-370-170" }?.cpr, 924)
        XCTAssertEqual(MotorPresets.all.first { $0.id == "jgb37-520b-1000" }?.cpr, 396)
    }
    func testMatch() {
        XCTAssertEqual(MotorPresets.match(ppr: 11, gearX100: 2100, quad: 4)?.name, "JGA25-370")
        XCTAssertEqual(MotorPresets.match(ppr: 11, gearX100: 900, quad: 4)?.name, "JGB37-520B")
        XCTAssertNil(MotorPresets.match(ppr: 13, gearX100: 2100, quad: 4))
    }
    func testIdsUnique() {
        XCTAssertEqual(Set(MotorPresets.all.map { $0.id }).count, MotorPresets.all.count)
    }
}
```

- [ ] **Step 6: Commit**

```bash
git add ios/ESP32Car/MotorPresets.swift ios/ESP32CarTests/MotorPresetsTests.swift
git commit -m "feat(ios): MotorPresets pure table (cpr/match) + host tests"
```

---

### Task 4: iOS `WheelClient.swift`

**Files:**
- Create: `ios/ESP32Car/WheelClient.swift`

- [ ] **Step 1: Write `ios/ESP32Car/WheelClient.swift`**

```swift
import Foundation

/// Reads/writes the car's wheel + motor params via GET/POST /wheel.
/// GET returns JSON; POST sends four space-separated ints (mirrors the firmware).
struct WheelClient {
    struct Params: Equatable {
        var diameterMm: Int
        var ppr: Int
        var gearX100: Int
        var quad: Int
    }

    func get() async -> Params? {
        guard let url = URL(string: CarHost.httpBase + "/wheel") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let d = j["diameter_mm"] as? Int,
              let ppr = j["ppr"] as? Int,
              let gear = j["gear_x100"] as? Int,
              let quad = j["quad"] as? Int else { return nil }
        return Params(diameterMm: d, ppr: ppr, gearX100: gear, quad: quad)
    }

    @discardableResult
    func set(_ p: Params) async -> Bool {
        guard let url = URL(string: CarHost.httpBase + "/wheel") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = "\(p.diameterMm) \(p.ppr) \(p.gearX100) \(p.quad)".data(using: .utf8)
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }
}
```

- [ ] **Step 2: Commit** (compile verification happens in Task 7 with the rest of the iOS target)

```bash
git add ios/ESP32Car/WheelClient.swift
git commit -m "feat(ios): WheelClient — GET/POST /wheel"
```

---

### Task 5: iOS `WheelParamsView.swift` + localization

**Files:**
- Create: `ios/ESP32Car/WheelParamsView.swift`
- Modify: `ios/ESP32Car/L.swift`, `ios/ESP32Car/Resources/ru.lproj/Localizable.strings`

- [ ] **Step 1: Add localization keys to `ios/ESP32Car/Resources/ru.lproj/Localizable.strings`**

Append (place near the other settings entries):
```
"wheel.title"         = "Колесо и моторы";
"wheel.wizardTitle"   = "Параметры колёс";
"wheel.step"          = "шаг %d из %d";
"wheel.next"          = "Далее";
"wheel.sectionWheels" = "Колёса";
"wheel.sectionMotors" = "Моторы";
"wheel.diameter"      = "Диаметр колеса";
"wheel.circ"          = "Окружность";
"wheel.model"         = "Модель";
"wheel.ppr"           = "Импульсы (PPR)";
"wheel.gear"          = "Редуктор";
"wheel.quad"          = "Квадратура";
"wheel.custom"        = "Свои параметры";
"unit.mm"             = "мм";
"unit.rpm"            = "об/мин";
```

- [ ] **Step 2: Add typed accessors to `ios/ESP32Car/L.swift`**

Add these inside `enum L` (e.g. after the `recover*` accessors near line 70):
```swift
    static var wheelTitle: String { s("wheel.title") }
    static var wheelWizardTitle: String { s("wheel.wizardTitle") }
    static func wheelStep(_ a: Int, _ b: Int) -> String { s("wheel.step", a, b) }
    static var wheelNext: String { s("wheel.next") }
    static var wheelSectionWheels: String { s("wheel.sectionWheels") }
    static var wheelSectionMotors: String { s("wheel.sectionMotors") }
    static var wheelDiameter: String { s("wheel.diameter") }
    static var wheelCirc: String { s("wheel.circ") }
    static var wheelModel: String { s("wheel.model") }
    static var wheelPpr: String { s("wheel.ppr") }
    static var wheelGear: String { s("wheel.gear") }
    static var wheelQuad: String { s("wheel.quad") }
    static var wheelCustom: String { s("wheel.custom") }
    static var mmUnit: String { s("unit.mm") }
    static var rpmUnit: String { s("unit.rpm") }
```

- [ ] **Step 3: Write `ios/ESP32Car/WheelParamsView.swift`**

```swift
import SwiftUI

/// Wheel diameter + motor encoder params (PPR · gear · quadrature → CPR), stored on the car
/// via /wheel. Two uses: a Settings menu item (wizard == false, back chevron) and step 1 of
/// the mandatory calibration wizard (wizard == true, "Далее" → CalibrationView). No system
/// nav bar (matches SplitScreen siblings) — draws its own header.
struct WheelParamsView: View {
    let palette: Palette
    var wizard: Bool = false
    @Environment(\.dismiss) private var dismiss
    private var p: Palette { palette }

    @State private var diameterMm = 65
    @State private var ppr = 11
    @State private var gearX100 = 2100
    @State private var quad = 4
    @State private var gearText = "21"
    @AppStorage("wheel.model") private var modelId = ""

    private var preset: MotorPreset? { MotorPresets.match(ppr: ppr, gearX100: gearX100, quad: quad) }
    private var cpr: Double { MotorPresets.cpr(ppr: ppr, gearX100: gearX100, quad: quad) }
    private var circMm: Double { .pi * Double(diameterMm) }

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 18) {
                        wheelsCard
                        motorsCard
                    }
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 20)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if let c = await WheelClient().get() {
                diameterMm = c.diameterMm; ppr = c.ppr; gearX100 = c.gearX100; quad = c.quad
                gearText = Self.gearString(c.gearX100)
            }
        }
    }

    // MARK: header
    private var header: some View {
        HStack {
            if wizard {
                Text(L.wheelStep(1, 2)).font(.system(size: 13)).foregroundStyle(p.muted)
                    .frame(width: 70, alignment: .leading)
            } else {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(p.accent).frame(width: 70, alignment: .leading)
            }
            Spacer()
            Text(wizard ? L.wheelWizardTitle : L.wheelTitle)
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(p.text)
            Spacer()
            Group {
                if wizard {
                    NavigationLink { CalibrationView(palette: p, dismissible: false) } label: {
                        Text(L.wheelNext).font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(p.accent)
                } else {
                    Color.clear.frame(width: 1, height: 1)
                }
            }
            .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)
    }

    // MARK: cards
    private var wheelsCard: some View {
        card(L.wheelSectionWheels) {
            row(L.wheelDiameter) {
                Stepper("\(diameterMm) \(L.mmUnit)", value: $diameterMm, in: 20...150)
                    .fixedSize().foregroundStyle(p.text)
                    .onChange(of: diameterMm) { _ in save() }
            }
            divider
            infoRow(L.wheelCirc, String(format: "%.0f %@", circMm, L.mmUnit))
        }
    }

    private var motorsCard: some View {
        card(L.wheelSectionMotors) {
            row(L.wheelModel) {
                Menu {
                    ForEach(MotorPresets.all) { m in
                        Button { apply(m) } label: { Text("\(m.name) · \(m.rpm) \(L.rpmUnit)") }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(preset?.name ?? L.wheelCustom).foregroundStyle(p.accent)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11)).foregroundStyle(p.muted)
                    }
                }
            }
            divider
            row(L.wheelPpr) {
                Stepper("\(ppr)", value: $ppr, in: 1...1000)
                    .fixedSize().foregroundStyle(p.text)
                    .onChange(of: ppr) { _ in save() }
            }
            divider
            row(L.wheelGear) {
                TextField("", text: $gearText)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    .frame(width: 70).foregroundStyle(p.text)
                    .onChange(of: gearText) { _ in commitGear() }
            }
            divider
            row(L.wheelQuad) {
                Picker("", selection: $quad) {
                    Text("×1").tag(1); Text("×2").tag(2); Text("×4").tag(4)
                }
                .pickerStyle(.segmented).frame(width: 150)
                .onChange(of: quad) { _ in save() }
            }
            divider
            infoRow("CPR", String(format: "%.0f", cpr))
        }
    }

    // MARK: actions
    private func apply(_ m: MotorPreset) {
        ppr = m.ppr; gearX100 = m.gearX100; quad = m.quad
        gearText = Self.gearString(m.gearX100)
        modelId = m.id
        save()
    }

    private func commitGear() {
        let norm = gearText.replacingOccurrences(of: ",", with: ".")
        if let g = Double(norm), g >= 1, g <= 300 {
            gearX100 = Int((g * 100).rounded())
            save()
        }
    }

    private func save() {
        Task {
            await WheelClient().set(.init(diameterMm: diameterMm, ppr: ppr,
                                          gearX100: gearX100, quad: quad))
        }
    }

    static func gearString(_ x100: Int) -> String {
        let g = Double(x100) / 100
        return g == g.rounded() ? String(format: "%.0f", g) : String(format: "%.1f", g)
    }

    // MARK: row/card builders
    @ViewBuilder private func card<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased()).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(p.muted).padding(.leading, 4).padding(.bottom, 6)
            VStack(spacing: 0) { content() }
                .background(p.panel)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(p.metal.opacity(0.4), lineWidth: 1))
        }
    }

    @ViewBuilder private func row<C: View>(_ label: String, @ViewBuilder _ control: () -> C) -> some View {
        HStack { Text(label).foregroundStyle(p.text); Spacer(); control() }
            .font(.system(size: 14)).padding(.horizontal, 14).frame(minHeight: 44)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(p.muted)
            Spacer()
            Text(value).foregroundStyle(p.accent).fontWeight(.semibold).monospacedDigit()
        }
        .font(.system(size: 14)).padding(.horizontal, 14).frame(minHeight: 44)
    }

    private var divider: some View { Rectangle().fill(p.metal.opacity(0.25)).frame(height: 1) }
}
```

- [ ] **Step 4: Commit** (the view compiles as part of the target in Task 7)

```bash
git add ios/ESP32Car/WheelParamsView.swift ios/ESP32Car/L.swift ios/ESP32Car/Resources/ru.lproj/Localizable.strings
git commit -m "feat(ios): WheelParamsView — two-card editor (model Menu autofill) + ru strings"
```

---

### Task 6: iOS integration — Settings row + wizard step 1

**Files:**
- Modify: `ios/ESP32Car/SettingsView.swift`, `ios/ESP32Car/DriveView.swift`

- [ ] **Step 1: Add the «Колесо и моторы» row to `SettingsView.swift`**

Insert this `NavigationLink` as the FIRST item in the `List` (immediately after `List {`, before the «Калибровка» row at line 16):
```swift
                    NavigationLink {
                        WheelParamsView(palette: palette)
                    } label: {
                        Label(L.wheelTitle, systemImage: "ruler")
                            .foregroundStyle(palette.text)
                    }
                    .listRowBackground(palette.panel)
```

- [ ] **Step 2: Make wheel params step 1 of the mandatory wizard in `DriveView.swift`**

Replace the sheet body (lines 171-176):
```swift
        .sheet(isPresented: $showCalib) {
            NavigationStack {
                CalibrationView(palette: p, dismissible: false)
            }
            .interactiveDismissDisabled(true)
        }
```
with:
```swift
        .sheet(isPresented: $showCalib) {
            NavigationStack {
                WheelParamsView(palette: p, wizard: true)   // step 1 → "Далее" → CalibrationView
            }
            .interactiveDismissDisabled(true)
        }
```

- [ ] **Step 3: Commit**

```bash
git add ios/ESP32Car/SettingsView.swift ios/ESP32Car/DriveView.swift
git commit -m "feat(ios): wire WheelParamsView into Settings + as calibration wizard step 1"
```

---

### Task 7: Mock car `/wheel` + full build/test verification

**Files:**
- Modify: `tools/mock_car/mock_car.py`

- [ ] **Step 1: Add `/wheel` to the mock car**

In `tools/mock_car/mock_car.py`, extend `STATE` (line 10) to include a wheel dict:
```python
STATE = {"calibrated": False, "ramp_ms": 300, "trim_pct": 0, "wdt_trips": 0,
         "wheel": {"diameter_mm": 65, "ppr": 11, "gear_x100": 2100, "quad": 4}}
```

Add these handlers (after `trim_post`, before `ota`):
```python
async def wheel_get(request):
    return web.json_response(STATE["wheel"])


async def wheel_post(request):
    body = (await request.text()).strip()
    try:
        d, ppr, gear, quad = (int(x) for x in body.split())
        if not (20 <= d <= 150 and 1 <= ppr <= 1000 and 100 <= gear <= 30000 and quad in (1, 2, 4)):
            raise ValueError
    except ValueError:
        return web.Response(status=400, text="need: <d> <ppr> <gear_x100> <quad>")
    STATE["wheel"] = {"diameter_mm": d, "ppr": ppr, "gear_x100": gear, "quad": quad}
    print(f"wheel: {STATE['wheel']}")
    return web.Response(text="ok")
```

Register the routes (in the `app.add_routes([...])` list):
```python
        web.get("/wheel", wheel_get),
        web.post("/wheel", wheel_post),
```

- [ ] **Step 2: Run firmware host tests**

Run: `cd test && make run`
Expected: all pass, ending `test_wheel: all passed`.

- [ ] **Step 3: Run the iOS pure check**

Run: `swiftc ios/ESP32Car/MotorPresets.swift /tmp/mp_check.swift -o /tmp/mp_check && /tmp/mp_check`
Expected: `MotorPresets: all passed`

- [ ] **Step 4: Regenerate the Xcode project and build the iOS target**

Run:
```bash
cd ios && xcodegen generate
xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **` (new files `MotorPresets.swift`, `WheelClient.swift`, `WheelParamsView.swift` picked up by xcodegen's glob).

- [ ] **Step 5: Build the firmware once more (full integration)**

Run:
```bash
export PATH=/tmp/py313bin:$PATH && source ~/esp/esp-idf/export.sh && idf.py build 2>&1 | tail -3
```
Expected: `Project build complete.`

- [ ] **Step 6: Commit**

```bash
git add tools/mock_car/mock_car.py
git commit -m "test(mock): serve /wheel GET/POST for simulator runs"
```

---

## Manual verification (user, after merge)

Not automatable here — note for the user:
- **Simulator:** launch with the mock car running → Settings → «Колесо и моторы» shows JGA25-370 by default; pick JGB37-520B → PPR/gear/quad + CPR (396) autofill; edit gear → model flips to «Свои параметры»; values persist across relaunch (mock holds them). First-connect (calibrated=false) → wizard shows «Параметры колёс» (step 1 of 2) → «Далее» → calibration.
- **Device (when flashed):** same, persisted in NVS across reboot/OTA.

---

## Self-Review

**Spec coverage:**
- Firmware NVS store (D, PPR, gear_x100, quad) + defaults → Task 1. ✅
- `wheel_cpr` helper laid in + host-tested → Task 1. ✅
- `GET/POST /wheel` + boot wiring + handlers 13→15 → Task 2. ✅
- `MotorPresets` pure table (cpr/match) + host test, two real motors, no «Другое» menu item → Task 3. ✅
- `WheelClient` → Task 4. ✅
- `WheelParamsView` two cards, model Menu autofill, edit→«Свои параметры», wizard mode, `.task` load → Task 5. ✅
- Settings menu item «Колесо и моторы» (before Калибровка) + wizard step 1 in DriveView → Task 6. ✅
- Localization, no Cyrillic literals (all via L/strings; only "CPR"/"×1"/"PPR" acronyms inline) → Task 5. ✅
- Mock `/wheel` for sim → Task 7. ✅
- Out of scope (speed calc, PCNT, per-wheel D) → not implemented, by design. ✅

**Placeholder scan:** no TBD/TODO; every code step shows full code. ✅

**Type consistency:** `gearX100` (Int) used consistently in `MotorPreset`, `WheelClient.Params`, and `WheelParamsView`; firmware `gear_x100` (uint16) matches; `quad` ∈ {1,2,4} enforced in `wheel_set`, `wheel_post_handler`, the Picker tags, and mock validation; JSON keys `diameter_mm`/`ppr`/`gear_x100`/`quad` identical across firmware GET, `WheelClient.get`, and mock. ✅
