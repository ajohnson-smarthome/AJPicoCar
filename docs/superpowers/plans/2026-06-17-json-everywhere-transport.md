# JSON Everywhere — Phase 1: Transport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move all app↔car *communication* to JSON — the `/ws` control frames (drive + tricks) become `{"t":..,"y":..}`, and every config POST body becomes a JSON object — while keeping the hot `/ws` path zero-alloc.

**Architecture:** A pure zero-alloc `control_parse_json` handles the 10 Hz `/ws` frame (no heap); the bundled ESP-IDF `cJSON` component parses the cold config POST bodies. GET responses + 5 Hz telemetry are already JSON (`snprintf`) and unchanged. iOS clients send JSON bodies; the mock matches. **Storage stays as-is in this phase** (NVS typed keys) — that's Phase 2.

**Tech Stack:** ESP-IDF 5.4 (C, cJSON), SwiftUI (Swift 6), `swiftc`/`cc` host tests, aiohttp mock.

**Spec:** `docs/superpowers/specs/2026-06-17-json-everywhere-design.md`

**Branch:** `feat/json-everywhere`

---

## File Structure

- `main/CMakeLists.txt` — **modify**: add `json` (cJSON) to `REQUIRES`.
- `main/control_proto.{c,h}` — **modify**: replace `control_parse_ty` with pure zero-alloc `control_parse_json`.
- `test/test_control_proto.c`, `test/Makefile` — **modify**: JSON-frame tests.
- `main/ws_control.c` — **modify**: parse frames via `control_parse_json`.
- `main/{wheel,dims,ramp,trim,recovery,calib}_api.c` — **modify**: POST handlers parse JSON via cJSON.
- `ios/ESP32Car/ControlModel.swift` — **modify**: `frame()` → JSON; `calibSaveBody()` → JSON.
- `ios/ESP32Car/{WheelClient,DimsClient,RampClient,TrimClient,RecoverClient,CalibClient}.swift` — **modify**: JSON POST bodies.
- `tools/mock_car/mock_car.py` — **modify**: parse JSON `/ws` frames + JSON config POSTs.

NVS storage (the inline `nvs_set_*` in the api POST handlers + the `*_init` loads) is **untouched** here — Phase 2.

---

### Task 1: Add the cJSON dependency

**Files:**
- Modify: `main/CMakeLists.txt`

- [ ] **Step 1: Add `json` to `REQUIRES`**

In `main/CMakeLists.txt`, append `json` to the `REQUIRES` list:
```
    REQUIRES esp_wifi esp_netif esp_event nvs_flash esp_http_server esp_timer heap esp_app_format app_update json
```

- [ ] **Step 2: Verify the firmware still builds (cJSON links)**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
mkdir -p /tmp/py313bin && ln -sf /opt/homebrew/bin/python3.13 /tmp/py313bin/python3
export PATH=/tmp/py313bin:$PATH
source ~/esp/esp-idf/export.sh >/dev/null 2>&1
idf.py build 2>&1 | tail -4
```
Expected: `Project build complete.` / `Built target app`. (cJSON is a bundled IDF component — adding it to REQUIRES is enough; no source download.)

- [ ] **Step 3: Commit**

```bash
git add main/CMakeLists.txt
git commit -m "build(fw): add cJSON (json component) to REQUIRES"
```

---

### Task 2: `/ws` control frame → JSON (pure, zero-alloc) + firmware wiring

**Files:**
- Modify: `main/control_proto.h`, `main/control_proto.c`, `test/test_control_proto.c`, `main/ws_control.c`

- [ ] **Step 1: Rewrite the host test `test/test_control_proto.c`** (TDD — JSON frames now)

Replace the whole file with:
```c
#include "control_proto.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

static int approx(float a, float b) { return fabsf(a - b) < 1e-4f; }

static void ok(const char *msg, float et, float ey) {
    float t = 999.0f, y = 999.0f;
    int r = control_parse_json(msg, &t, &y);
    if (r != 0 || !approx(t, et) || !approx(y, ey)) {
        printf("FAIL ok('%s') -> r=%d t=%.4f y=%.4f (want t=%.4f y=%.4f)\n",
               msg, r, t, y, et, ey);
        assert(0);
    }
}

static void bad(const char *msg) {
    float t = 7.0f, y = 7.0f;
    int r = control_parse_json(msg, &t, &y);
    if (r != -1 || t != 7.0f || y != 7.0f) {  // unchanged on failure
        printf("FAIL bad('%s') -> r=%d t=%.4f y=%.4f (want r=-1, unchanged)\n",
               msg ? msg : "(null)", r, t, y);
        assert(0);
    }
}

