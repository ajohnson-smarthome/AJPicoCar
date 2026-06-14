# Link-Loss Auto-Return Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On WS link loss, replay the last N seconds of commands in reverse (each negated) to retrace the path back into range, until the link returns — with a configurable window (1–10 s) and an on/off toggle in the iOS app.

**Architecture:** A new `recovery` module keeps a ring buffer of `{t, y, ts}` samples (one per WS frame), sized at compile time from `WINDOW_MAX_S × FRAME_HZ`. The watchdog calls `recovery_on_link_lost()` instead of `car_stop()`; a FreeRTOS retreat task snapshots the in-window samples and drives `car_drive(-t,-y)` for each segment's real duration, newest→oldest, aborting the instant a new frame arrives (seq change). Config (enabled + window) is NVS-persisted and exposed at `GET/POST /recover`; the iOS app gets a `RecoverView` screen (toggle + slider) reusing the unified `SplitScreen` car geometry.

**Tech Stack:** ESP-IDF 5.4 (C11, FreeRTOS task + portMUX, esp_http_server, NVS), Swift 6 / SwiftUI.

**Build/verify commands:**
- Host tests: `cd test && make run`
- Firmware: `mkdir -p /tmp/py313bin && ln -sf /opt/homebrew/bin/python3.13 /tmp/py313bin/python3 && export PATH=/tmp/py313bin:$PATH && source ~/esp/esp-idf/export.sh && idf.py build`
- iOS: `cd ios && xcodegen generate && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata`

---

### Task 1: `recovery.h` interface + pure helpers + host test (TDD)

**Files:**
- Create: `main/recovery.h`
- Create: `test/test_recovery.c`
- Modify: `test/Makefile`

- [ ] **Step 1: Write the failing host test**

Create `test/test_recovery.c`:

```c
#include "../main/recovery.h"
#include <assert.h>
#include <stdio.h>
#include <math.h>

static int feq(float a, float b) { return fabsf(a - b) < 1e-6f; }

int main(void) {
    // recovery_reverse negates both axes
    float rt, ry;
    recovery_reverse(0.8f, -0.3f, &rt, &ry);
    assert(feq(rt, -0.8f) && feq(ry, 0.3f));
    recovery_reverse(0.0f, 0.0f, &rt, &ry);
    assert(feq(rt, 0.0f) && feq(ry, 0.0f));

    // recovery_evict: sample is evicted when older than the window
    assert(recovery_evict(0, 6000, 5000) == true);    // 6s old, 5s window → evict
    assert(recovery_evict(2000, 6000, 5000) == false); // 4s old, 5s window → keep
    assert(recovery_evict(6000, 6000, 5000) == false); // same instant → keep
    // unsigned-rollover safe: now wrapped past UINT32_MAX
    assert(recovery_evict(0xFFFFFF00u, 0x00000064u, 5000) == false); // 356ms apart → keep
    assert(recovery_evict(0xFFFF0000u, 0x00010000u, 5000) == true);  // ~131s apart → evict

    printf("test_recovery: all passed\n");
    return 0;
}
```

- [ ] **Step 2: Create `main/recovery.h` (interface + pure inlines)**

```c
#ifndef RECOVERY_H
#define RECOVERY_H

#include <stdint.h>
#include <stdbool.h>

// Configurable history-window bounds (milliseconds).
#define RECOVER_WIN_MIN_MS 1000
#define RECOVER_WIN_MAX_MS 10000

// Load NVS config (enabled + window, defaults: ON, 5000 ms) and start the retreat
// task. Call once, BEFORE watchdog_init().
void recovery_init(void);

// Record one control frame into the breadcrumb buffer (call from the WS handler on
// each valid frame, alongside watchdog_feed). Also bumps the liveness sequence.
void recovery_note_command(float t, float y);

// Called by the watchdog when the link goes stale, INSTEAD of car_stop(). Decides:
// disabled / empty / stationary history → car_stop(); else → trigger the reverse replay.
void recovery_on_link_lost(void);

// Config getters/setters (RAM; the API layer persists to NVS).
void recovery_set_config(bool enabled, uint16_t window_ms);
void recovery_get_config(bool *enabled, uint16_t *window_ms);

// Pure (host-tested): reverse a command = negate both axes.
static inline void recovery_reverse(float t, float y, float *rt, float *ry) {
    *rt = -t;
    *ry = -y;
}

// Pure (host-tested): is a sample taken at `ts` older than `window_ms` before `now`?
// Unsigned subtraction → 32-bit millisecond-counter rollover is handled.
static inline bool recovery_evict(uint32_t ts, uint32_t now, uint16_t window_ms) {
    return (uint32_t)(now - ts) > window_ms;
}

#endif // RECOVERY_H
```

- [ ] **Step 3: Add the test to `test/Makefile`**

In `test/Makefile`, append `test_recovery` to the `all`, add a rule, and add it to `run` and `clean`:

- `all:` line → add ` test_recovery` at the end.
- New rule after `test_telemetry`:
```make
test_recovery: test_recovery.c
	$(CC) $(CFLAGS) -o $@ $^ $(LDLIBS)
```
- `run:` line → append ` && ./test_recovery`.
- `clean:` line → append ` test_recovery`.

- [ ] **Step 4: Run host tests**

Run: `cd test && make run`
Expected: ends with `test_recovery: all passed` and all prior suites still pass.

- [ ] **Step 5: Commit**

```bash
git add main/recovery.h test/test_recovery.c test/Makefile
git commit -m "feat(recovery): pure helpers (reverse, evict) + host test"
```

---

### Task 2: `recovery.c` — breadcrumb buffer + retreat task + config

**Files:**
- Create: `main/recovery.c`
- Modify: `main/CMakeLists.txt`

- [ ] **Step 1: Write `main/recovery.c`**

```c
#include "recovery.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "nvs.h"
#include "car.h"

static const char *TAG = "recovery";

#define FRAME_HZ      10                              // WS stream rate (phone streams held cmd at 10 Hz)
#define WINDOW_MAX_S  (RECOVER_WIN_MAX_MS / 1000)     // 10
#define MAX_SAMPLES   (WINDOW_MAX_S * FRAME_HZ * 3 / 2) // 150: 10 s @10 Hz + 50% jitter headroom
#define TICK_MS       30                              // replay granularity / reconnect-abort latency
#define TAIL_MS       400                             // cap for the newest segment's reverse duration
#define MOVE_EPS      0.02f                           // below this a sample counts as "stationary"

typedef struct { float t, y; uint32_t ts; } sample_t;

static sample_t        s_buf[MAX_SAMPLES];
static int             s_head = 0;     // next write index
static int             s_count = 0;    // valid samples
static volatile uint32_t s_seq = 0;    // bumped per frame; liveness signal
static bool            s_enabled = true;
static uint16_t        s_window_ms = 5000;
static TaskHandle_t    s_task = NULL;
static portMUX_TYPE    s_mux = portMUX_INITIALIZER_UNLOCKED;

static uint32_t now_ms(void) {
    return (uint32_t)(xTaskGetTickCount() * portTICK_PERIOD_MS);
}

void recovery_set_config(bool enabled, uint16_t window_ms) {
    if (window_ms < RECOVER_WIN_MIN_MS) window_ms = RECOVER_WIN_MIN_MS;
    if (window_ms > RECOVER_WIN_MAX_MS) window_ms = RECOVER_WIN_MAX_MS;
    taskENTER_CRITICAL(&s_mux);
    s_enabled = enabled;
    s_window_ms = window_ms;
    taskEXIT_CRITICAL(&s_mux);
}

void recovery_get_config(bool *enabled, uint16_t *window_ms) {
    taskENTER_CRITICAL(&s_mux);
    if (enabled) *enabled = s_enabled;
    if (window_ms) *window_ms = s_window_ms;
    taskEXIT_CRITICAL(&s_mux);
}

void recovery_note_command(float t, float y) {
    uint32_t now = now_ms();
    taskENTER_CRITICAL(&s_mux);
    s_buf[s_head] = (sample_t){ .t = t, .y = y, .ts = now };
    s_head = (s_head + 1) % MAX_SAMPLES;
    if (s_count < MAX_SAMPLES) s_count++;
    s_seq++;
    taskEXIT_CRITICAL(&s_mux);
}

// Snapshot in-window samples newest→oldest into out[] (cap MAX_SAMPLES). Returns count.
// *seq receives the liveness sequence at snapshot time.
static int snapshot(sample_t *out, uint32_t now, uint32_t *seq) {
    int n = 0;
    taskENTER_CRITICAL(&s_mux);
    *seq = s_seq;
    uint16_t win = s_window_ms;
    for (int k = 0; k < s_count; k++) {
        int idx = (s_head - 1 - k + MAX_SAMPLES) % MAX_SAMPLES;  // newest → oldest
        if (recovery_evict(s_buf[idx].ts, now, win)) break;       // older than window → stop
        out[n++] = s_buf[idx];
    }
    taskEXIT_CRITICAL(&s_mux);
    return n;
}

static bool any_motion(const sample_t *s, int n) {
    for (int i = 0; i < n; i++) {
        if (s[i].t > MOVE_EPS || s[i].t < -MOVE_EPS ||
            s[i].y > MOVE_EPS || s[i].y < -MOVE_EPS) return true;
    }
    return false;
}

static void retreat_task(void *arg) {
    (void)arg;
    static sample_t snap[MAX_SAMPLES];   // task-owned; not on the small task stack
    for (;;) {
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);   // wait for a link-loss trigger

        uint32_t t_loss = now_ms();
        uint32_t snap_seq;
        int n = snapshot(snap, t_loss, &snap_seq);
        if (n == 0 || !any_motion(snap, n)) { car_stop(); continue; }

        ESP_LOGW(TAG, "link lost — retracing %d samples in reverse", n);
        bool aborted = false;
        for (int i = 0; i < n && !aborted; i++) {
            float rt, ry;
            recovery_reverse(snap[i].t, snap[i].y, &rt, &ry);
            uint32_t dur = (i == 0)
                ? (uint32_t)(t_loss - snap[0].ts)            // newest held until link loss
                : (uint32_t)(snap[i - 1].ts - snap[i].ts);   // until the next-newer frame
            if (i == 0 && dur > TAIL_MS) dur = TAIL_MS;       // cap the open segment
            car_drive(rt, ry);
            for (uint32_t waited = 0; waited < dur; ) {
                if (s_seq != snap_seq) { aborted = true; break; }  // a frame arrived → link back
                uint32_t step = (dur - waited < TICK_MS) ? (dur - waited) : TICK_MS;
                vTaskDelay(pdMS_TO_TICKS(step));
                waited += step;
            }
        }
        if (aborted) ESP_LOGI(TAG, "link returned — handing control back");
        else { car_stop(); ESP_LOGI(TAG, "retrace exhausted — stopped"); }
    }
}

void recovery_on_link_lost(void) {
    if (!s_enabled) { car_stop(); return; }   // feature off → plain stop (old watchdog behavior)
    if (s_task) xTaskNotifyGive(s_task);       // hand off to the retreat task
    else car_stop();
}

void recovery_init(void) {
    nvs_handle_t h;
    if (nvs_open("car", NVS_READONLY, &h) == ESP_OK) {
        int8_t en;
        if (nvs_get_i8(h, "recover_en", &en) == ESP_OK) s_enabled = (en != 0);
        uint16_t win;
        if (nvs_get_u16(h, "recover_win", &win) == ESP_OK &&
            win >= RECOVER_WIN_MIN_MS && win <= RECOVER_WIN_MAX_MS) s_window_ms = win;
        nvs_close(h);
    }
    BaseType_t ok = xTaskCreate(retreat_task, "recovery", 3072, NULL, 5, &s_task);
    if (ok != pdPASS) ESP_LOGE(TAG, "retreat task create failed");
    ESP_LOGI(TAG, "recovery %s, window %u ms", s_enabled ? "on" : "off", s_window_ms);
}
```