int main(void) {
    ok("{\"t\":0.5,\"y\":0}", 0.5f, 0.0f);
    ok("{\"t\":0,\"y\":1}", 0.0f, 1.0f);
    ok("{\"t\":-1,\"y\":-0.5}", -1.0f, -0.5f);
    ok("{\"y\":-1.0,\"t\":1.0}", 1.0f, -1.0f);          // key order independent
    ok("{ \"t\" : 0.25 , \"y\" : 0.75 }", 0.25f, 0.75f); // whitespace tolerated

    bad("abc");
    bad("{\"t\":0.5}");        // missing y
    bad("{\"y\":0.5}");        // missing t
    bad("{}");
    bad("");
    bad("{\"t\":nan,\"y\":0}");  // non-finite rejected
    bad("{\"t\":inf,\"y\":0}");  // non-finite rejected
    bad("{\"t\":1,\"y\":-inf}");
    bad(NULL);

    printf("test_control_proto: all passed\n");
    return 0;
}
```

- [ ] **Step 2: Update `test/Makefile` target** (the source list is unchanged, but confirm it still links `control_proto.c`)

The line is already:
```
test_control_proto: test_control_proto.c ../main/control_proto.c
	$(CC) $(CFLAGS) -o $@ $^ $(LDLIBS)
```
No change needed — verify it exists.

- [ ] **Step 3: Run the test to verify it FAILS** (no `control_parse_json` yet)

Run: `cd /Users/adamjohnson/VSCode/esp32-p4-car/test && make test_control_proto 2>&1 | tail -5`
Expected: compile FAIL — `control_parse_json` undefined.

- [ ] **Step 4: Rewrite `main/control_proto.h`**

```c
#ifndef CONTROL_PROTO_H
#define CONTROL_PROTO_H

// Parse a JSON control frame {"t":<num>,"y":<num>} into throttle and yaw.
// Zero-alloc, fixed-shape scan (no JSON library) for the 10 Hz hot path: finds the
// "t"/"y" keys (order-independent) and reads the number after each. Whitespace is
// tolerated. Non-finite values (NaN/inf) are rejected. Returns 0 on success, -1 on
// malformed input or a missing key. Does NOT range-check finite values (car_drive
// clamps them). On failure, *throttle/*yaw are unchanged.
int control_parse_json(const char *msg, float *throttle, float *yaw);

#endif // CONTROL_PROTO_H
```

- [ ] **Step 5: Rewrite `main/control_proto.c`**

```c
#include "control_proto.h"
#include <string.h>
#include <stdlib.h>
#include <math.h>

// Find a JSON number keyed by `key` (e.g. "\"t\"") and parse the value after the
// colon. Zero-alloc; tolerant of whitespace. Returns 0 on success, -1 otherwise.
static int find_num(const char *msg, const char *key, float *out) {
    const char *p = strstr(msg, key);
    if (p == NULL) return -1;
    p += strlen(key);
    while (*p == ' ' || *p == '\t' || *p == ':') p++;  // skip ws + the colon
    char *end;
    float v = strtof(p, &end);
    if (end == p || !isfinite(v)) return -1;
    *out = v;
    return 0;
}