- [ ] **Step 2: Add `recovery.c` to `main/CMakeLists.txt`**

In the `SRCS` list, add `"recovery.c"` (e.g. right after `"watchdog.c"`).

- [ ] **Step 3: Build firmware**

Run the firmware build command (see header).
Expected: `Project build complete` with no errors.

- [ ] **Step 4: Commit**

```bash
git add main/recovery.c main/CMakeLists.txt
git commit -m "feat(recovery): breadcrumb buffer + reverse-replay retreat task + NVS config"
```

---

### Task 3: Wire recovery into watchdog, ws_control, app_main

**Files:**
- Modify: `main/watchdog.c`
- Modify: `main/ws_control.c`
- Modify: `main/main.c`

- [ ] **Step 1: Watchdog calls recovery instead of car_stop**

In `main/watchdog.c`, change the include `#include "car.h"` to `#include "recovery.h"` and replace `car_stop();` in `wdt_cb` with `recovery_on_link_lost();`.
(The log line, `s_trips++`, and `s_armed = false` stay.)

- [ ] **Step 2: WS handler records each frame**

In `main/ws_control.c`, add `#include "recovery.h"` (after `#include "watchdog.h"`), and in the successful-parse branch add the note call:

```c
    if (control_parse_ty((const char *)buf, &t, &y) == 0) {
        s_frames++;
        watchdog_feed();
        recovery_note_command(t, y);
        car_drive(t, y);
    } else {
```

- [ ] **Step 3: Init recovery before the watchdog**

In `main/main.c`, add `#include "recovery.h"` with the other module includes, and call `recovery_init();` on the line immediately before `watchdog_init(WDT_TIMEOUT_MS);`:

```c
    ESP_ERROR_CHECK(telemetry_start());
    recovery_init();                       // breadcrumb buffer; must precede the watchdog
    watchdog_init(WDT_TIMEOUT_MS);
```

- [ ] **Step 4: Build firmware**

Run the firmware build command.
Expected: builds clean.

- [ ] **Step 5: Commit**

```bash
git add main/watchdog.c main/ws_control.c main/main.c
git commit -m "feat(recovery): watchdog→recovery_on_link_lost; ws records frames; init in app_main"
```

---

### Task 4: REST `/recover` (GET/POST) + NVS persist

**Files:**
- Create: `main/recovery_api.h`
- Create: `main/recovery_api.c`
- Modify: `main/CMakeLists.txt`
- Modify: `main/main.c`
- Modify: `main/http_server.c`

- [ ] **Step 1: Create `main/recovery_api.h`**

```c
#ifndef RECOVERY_API_H
#define RECOVERY_API_H

#include "esp_err.h"

// Register GET/POST /recover on the shared httpd. Call after http_server_start().
esp_err_t recovery_api_start(void);

#endif // RECOVERY_API_H
```

- [ ] **Step 2: Create `main/recovery_api.c`**

```c
#include "recovery_api.h"
#include <stdio.h>
#include "esp_http_server.h"
#include "esp_log.h"
#include "esp_check.h"
#include "nvs.h"
#include "http_server.h"
#include "recovery.h"

static const char *TAG = "recovery_api";

static esp_err_t recover_get(httpd_req_t *req) {
    bool en; uint16_t win;
    recovery_get_config(&en, &win);
    char buf[48];
    int n = snprintf(buf, sizeof(buf), "{\"enabled\":%s,\"window_ms\":%u}",
                     en ? "true" : "false", win);
    httpd_resp_set_type(req, "application/json");
    return httpd_resp_send(req, buf, n);
}

static esp_err_t recover_post(httpd_req_t *req) {
    char body[32] = {0};
    int len = httpd_req_recv(req, body, sizeof(body) - 1);
    if (len <= 0) return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "empty");
    // Body is two ints: "<0|1> <window_ms>" (avoids a JSON parser dependency).
    int en = -1; long win = -1;
    if (sscanf(body, "%d %ld", &en, &win) != 2 || (en != 0 && en != 1) ||
        win < RECOVER_WIN_MIN_MS || win > RECOVER_WIN_MAX_MS) {
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "need: <0|1> <1000..10000>");
    }
    recovery_set_config(en == 1, (uint16_t)win);
    nvs_handle_t h;
    if (nvs_open("car", NVS_READWRITE, &h) == ESP_OK) {
        nvs_set_i8(h, "recover_en", (int8_t)en);
        nvs_set_u16(h, "recover_win", (uint16_t)win);
        esp_err_t e = nvs_commit(h);
        if (e != ESP_OK) ESP_LOGW(TAG, "recover save failed: %s", esp_err_to_name(e));
        nvs_close(h);
    }
    return httpd_resp_sendstr(req, "ok");
}

esp_err_t recovery_api_start(void) {
    httpd_handle_t server = http_server_get_handle();
    if (server == NULL) { ESP_LOGE(TAG, "http server not started"); return ESP_FAIL; }
    httpd_uri_t g = { .uri = "/recover", .method = HTTP_GET,  .handler = recover_get };
    httpd_uri_t p = { .uri = "/recover", .method = HTTP_POST, .handler = recover_post };
    ESP_RETURN_ON_ERROR(httpd_register_uri_handler(server, &g), TAG, "reg GET /recover");
    ESP_RETURN_ON_ERROR(httpd_register_uri_handler(server, &p), TAG, "reg POST /recover");
    return ESP_OK;
}
```