int control_parse_json(const char *msg, float *throttle, float *yaw) {
    if (msg == NULL) return -1;
    float t, y;
    if (find_num(msg, "\"t\"", &t) != 0) return -1;
    if (find_num(msg, "\"y\"", &y) != 0) return -1;
    *throttle = t;
    *yaw = y;
    return 0;
}
```

- [ ] **Step 6: Run the test to verify it PASSES**

Run: `cd /Users/adamjohnson/VSCode/esp32-p4-car/test && make run 2>&1 | tail -12`
Expected: `test_control_proto: all passed` (and all other suites still pass).

- [ ] **Step 7: Update `main/ws_control.c`** to call the JSON parser

Change the parse call:
```c
    if (control_parse_ty((const char *)buf, &t, &y) == 0) {
```
to:
```c
    if (control_parse_json((const char *)buf, &t, &y) == 0) {
```

- [ ] **Step 8: Commit**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add main/control_proto.h main/control_proto.c test/test_control_proto.c main/ws_control.c
git commit -m "feat(fw): /ws control frame is JSON {\"t\",\"y\"} — pure zero-alloc parser"
```

---

### Task 3: iOS `/ws` frame → JSON

**Files:**
- Modify: `ios/ESP32Car/ControlModel.swift`

- [ ] **Step 1: Write the host check `/tmp/frame.swift`**

```swift
import Foundation
func eq(_ a: String, _ b: String, _ w: String) { assert(a == b, "\(w): '\(a)' != '\(b)'") }
eq(ControlModel.frame(t: 0.5, y: 0), "{\"t\":0.50,\"y\":0.00}", "f1")
eq(ControlModel.frame(t: -1, y: 1), "{\"t\":-1.00,\"y\":1.00}", "f2")
eq(ControlModel.frame(t: 5, y: -5), "{\"t\":1.00,\"y\":-1.00}", "clamp")   // clamped to [-1,1]
print("frame json: all passed")
```

- [ ] **Step 2: Run it to verify it FAILS** (frame still emits "t,y")

Run: `cd /Users/adamjohnson/VSCode/esp32-p4-car && swiftc ios/ESP32Car/ControlModel.swift /tmp/frame.swift -o /tmp/cf && /tmp/cf`
Expected: assertion FAIL (`'0.50,0.00' != '{"t":0.50,"y":0.00}'`).

- [ ] **Step 3: Change `frame()` in `ios/ESP32Car/ControlModel.swift`**

Replace:
```swift
    /// Wire frame "t,y" with two decimals (matches the web pad / firmware parser).
    static func frame(t: Double, y: Double) -> String {
        String(format: "%.2f,%.2f", clamp(t), clamp(y))
    }
```
with:
```swift
    /// Wire frame as a JSON object {"t":..,"y":..} (two decimals), clamped to [-1,1].
    static func frame(t: Double, y: Double) -> String {
        String(format: "{\"t\":%.2f,\"y\":%.2f}", clamp(t), clamp(y))
    }
```

- [ ] **Step 4: Run the host check to verify it PASSES**

Run: `cd /Users/adamjohnson/VSCode/esp32-p4-car && swiftc ios/ESP32Car/ControlModel.swift /tmp/frame.swift -o /tmp/cf && /tmp/cf`
Expected: `frame json: all passed`

- [ ] **Step 5: Build the iOS target** (callers `CarConnection`/`DriveView` use `frame` unchanged)

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate >/dev/null
xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -4
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/ControlModel.swift
git commit -m "feat(ios): /ws drive+trick frame is JSON {\"t\",\"y\"}"
```

---

### Task 4: Firmware config POST bodies → cJSON

**Files:**
- Modify: `main/wheel_api.c`, `main/dims_api.c`, `main/ramp_api.c`, `main/trim_api.c`, `main/recovery_api.c`, `main/calib_api.c`

For each handler: keep the existing NVS-write/validation logic; only the body **parse** changes from `sscanf`/`strtol` to cJSON. Add `#include "cJSON.h"` at the top of each file.

- [ ] **Step 1: `main/wheel_api.c`** — replace the body-parse block in `wheel_post_handler`

Add `#include "cJSON.h"`. Replace the `sscanf` validation block:
```c
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
```
with:
```c
    // Body is JSON: {"diameter_mm":..,"ppr":..,"gear_x100":..,"quad":..}
    cJSON *j = cJSON_Parse(body);
    cJSON *jd = cJSON_GetObjectItemCaseSensitive(j, "diameter_mm");
    cJSON *jp = cJSON_GetObjectItemCaseSensitive(j, "ppr");
    cJSON *jg = cJSON_GetObjectItemCaseSensitive(j, "gear_x100");
    cJSON *jq = cJSON_GetObjectItemCaseSensitive(j, "quad");
    if (!cJSON_IsNumber(jd) || !cJSON_IsNumber(jp) || !cJSON_IsNumber(jg) || !cJSON_IsNumber(jq)) {
        cJSON_Delete(j);
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST,
                                   "need {diameter_mm,ppr,gear_x100,quad}");
    }
    int d = jd->valueint, ppr = jp->valueint, gear = jg->valueint, quad = jq->valueint;
    cJSON_Delete(j);
    if (d < WHEEL_D_MIN_MM || d > WHEEL_D_MAX_MM ||
        ppr < WHEEL_PPR_MIN || ppr > WHEEL_PPR_MAX ||
        gear < WHEEL_GEAR_X100_MIN || gear > WHEEL_GEAR_X100_MAX ||
        (quad != 1 && quad != 2 && quad != 4)) {
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST,
                                   "range: <20..150> <1..1000> <100..30000> <1|2|4>");
    }
```
(The rest — building `wheel_params_t`, `wheel_set`, the NVS write, `"ok"` — is unchanged.)

- [ ] **Step 2: `main/dims_api.c`** — replace the body-parse block in `dims_post_handler`

Add `#include "cJSON.h"`. Replace:
```c
    // Body is two ints: "<track_mm> <wheelbase_mm>" (no JSON parser dependency).
    int track = -1, base = -1;
    if (sscanf(body, "%d %d", &track, &base) != 2 ||
        track < DIMS_TRACK_MIN_MM || track > DIMS_TRACK_MAX_MM ||
        base < DIMS_WHEELBASE_MIN_MM || base > DIMS_WHEELBASE_MAX_MM) {
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "need: <60..300> <90..360>");
    }
```
with:
```c
    // Body is JSON: {"track_mm":..,"wheelbase_mm":..}
    cJSON *j = cJSON_Parse(body);
    cJSON *jt = cJSON_GetObjectItemCaseSensitive(j, "track_mm");
    cJSON *jw = cJSON_GetObjectItemCaseSensitive(j, "wheelbase_mm");
    if (!cJSON_IsNumber(jt) || !cJSON_IsNumber(jw)) {
        cJSON_Delete(j);
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "need {track_mm,wheelbase_mm}");
    }
    int track = jt->valueint, base = jw->valueint;
    cJSON_Delete(j);
    if (track < DIMS_TRACK_MIN_MM || track > DIMS_TRACK_MAX_MM ||
        base < DIMS_WHEELBASE_MIN_MM || base > DIMS_WHEELBASE_MAX_MM) {
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "range: <60..300> <90..360>");
    }
```
(Rest unchanged.)

- [ ] **Step 3: `main/ramp_api.c`** — replace the body-parse in `ramp_post`

Add `#include "cJSON.h"`. Replace:
```c
    char *end;
    long v = strtol(body, &end, 10);
    if (end == body || v < 0 || v > 2000) {
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "ramp_ms must be 0..2000");
    }
```
with:
```c
    cJSON *j = cJSON_Parse(body);
    cJSON *jv = cJSON_GetObjectItemCaseSensitive(j, "ramp_ms");
    if (!cJSON_IsNumber(jv)) { cJSON_Delete(j); return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "need {ramp_ms}"); }
    long v = jv->valueint;
    cJSON_Delete(j);
    if (v < 0 || v > 2000) {
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "ramp_ms must be 0..2000");
    }
```
(Rest — `ramp_set_ms`, NVS, `"ok"` — unchanged.)

- [ ] **Step 4: `main/trim_api.c`** — replace the body-parse in `trim_post`

Add `#include "cJSON.h"`. Replace:
```c
    char *end;
    long v = strtol(body, &end, 10);
    if (end == body || v < -30 || v > 30) {
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "trim_pct must be -30..30");
    }
```
with:
```c
    cJSON *j = cJSON_Parse(body);
    cJSON *jv = cJSON_GetObjectItemCaseSensitive(j, "trim_pct");
    if (!cJSON_IsNumber(jv)) { cJSON_Delete(j); return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "need {trim_pct}"); }
    long v = jv->valueint;
    cJSON_Delete(j);
    if (v < -30 || v > 30) {
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "trim_pct must be -30..30");
    }
```
(Rest unchanged.)

- [ ] **Step 5: `main/recovery_api.c`** — replace the body-parse in `recover_post`

Add `#include "cJSON.h"`. Replace:
```c
    // Body is two ints: "<0|1> <window_ms>" (avoids a JSON parser dependency).
    int en = -1; long win = -1;
    if (sscanf(body, "%d %ld", &en, &win) != 2 || (en != 0 && en != 1) ||
        win < RECOVER_WIN_MIN_MS || win > RECOVER_WIN_MAX_MS) {
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "need: <0|1> <1000..10000>");
    }
```
with:
```c
    // Body is JSON: {"enabled":true|false,"window_ms":..}
    cJSON *j = cJSON_Parse(body);
    cJSON *je = cJSON_GetObjectItemCaseSensitive(j, "enabled");
    cJSON *jw = cJSON_GetObjectItemCaseSensitive(j, "window_ms");
    if (!cJSON_IsBool(je) || !cJSON_IsNumber(jw)) {
        cJSON_Delete(j);
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "need {enabled,window_ms}");
    }
    int en = cJSON_IsTrue(je) ? 1 : 0;
    long win = jw->valueint;
    cJSON_Delete(j);
    if (win < RECOVER_WIN_MIN_MS || win > RECOVER_WIN_MAX_MS) {
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "window_ms 1000..10000");
    }
```
(Rest — `recovery_set_config`, NVS, `"ok"` — unchanged.)

- [ ] **Step 6: `main/calib_api.c`** — JSON for `/calib/save` and `/calib/spin`

Add `#include "cJSON.h"`. Replace the `calib_save` parse block:
```c
    unsigned p[4];
    int s[4];
    if (sscanf(b, "%u:%d,%u:%d,%u:%d,%u:%d",
               &p[0], &s[0], &p[1], &s[1], &p[2], &s[2], &p[3], &s[3]) != 8) {
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "bad format");
    }
    motors_config_t cfg = { .deadzone = 0.05f };
    for (int i = 0; i < 4; i++) {
        cfg.wheels[i].channel_pair = (uint8_t)p[i];
        cfg.wheels[i].sign = (int8_t)s[i];
    }
```
with:
```c
    // Body is JSON: {"wheels":[{"pair":..,"sign":..} × 4]} in FL,FR,RL,RR order.
    cJSON *j = cJSON_Parse(b);
    cJSON *arr = cJSON_GetObjectItemCaseSensitive(j, "wheels");
    if (!cJSON_IsArray(arr) || cJSON_GetArraySize(arr) != 4) {
        cJSON_Delete(j);
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "need {wheels:[4×{pair,sign}]}");
    }
    motors_config_t cfg = { .deadzone = 0.05f };
    for (int i = 0; i < 4; i++) {
        cJSON *w = cJSON_GetArrayItem(arr, i);
        cJSON *jp = cJSON_GetObjectItemCaseSensitive(w, "pair");
        cJSON *js = cJSON_GetObjectItemCaseSensitive(w, "sign");
        if (!cJSON_IsNumber(jp) || !cJSON_IsNumber(js)) {
            cJSON_Delete(j);
            return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "wheel needs {pair,sign}");
        }
        cfg.wheels[i].channel_pair = (uint8_t)jp->valueint;
        cfg.wheels[i].sign = (int8_t)js->valueint;
    }
    cJSON_Delete(j);
```
And replace the `calib_spin` parse (it currently `sscanf`s `"<pair>,<dir>"`). Find its body-parse:
```c
    int pair, dir;
    if (sscanf(b, "%d,%d", &pair, &dir) != 2 || pair < 0 || pair > 3 || (dir != 0 && dir != 1)) {
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "bad spin");
    }
```
with:
```c
    // Body is JSON: {"pair":0..3,"dir":0|1}
    cJSON *j = cJSON_Parse(b);
    cJSON *jp = cJSON_GetObjectItemCaseSensitive(j, "pair");
    cJSON *jd = cJSON_GetObjectItemCaseSensitive(j, "dir");
    if (!cJSON_IsNumber(jp) || !cJSON_IsNumber(jd)) {
        cJSON_Delete(j);
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "need {pair,dir}");
    }
    int pair = jp->valueint, dir = jd->valueint;
    cJSON_Delete(j);
    if (pair < 0 || pair > 3 || (dir != 0 && dir != 1)) {
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "pair 0..3, dir 0|1");
    }
```
(If `calib_spin`'s exact current text differs, match its real variable names — read the file first. The rest of both handlers is unchanged.)

- [ ] **Step 7: Syntax sanity (full build is Task 7)**

Run: `cd /Users/adamjohnson/VSCode/esp32-p4-car && for f in wheel dims ramp trim recovery calib; do cc -fsyntax-only -I main main/${f}_api.c 2>&1 | grep -v "file not found" | head -2; done; echo "syntax scan done"`
Expected: only IDF-header "file not found" noise (filtered) — no logic/syntax errors from the edits. (Real gate: `idf.py build` in Task 7.)

- [ ] **Step 8: Commit**

```bash
git add main/wheel_api.c main/dims_api.c main/ramp_api.c main/trim_api.c main/recovery_api.c main/calib_api.c
git commit -m "feat(fw): config POST bodies are JSON (cJSON on the cold path)"
```

---

### Task 5: iOS clients → JSON POST bodies

**Files:**
- Modify: `ios/ESP32Car/{WheelClient,DimsClient,RampClient,TrimClient,RecoverClient,CalibClient}.swift`, `ios/ESP32Car/ControlModel.swift`

- [ ] **Step 1: `WheelClient.set` body → JSON**

Replace:
```swift
        req.httpBody = "\(p.diameterMm) \(p.ppr) \(p.gearX100) \(p.quad)".data(using: .utf8)
```
with:
```swift
        req.httpBody = #"{"diameter_mm":\#(p.diameterMm),"ppr":\#(p.ppr),"gear_x100":\#(p.gearX100),"quad":\#(p.quad)}"#.data(using: .utf8)
```

- [ ] **Step 2: `DimsClient.set` body → JSON**

Replace:
```swift
        req.httpBody = "\(p.trackMm) \(p.wheelbaseMm)".data(using: .utf8)
```
with:
```swift
        req.httpBody = #"{"track_mm":\#(p.trackMm),"wheelbase_mm":\#(p.wheelbaseMm)}"#.data(using: .utf8)
```

- [ ] **Step 3: `RampClient.set` body → JSON**

Replace:
```swift
        req.httpBody = String(ms).data(using: .utf8)
```
with:
```swift
        req.httpBody = #"{"ramp_ms":\#(ms)}"#.data(using: .utf8)
```

- [ ] **Step 4: `TrimClient.set` body → JSON**

Replace:
```swift
        req.httpBody = String(pct).data(using: .utf8)
```
with:
```swift
        req.httpBody = #"{"trim_pct":\#(pct)}"#.data(using: .utf8)
```

- [ ] **Step 5: `RecoverClient.set` body → JSON**

Replace:
```swift
        req.httpBody = "\(enabled ? 1 : 0) \(windowMs)".data(using: .utf8)   // "<0|1> <ms>"
```
with:
```swift
        req.httpBody = #"{"enabled":\#(enabled),"window_ms":\#(windowMs)}"#.data(using: .utf8)
```

- [ ] **Step 6: `CalibClient.spin` body → JSON**

In `ios/ESP32Car/CalibClient.swift`, replace:
```swift
    func spin(pair: Int, dir: Int) async {
        await post("/calib/spin", body: "\(pair),\(dir)")
    }
```
with:
```swift
    func spin(pair: Int, dir: Int) async {
        await post("/calib/spin", body: #"{"pair":\#(pair),"dir":\#(dir)}"#)
    }
```

- [ ] **Step 7: `ControlModel.calibSaveBody` → JSON** (the `/calib/save` body builder; pure, host-tested)

Replace:
```swift
    static func calibSaveBody(_ a: [Corner: (pair: Int, sign: Int)]) -> String {
        Corner.allCases.map { c in
            let v = a[c] ?? (pair: 0, sign: 1)
            return "\(v.pair):\(v.sign)"
        }.joined(separator: ",")
    }
```
with:
```swift
    static func calibSaveBody(_ a: [Corner: (pair: Int, sign: Int)]) -> String {
        let wheels = Corner.allCases.map { c -> String in
            let v = a[c] ?? (pair: 0, sign: 1)
            return #"{"pair":\#(v.pair),"sign":\#(v.sign)}"#
        }.joined(separator: ",")
        return #"{"wheels":[\#(wheels)]}"#
    }
```

- [ ] **Step 8: Host-check `calibSaveBody` + build**

Write `/tmp/calib.swift`:
```swift
import Foundation
let a: [ControlModel.Corner: (pair: Int, sign: Int)] =
    [.fl:(0,1), .fr:(1,-1), .rl:(2,1), .rr:(3,-1)]
let s = ControlModel.calibSaveBody(a)
assert(s == #"{"wheels":[{"pair":0,"sign":1},{"pair":1,"sign":-1},{"pair":2,"sign":1},{"pair":3,"sign":-1}]}"#,
       "calibSaveBody: \(s)")
print("calibSaveBody json: ok")
```
Run: `cd /Users/adamjohnson/VSCode/esp32-p4-car && swiftc ios/ESP32Car/ControlModel.swift /tmp/calib.swift -o /tmp/cb && /tmp/cb`
Expected: `calibSaveBody json: ok`. (If `Corner`'s case names/order differ, read `ControlModel.swift` and adjust the seed to the real `Corner.allCases` order — the assertion must reflect FL,FR,RL,RR.)

Then build the app:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -4
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Commit**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/WheelClient.swift ios/ESP32Car/DimsClient.swift ios/ESP32Car/RampClient.swift ios/ESP32Car/TrimClient.swift ios/ESP32Car/RecoverClient.swift ios/ESP32Car/CalibClient.swift ios/ESP32Car/ControlModel.swift
git commit -m "feat(ios): config POST bodies + calib body are JSON"
```

---

### Task 6: Mock car → JSON

**Files:**
- Modify: `tools/mock_car/mock_car.py`

- [ ] **Step 1: `/ws` — parse JSON frames; config POSTs — parse JSON**

In `tools/mock_car/mock_car.py`:

(a) In the `ws` handler, the RX branch currently does `print(f"ws rx: {msg.data}")`. Replace it to parse + echo the parsed t,y (so the mock validates the JSON frame shape):
```python
            if msg.type == WSMsgType.TEXT:
                try:
                    f = json.loads(msg.data)
                    print(f"ws rx: t={f['t']} y={f['y']}")
                except Exception:
                    print(f"ws rx (bad json): {msg.data}")
```

(b) `wheel_post`:
```python
async def wheel_post(request):
    try:
        b = await request.json()
        d, ppr, gear, quad = b["diameter_mm"], b["ppr"], b["gear_x100"], b["quad"]
        if not (20 <= d <= 150 and 1 <= ppr <= 1000 and 100 <= gear <= 30000 and quad in (1, 2, 4)):
            raise ValueError
    except Exception:
        return web.Response(status=400, text="need {diameter_mm,ppr,gear_x100,quad}")
    STATE["wheel"] = {"diameter_mm": d, "ppr": ppr, "gear_x100": gear, "quad": quad}
    print(f"wheel: {STATE['wheel']}")
    return web.Response(text="ok")
```

(c) `dims_post`:
```python
async def dims_post(request):
    try:
        b = await request.json()
        track, base = b["track_mm"], b["wheelbase_mm"]
        if not (60 <= track <= 300 and 90 <= base <= 360):
            raise ValueError
    except Exception:
        return web.Response(status=400, text="need {track_mm,wheelbase_mm}")
    STATE["dims"] = {"track_mm": track, "wheelbase_mm": base}
    print(f"dims: {STATE['dims']}")
    return web.Response(text="ok")
```

(d) `ramp_post`:
```python
async def ramp_post(request):
    try:
        v = int((await request.json())["ramp_ms"])
        if not (0 <= v <= 2000):
            raise ValueError
    except Exception:
        return web.Response(status=400, text="need {ramp_ms}")
    STATE["ramp_ms"] = v
    print(f"ramp_ms: {v}")
    return web.Response(text="ok")
```

(e) `trim_post`:
```python
async def trim_post(request):
    try:
        v = int((await request.json())["trim_pct"])
        if not (-30 <= v <= 30):
            raise ValueError
    except Exception:
        return web.Response(status=400, text="need {trim_pct}")
    STATE["trim_pct"] = v
    print(f"trim_pct: {v}")
    return web.Response(text="ok")
```

(f) `recover` POST:
```python
async def recover_post(request):
    try:
        b = await request.json()
        en, win = bool(b["enabled"]), int(b["window_ms"])
        if not (1000 <= win <= 10000):
            raise ValueError
    except Exception:
        return web.Response(status=400, text="need {enabled,window_ms}")
    STATE["recover"] = {"enabled": en, "window_ms": win}
    print(f"recover: {STATE['recover']}")
    return web.Response(text="ok")
```

(g) `calib_save` + `calib_spin`:
```python
async def calib_save(request):
    try:
        wheels = (await request.json())["wheels"]
        assert isinstance(wheels, list) and len(wheels) == 4
        for w in wheels:
            int(w["pair"]); int(w["sign"])
    except Exception:
        return web.Response(status=400, text="need {wheels:[4×{pair,sign}]}")
    STATE["calibrated"] = True
    print(f"calib save: {wheels}")
    return web.Response(text="ok")


async def calib_spin(request):
    try:
        b = await request.json()
        print(f"calib spin: pair={b['pair']} dir={b['dir']}")
    except Exception:
        return web.Response(status=400, text="need {pair,dir}")
    return web.Response(text="ok")
```
(Match the existing handler names/shapes — read the current `recover_post`/`calib_save`/`calib_spin` and replace their bodies; keep the route registrations + any `STATE` keys they already use, e.g. whatever `recover`/`calibrated` keys exist.)

- [ ] **Step 2: Smoke-test the mock end-to-end**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/tools/mock_car
pkill -f mock_car.py 2>/dev/null; sleep 1
nohup .venv/bin/python -u mock_car.py >/tmp/mock_car.log 2>&1 & sleep 2
curl -s -X POST -H 'Content-Type: application/json' -d '{"track_mm":140,"wheelbase_mm":200}' http://127.0.0.1:8080/dims; echo
curl -s http://127.0.0.1:8080/dims; echo
curl -s -X POST -d '{"ramp_ms":500}' http://127.0.0.1:8080/ramp; echo
curl -s -X POST -d '{"wheels":[{"pair":0,"sign":1},{"pair":1,"sign":-1},{"pair":2,"sign":1},{"pair":3,"sign":-1}]}' http://127.0.0.1:8080/calib/save; echo
```
Expected: `ok`, then `{"track_mm": 140, "wheelbase_mm": 200}`, `ok`, `ok`.

- [ ] **Step 3: Commit**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add tools/mock_car/mock_car.py
git commit -m "test(mock): parse JSON /ws frames + JSON config POST bodies"
```

---

### Task 7: Full build + end-to-end verification

- [ ] **Step 1: Firmware build gate (the real cJSON compile check)**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
export PATH=/tmp/py313bin:$PATH
source ~/esp/esp-idf/export.sh >/dev/null 2>&1
idf.py build 2>&1 | tail -6
```
Expected: `Project build complete.` / `Built target app`. Fix any cJSON-handler compile error minimally (re-read the offending `*_api.c`), rebuild, and report the fix.

- [ ] **Step 2: Host tests + iOS build**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/test && make run 2>&1 | tail -12
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -3
```
Expected: `test_control_proto: all passed` (+ all suites), `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Live drive check (JSON frame reaches the mock over `/ws`)**

Launch the app in the simulator against the mock; tap the drive joystick (or run a trick), and confirm the mock log shows parsed JSON frames:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
curl -s http://127.0.0.1:8080/status >/dev/null 2>&1 || (cd tools/mock_car && nohup .venv/bin/python -u mock_car.py >/tmp/mock_car.log 2>&1 & sleep 2)
APP=$(find /tmp/ddata/Build/Products -name ESP32Car.app | head -1)
xcrun simctl boot "iPhone 17" 2>/dev/null; open -a Simulator
xcrun simctl install booted "$APP"; xcrun simctl terminate booted com.adamjohnson.esp32car 2>/dev/null
xcrun simctl launch booted com.adamjohnson.esp32car >/dev/null
sleep 6; grep "ws rx" /tmp/mock_car.log | tail -3
```
Expected: lines like `ws rx: t=0.0 y=0.0` (the 10 Hz idle stream) — confirms the app sends JSON frames the mock parses. (Driving from the simulator window produces non-zero t/y.)

- [ ] **Step 4: No commit** (verification only).

---

## Self-Review

**Spec coverage (transport half):**
- `/ws` app→car drive+tricks → `{"t","y"}`; zero-alloc pure parser; control_proto host-tested → Tasks 2, 3. ✅
- `/ws` car→app telemetry already JSON → unchanged (noted). ✅
- JSON-only, no back-compat (`control_parse_ty` removed) → Task 2. ✅
- Config POST bodies → JSON via cJSON (wheel/dims/ramp/trim/recover/calib save+spin) → Task 4. ✅
- cJSON dependency added → Task 1. ✅
- iOS clients send JSON; `ControlModel.frame`/`calibSaveBody` JSON (host-tested) → Tasks 3, 5. ✅
- Mock matches (JSON `/ws` + config POSTs) → Task 6. ✅
- GET/telemetry stay `snprintf` JSON → untouched (noted). ✅
- USB console `mix` untouched → not in scope. ✅
- **Storage stays typed NVS** (Phase 2) → explicitly out of scope here. ✅

**Placeholder scan:** none — full code per step; the two "match the real var names if different" notes (calib_spin, mock handler names) instruct reading the file, with the full replacement code given. ✅

**Type/name consistency:** `control_parse_json(const char*, float*, float*)` defined in Task 2, used in ws_control (Task 2) + test (Task 2); `control_parse_ty` fully removed; `ControlModel.frame` JSON (Task 3) used by existing callers; `calibSaveBody` JSON (Task 5) host-tested; cJSON API (`cJSON_Parse`/`cJSON_GetObjectItemCaseSensitive`/`cJSON_IsNumber`/`cJSON_IsBool`/`cJSON_IsTrue`/`cJSON_IsArray`/`cJSON_GetArrayItem`/`cJSON_GetArraySize`/`cJSON_Delete`) used consistently; `json` in REQUIRES (Task 1) makes `cJSON.h` available to Task 4. ✅

---

## Follow-up: Phase 2 (Storage)

A separate plan (`2026-06-17-json-everywhere-storage.md`) migrates NVS persistence to one JSON string per domain
(`wheel.c`/`dims.c`/`ramp.c`/`recovery.c`/`car.c` trim load + the api POST writes + `calibration.c` blob→string),
with the accepted reset-to-defaults on upgrade. Not part of this transport plan.