- [ ] **Step 3: Add `recovery_api.c` to `main/CMakeLists.txt` SRCS** (after `"trim_api.c"`).

- [ ] **Step 4: Register in `main/main.c`**

Add `#include "recovery_api.h"` with the other API includes, and after `ESP_ERROR_CHECK(trim_api_start());` add:
```c
    ESP_ERROR_CHECK(recovery_api_start());
```

- [ ] **Step 5: Bump the handler-count comment in `main/http_server.c`**

Update the comment near `max_uri_handlers` from "We register 11 URI handlers (...)" to note 13 and add `/recover*2`:
```c
    // We register 13 URI handlers (/, /ws, /calib*3, /status, /ota, /ramp*2, /trim*2, /recover*2),
```
(The `config.max_uri_handlers = 20;` line is unchanged — still ample headroom.)

- [ ] **Step 6: Build firmware**

Run the firmware build command.
Expected: builds clean.

- [ ] **Step 7: Commit**

```bash
git add main/recovery_api.c main/recovery_api.h main/CMakeLists.txt main/main.c main/http_server.c
git commit -m "feat(recovery): GET/POST /recover (enabled + window) with NVS persist"
```

---

### Task 5: iOS `RecoverClient`

**Files:**
- Create: `ios/ESP32Car/RecoverClient.swift`

- [ ] **Step 1: Write the client**

```swift
import Foundation

/// Reads/writes the car's link-loss auto-return config via GET/POST /recover.
struct RecoverClient {
    func get() async -> (enabled: Bool, windowMs: Int)? {
        guard let url = URL(string: CarHost.httpBase + "/recover") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let enabled = j["enabled"] as? Bool,
              let win = j["window_ms"] as? Int else { return nil }
        return (enabled, win)
    }

    @discardableResult
    func set(enabled: Bool, windowMs: Int) async -> Bool {
        guard let url = URL(string: CarHost.httpBase + "/recover") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = "\(enabled ? 1 : 0) \(windowMs)".data(using: .utf8)   // "<0|1> <ms>"
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }
}
```

- [ ] **Step 2: Build iOS**

Run the iOS build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/ESP32Car/RecoverClient.swift
git commit -m "feat(ios): RecoverClient — GET/POST /recover"
```

---

### Task 6: iOS `RecoverView` + `RecoverCarView` + Settings link + strings

**Files:**
- Create: `ios/ESP32Car/RecoverView.swift`
- Modify: `ios/ESP32Car/SettingsView.swift`
- Modify: `ios/ESP32Car/L.swift`
- Modify: `ios/ESP32Car/Resources/ru.lproj/Localizable.strings`
- Modify: `ios/ESP32Car/GalleryView.swift`

- [ ] **Step 1: Create `ios/ESP32Car/RecoverView.swift`**

`RecoverCarView` mirrors `RampCarView`/`TrimCarView` geometry exactly (Canvas, `center = size/2`, body 34×72, dark corner wheels 11×15, windshield; `.frame(width:120, height:210).scaleEffect(1.6)`) so the car centres and sizes identically to every other screen. A dashed "retrace" trail is drawn behind the car (downward from its rear), dimmed when the feature is off.

```swift
import SwiftUI

/// Link-loss auto-return: toggle + history-window slider (1–10 s). Split layout like RampView.
struct RecoverView: View {
    let palette: Palette
    @State private var enabled = true
    @State private var windowSec = 5         // live slider value
    @Environment(\.dismiss) private var dismiss
    private var p: Palette { palette }

    var body: some View {
        SplitScreen(palette: p, title: L.recoverTitle, onBack: { dismiss() }) {
            RecoverCarView(active: enabled, palette: p)
        } right: {
            rightPanel
        }
        .task {
            if let c = await RecoverClient().get() {
                enabled = c.enabled
                windowSec = max(1, min(10, c.windowMs / 1000))
            }
        }
    }

    private func save() {
        Task { await RecoverClient().set(enabled: enabled, windowMs: windowSec * 1000) }
    }

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.recoverHeadline).font(.system(size: 20, weight: .semibold)).foregroundStyle(p.text)
            Toggle(L.recoverEnable, isOn: $enabled)
                .tint(p.accent)
                .frame(width: 230)
                .onChange(of: enabled) { _ in save() }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(L.recoverWindow).font(.system(size: 12)).foregroundStyle(p.muted)
                    Spacer()
                    Text(L.recoverWindowValue(windowSec)).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(enabled ? p.accent : p.muted).monospacedDigit()
                }
                Slider(value: Binding(
                    get: { Double(windowSec) },
                    set: { windowSec = Int($0.rounded()) }
                ), in: 1...10, step: 1) { editing in
                    if !editing { save() }
                }
                .tint(p.accent)
                .disabled(!enabled)
            }
            .frame(width: 230)
            .opacity(enabled ? 1 : 0.4)
            Text(enabled ? L.recoverSubOn : L.recoverSubOff)
                .font(.system(size: 12)).foregroundStyle(p.muted)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 250, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Centred reference car (same geometry as RampCarView/TrimCarView) with a dashed
/// "retrace" trail behind it. The car is NOT moved — only the trail signals the feature.
struct RecoverCarView: View {
    let active: Bool
    let palette: Palette

    private var metal: Color { palette.metal }
    private let carW: CGFloat = 34
    private let carLen: CGFloat = 72
    private let wheelW: CGFloat = 11
    private let wheelH: CGFloat = 15

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            drawTrail(&ctx, center: center)
            drawCar(&ctx, center: center)
            let wx = carW / 2 + 1
            let wy = carLen / 2 - 16
            for dx in [-wx, wx] {
                for dy in [-wy, wy] {
                    let r = CGRect(x: center.x + dx - wheelW / 2, y: center.y + dy - wheelH / 2,
                                   width: wheelW, height: wheelH)
                    ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(metal))
                }
            }
        }
        .frame(width: 120, height: 210)
        .scaleEffect(1.6)
    }

    private func drawCar(_ ctx: inout GraphicsContext, center: CGPoint) {
        let body = CGRect(x: center.x - carW / 2, y: center.y - carLen / 2, width: carW, height: carLen)
        let bp = Path(roundedRect: body, cornerRadius: 11)
        ctx.fill(bp, with: .color(palette.bg))
        ctx.fill(bp, with: .color(palette.panel))
        ctx.stroke(bp, with: .color(metal), lineWidth: 1)
        let wind = CGRect(x: center.x - 11, y: body.minY + 7, width: 22, height: 9)
        ctx.fill(Path(roundedRect: wind, cornerRadius: 3), with: .color(palette.bg.opacity(0.85)))
    }

    // Dashed trail behind the car (downward from the rear), with a small reverse chevron.
    private func drawTrail(_ ctx: inout GraphicsContext, center: CGPoint) {
        let startY = center.y + carLen / 2 + 6
        let endY = startY + 58
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: startY))
        path.addLine(to: CGPoint(x: center.x, y: endY))
        ctx.stroke(path, with: .color(palette.accent.opacity(active ? 0.55 : 0.12)),
                   style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 7]))
        var chev = Path()
        chev.move(to: CGPoint(x: center.x - 5, y: endY - 5))
        chev.addLine(to: CGPoint(x: center.x, y: endY))
        chev.addLine(to: CGPoint(x: center.x + 5, y: endY - 5))
        ctx.stroke(chev, with: .color(palette.accent.opacity(active ? 0.7 : 0.12)),
                   style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
}
```

- [ ] **Step 2: Add the Settings link**

In `ios/ESP32Car/SettingsView.swift`, after the `TrimView` `NavigationLink` block (before the `FirmwareView` one), insert:

```swift
                    NavigationLink {
                        RecoverView(palette: palette)
                    } label: {
                        Label(L.recoverTitle, systemImage: "arrow.uturn.backward")
                            .foregroundStyle(palette.text)
                    }
                    .listRowBackground(palette.panel)
```

- [ ] **Step 3: Add `L` accessors**

In `ios/ESP32Car/L.swift`, after the trim entries (around line 65), add:

```swift
    static var recoverTitle: String { s("recover.title") }
    static var recoverHeadline: String { s("recover.headline") }
    static var recoverEnable: String { s("recover.enable") }
    static var recoverWindow: String { s("recover.window") }
    static func recoverWindowValue(_ sec: Int) -> String { s("recover.windowValue", sec) }
    static var recoverSubOn: String { s("recover.subOn") }
    static var recoverSubOff: String { s("recover.subOff") }
```

- [ ] **Step 4: Add the strings**

In `ios/ESP32Car/Resources/ru.lproj/Localizable.strings`, after the trim block, add:

```
"recover.title"       = "Авто-возврат";
"recover.headline"    = "Авто-возврат при обрыве";
"recover.enable"      = "Включить";
"recover.window"      = "Окно истории";
"recover.windowValue" = "%d с";
"recover.subOn"       = "При потере связи машинка отматывает недавний путь назад, пока не вернётся в зону.";
"recover.subOff"      = "Выключено — при обрыве машинка просто останавливается.";
```

- [ ] **Step 5: Add a gallery frame**

In `ios/ESP32Car/GalleryView.swift`, add to the `makeFrames` array, right after the `("Trim", ...)` entry:

```swift
            ("Recover",                 AnyView(NavigationStack { RecoverView(palette: p) })),
```

- [ ] **Step 6: Build iOS**

Run: `cd ios && xcodegen generate && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add ios/ESP32Car/RecoverView.swift ios/ESP32Car/SettingsView.swift ios/ESP32Car/L.swift ios/ESP32Car/Resources/ru.lproj/Localizable.strings ios/ESP32Car/GalleryView.swift
git commit -m "feat(ios): RecoverView (toggle + window slider) + Settings link + strings"
```

---

### Task 7: Final verification (host tests, firmware build, gallery)

**Files:**
- (Temporary, not committed) `ios/ESP32Car/GalleryView.swift`

- [ ] **Step 1: Host tests**

Run: `cd test && make run`
Expected: all suites pass, including `test_recovery: all passed`.

- [ ] **Step 2: Firmware build**

Run the firmware build command.
Expected: `Project build complete`, app size within the partition.

- [ ] **Step 3: Visual check of the Recover screen (gallery, both themes)**

Find the "Recover" frame index N in `GalleryView.swift` (count the array entries). Temporarily set `@State private var index = N`, build for the simulator, install, launch with `--args -gallery`, screenshot in dark and light:

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
xcrun simctl boot "iPhone 17" 2>/dev/null; sleep 2
# set index to the Recover frame, then:
( cd ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -1 )
DD=$(find /tmp/ddata/Build/Products -name ESP32Car.app | head -1)
xcrun simctl install booted "$DD"
xcrun simctl ui booted appearance dark
xcrun simctl terminate booted com.adamjohnson.esp32car 2>/dev/null
xcrun simctl launch booted com.adamjohnson.esp32car --args -gallery
sleep 3; xcrun simctl io booted screenshot /tmp/recover-dark.png
xcrun simctl ui booted appearance light
xcrun simctl terminate booted com.adamjohnson.esp32car 2>/dev/null
xcrun simctl launch booted com.adamjohnson.esp32car --args -gallery
sleep 3; xcrun simctl io booted screenshot /tmp/recover-light.png
```

Read both. Expected: car centred at the same vertical position and size as the other split screens; dashed trail behind it; header «Авто-возврат» + chevron; toggle + window slider on the right; readable in both themes.

- [ ] **Step 4: Revert the temporary gallery index**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
sed -i '' 's/@State private var index = [0-9]*/@State private var index = 0/' ios/ESP32Car/GalleryView.swift
git diff --stat   # expect: no tracked changes
```

No commit (verification only; all feature changes already committed in Tasks 1–6).
