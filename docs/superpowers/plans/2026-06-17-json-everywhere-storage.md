# JSON Everywhere — Phase 2: Storage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist every config domain in NVS as a single JSON string per domain (instead of typed `u16`/`i8` keys and the calibration blob), serialized with `snprintf` and parsed at boot with cJSON.

**Architecture:** Each owning module gains a `*_save()` that `snprintf`s its struct to JSON and `nvs_set_str`s it under one key; `*_init`/`*_load` does `nvs_get_str` → `cJSON_Parse` → clamp/validate (reusing the existing `*_set`/`*_valid`), else keeps the compiled defaults. The api POST handlers drop their inline `nvs_set_*` blocks and call `*_save()`. Firmware-only — no wire/iOS change (Phase 1 did transport).

**Tech Stack:** ESP-IDF 5.4 (C, cJSON — already in REQUIRES), `cc` host tests for the still-pure `calibration_valid`.

**Spec:** `docs/superpowers/specs/2026-06-17-json-everywhere-design.md`

**Branch:** `feat/json-everywhere`

**Upgrade note (accepted, per spec):** the new JSON string keys don't match the old typed keys, so the first boot after flashing this firmware finds none → every domain resets to its compiled default (calibration's mandatory wizard re-runs). No migration of old keys. The modules whose `.c` is NOT host-compiled (wheel/dims/ramp/recovery/calibration — their `test_*` targets only link the test file + the header inline) may freely `#include "cJSON.h"`.

---

## File Structure

- `main/wheel.{c,h}`, `main/dims.{c,h}`, `main/ramp.c`, `main/recovery.c`, `main/calibration.c` — **modify**: JSON `_save()` + JSON parse in `_init`/`_load`.
- `main/car.{c,h}` — **modify**: trim's persisted value (lives in `car.c`) loads JSON; new `car_save_trim()`.
- `main/wheel_api.c`, `main/dims_api.c`, `main/ramp_api.c`, `main/recovery_api.c`, `main/trim_api.c` — **modify**: drop the inline `nvs_set_*` block, call the module `*_save()`. (`calib_api.c` already calls `calibration_save` — unchanged.)

NVS string keys (one per domain): `wheel`, `dims`, `ramp`, `recover`, `trim`, `calib`. (Old typed keys `wheel_d`/`track_mm`/`ramp_ms`/… and the `calib` blob are orphaned → default reset on upgrade.)

---

### Task 1: `wheel` + `dims` storage → JSON string

**Files:**
- Modify: `main/wheel.h`, `main/wheel.c`, `main/wheel_api.c`, `main/dims.h`, `main/dims.c`, `main/dims_api.c`

- [ ] **Step 1: Declare `wheel_save` in `main/wheel.h`** — add after the `void wheel_set(const wheel_params_t *in);` line:
```c
// Serialize the current params to a JSON string and persist to NVS (one key).
void wheel_save(void);
```

- [ ] **Step 2: Rewrite `wheel_init` + add `wheel_save` in `main/wheel.c`.** Add `#include "cJSON.h"` and `#include <stdio.h>` at the top. Replace the `wheel_init` function:
```c
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
with:
```c
// JSON string in NVS under "wheel": {"diameter_mm":..,"ppr":..,"gear_x100":..,"quad":..}
void wheel_save(void) {
    char buf[96];
    snprintf(buf, sizeof(buf), "{\"diameter_mm\":%u,\"ppr\":%u,\"gear_x100\":%u,\"quad\":%u}",
             s_params.diameter_mm, s_params.ppr, s_params.gear_x100, s_params.quad);
    nvs_handle_t h;
    if (nvs_open("car", NVS_READWRITE, &h) == ESP_OK) {
        esp_err_t e = nvs_set_str(h, "wheel", buf);
        if (e == ESP_OK) e = nvs_commit(h);
        if (e != ESP_OK) ESP_LOGW(TAG, "wheel save failed: %s", esp_err_to_name(e));
        nvs_close(h);
    }
}

void wheel_init(void) {
    nvs_handle_t h;
    if (nvs_open("car", NVS_READONLY, &h) == ESP_OK) {
        char buf[96];
        size_t len = sizeof(buf);
        if (nvs_get_str(h, "wheel", buf, &len) == ESP_OK) {
            cJSON *j = cJSON_Parse(buf);
            cJSON *jd = cJSON_GetObjectItemCaseSensitive(j, "diameter_mm");
            cJSON *jp = cJSON_GetObjectItemCaseSensitive(j, "ppr");
            cJSON *jg = cJSON_GetObjectItemCaseSensitive(j, "gear_x100");
            cJSON *jq = cJSON_GetObjectItemCaseSensitive(j, "quad");
            if (cJSON_IsNumber(jd) && cJSON_IsNumber(jp) && cJSON_IsNumber(jg) && cJSON_IsNumber(jq)) {
                wheel_params_t w = { .diameter_mm = (uint16_t)jd->valueint, .ppr = (uint16_t)jp->valueint,
                                     .gear_x100 = (uint16_t)jg->valueint, .quad = (uint8_t)jq->valueint };
                wheel_set(&w);   // clamps + applies
            }
            cJSON_Delete(j);
        }
        nvs_close(h);
    }
    ESP_LOGI(TAG, "wheel d=%u mm ppr=%u gear=%u/100 quad=%u (cpr %.0f)",
             s_params.diameter_mm, s_params.ppr, s_params.gear_x100, s_params.quad,
             (double)wheel_cpr(&s_params));
}
```

- [ ] **Step 3: `main/wheel_api.c` — call `wheel_save()` instead of the inline NVS block.** Replace:
```c
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
```
with:
```c
    wheel_set(&w);
    wheel_save();
    return httpd_resp_sendstr(req, "ok");
```

- [ ] **Step 4: Declare `dims_save` in `main/dims.h`** — add after `void dims_set(const dims_params_t *in);`:
```c
// Serialize the current dims to a JSON string and persist to NVS (one key).
void dims_save(void);
```

- [ ] **Step 5: Rewrite `dims_init` + add `dims_save` in `main/dims.c`.** Add `#include "cJSON.h"` and `#include <stdio.h>`. Replace `dims_init`:
```c
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
with:
```c
// JSON string in NVS under "dims": {"track_mm":..,"wheelbase_mm":..}
void dims_save(void) {
    char buf[64];
    snprintf(buf, sizeof(buf), "{\"track_mm\":%u,\"wheelbase_mm\":%u}",
             s_params.track_mm, s_params.wheelbase_mm);
    nvs_handle_t h;
    if (nvs_open("car", NVS_READWRITE, &h) == ESP_OK) {
        esp_err_t e = nvs_set_str(h, "dims", buf);
        if (e == ESP_OK) e = nvs_commit(h);
        if (e != ESP_OK) ESP_LOGW(TAG, "dims save failed: %s", esp_err_to_name(e));
        nvs_close(h);
    }
}

void dims_init(void) {
    nvs_handle_t h;
    if (nvs_open("car", NVS_READONLY, &h) == ESP_OK) {
        char buf[64];
        size_t len = sizeof(buf);
        if (nvs_get_str(h, "dims", buf, &len) == ESP_OK) {
            cJSON *j = cJSON_Parse(buf);
            cJSON *jt = cJSON_GetObjectItemCaseSensitive(j, "track_mm");
            cJSON *jw = cJSON_GetObjectItemCaseSensitive(j, "wheelbase_mm");
            if (cJSON_IsNumber(jt) && cJSON_IsNumber(jw)) {
                dims_params_t d = { .track_mm = (uint16_t)jt->valueint, .wheelbase_mm = (uint16_t)jw->valueint };
                dims_set(&d);   // clamps + applies
            }
            cJSON_Delete(j);
        }
        nvs_close(h);
    }
    ESP_LOGI(TAG, "dims track=%u mm wheelbase=%u mm", s_params.track_mm, s_params.wheelbase_mm);
}
```

- [ ] **Step 6: `main/dims_api.c` — call `dims_save()`.** Replace the inline NVS block:
```c
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
```
with:
```c
    dims_params_t d = { .track_mm = (uint16_t)track, .wheelbase_mm = (uint16_t)base };
    dims_set(&d);
    dims_save();
    return httpd_resp_sendstr(req, "ok");
```

- [ ] **Step 7: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add main/wheel.h main/wheel.c main/wheel_api.c main/dims.h main/dims.c main/dims_api.c
git commit -m "feat(fw): wheel + dims persist as JSON strings in NVS"
```
(Build is verified in Task 5. Leftover `#include "nvs.h"` in the api files is harmless; leave it.)

---

### Task 2: `ramp` + `recovery` storage → JSON string

**Files:**
- Modify: `main/ramp.c`, `main/ramp.h`, `main/ramp_api.c`, `main/recovery.c`, `main/recovery.h`, `main/recovery_api.c`

- [ ] **Step 1: Declare `ramp_save` in `main/ramp.h`** — add near the other `ramp_*` prototypes:
```c
// Persist the current ramp_ms as a JSON string in NVS.
void ramp_save(void);
```

- [ ] **Step 2: `main/ramp.c` — JSON `ramp_save` + JSON parse in `ramp_init`.** Add `#include "cJSON.h"` (stdio is already pulled via string.h? add `#include <stdio.h>` to be safe). Add this function above `ramp_init`:
```c
void ramp_save(void) {
    char buf[32];
    snprintf(buf, sizeof(buf), "{\"ramp_ms\":%u}", ramp_get_ms());
    nvs_handle_t h;
    if (nvs_open(NS, NVS_READWRITE, &h) == ESP_OK) {
        esp_err_t e = nvs_set_str(h, "ramp", buf);
        if (e == ESP_OK) e = nvs_commit(h);
        if (e != ESP_OK) ESP_LOGW(TAG, "ramp save failed: %s", esp_err_to_name(e));
        nvs_close(h);
    }
}
```
In `ramp_init`, replace the NVS read block:
```c
    nvs_handle_t h;
    if (nvs_open(NS, NVS_READONLY, &h) == ESP_OK) {
        uint16_t v;
        if (nvs_get_u16(h, KEY, &v) == ESP_OK && v <= RAMP_MS_MAX) s_ramp_ms = v;
        nvs_close(h);
    }
```
with:
```c
    nvs_handle_t h;
    if (nvs_open(NS, NVS_READONLY, &h) == ESP_OK) {
        char buf[32];
        size_t len = sizeof(buf);
        if (nvs_get_str(h, "ramp", buf, &len) == ESP_OK) {
            cJSON *j = cJSON_Parse(buf);
            cJSON *jv = cJSON_GetObjectItemCaseSensitive(j, "ramp_ms");
            if (cJSON_IsNumber(jv) && jv->valueint >= 0 && jv->valueint <= RAMP_MS_MAX) {
                s_ramp_ms = (uint16_t)jv->valueint;
            }
            cJSON_Delete(j);
        }
        nvs_close(h);
    }
```
(The old `#define KEY "ramp_ms"` is now unused; leave it or delete it — if you delete it, ensure nothing else references `KEY`. Simplest: leave it.)

- [ ] **Step 3: `main/ramp_api.c` — call `ramp_save()`.** Replace the inline NVS block:
```c
    ramp_set_ms((uint16_t)v);
    nvs_handle_t h;
    if (nvs_open("car", NVS_READWRITE, &h) == ESP_OK) {
        esp_err_t e = nvs_set_u16(h, "ramp_ms", (uint16_t)v);
        if (e == ESP_OK) e = nvs_commit(h);
        if (e != ESP_OK) ESP_LOGW(TAG, "ramp save failed: %s", esp_err_to_name(e));
        nvs_close(h);
    }
    return httpd_resp_sendstr(req, "ok");
```
with:
```c
    ramp_set_ms((uint16_t)v);
    ramp_save();
    return httpd_resp_sendstr(req, "ok");
```

- [ ] **Step 4: Declare `recovery_save` in `main/recovery.h`** — add near the other prototypes:
```c
// Persist the current enabled+window config as a JSON string in NVS.
void recovery_save(void);
```

- [ ] **Step 5: `main/recovery.c` — JSON `recovery_save` + JSON parse in `recovery_init`.** Add `#include "cJSON.h"` and `#include <stdio.h>`. Add above `recovery_init`:
```c
void recovery_save(void) {
    bool en; uint16_t win;
    recovery_get_config(&en, &win);
    char buf[64];
    snprintf(buf, sizeof(buf), "{\"enabled\":%s,\"window_ms\":%u}", en ? "true" : "false", win);
    nvs_handle_t h;
    if (nvs_open("car", NVS_READWRITE, &h) == ESP_OK) {
        esp_err_t e = nvs_set_str(h, "recover", buf);
        if (e == ESP_OK) e = nvs_commit(h);
        if (e != ESP_OK) ESP_LOGW(TAG, "recover save failed: %s", esp_err_to_name(e));
        nvs_close(h);
    }
}
```
In `recovery_init`, replace the NVS read block:
```c
    nvs_handle_t h;
    if (nvs_open("car", NVS_READONLY, &h) == ESP_OK) {
        int8_t en;
        if (nvs_get_i8(h, "recover_en", &en) == ESP_OK) s_enabled = (en != 0);
        uint16_t win;
        if (nvs_get_u16(h, "recover_win", &win) == ESP_OK &&
            win >= RECOVER_WIN_MIN_MS && win <= RECOVER_WIN_MAX_MS) s_window_ms = win;
        nvs_close(h);
    }
```
with:
```c
    nvs_handle_t h;
    if (nvs_open("car", NVS_READONLY, &h) == ESP_OK) {
        char buf[64];
        size_t len = sizeof(buf);
        if (nvs_get_str(h, "recover", buf, &len) == ESP_OK) {
            cJSON *j = cJSON_Parse(buf);
            cJSON *je = cJSON_GetObjectItemCaseSensitive(j, "enabled");
            cJSON *jw = cJSON_GetObjectItemCaseSensitive(j, "window_ms");
            if (cJSON_IsBool(je)) s_enabled = cJSON_IsTrue(je);
            if (cJSON_IsNumber(jw) && jw->valueint >= RECOVER_WIN_MIN_MS && jw->valueint <= RECOVER_WIN_MAX_MS)
                s_window_ms = (uint16_t)jw->valueint;
            cJSON_Delete(j);
        }
        nvs_close(h);
    }
```

- [ ] **Step 6: `main/recovery_api.c` — call `recovery_save()`.** Replace the inline NVS block:
```c
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
```
with:
```c
    recovery_set_config(en == 1, (uint16_t)win);
    recovery_save();
    return httpd_resp_sendstr(req, "ok");
```

- [ ] **Step 7: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add main/ramp.c main/ramp.h main/ramp_api.c main/recovery.c main/recovery.h main/recovery_api.c
git commit -m "feat(fw): ramp + recovery persist as JSON strings in NVS"
```

---

### Task 3: `trim` storage → JSON string (in `car.c`)

**Files:**
- Modify: `main/car.h`, `main/car.c`, `main/trim_api.c`

- [ ] **Step 1: Declare `car_save_trim` in `main/car.h`** — add after `int8_t car_get_trim(void);`:
```c
// Persist the current trim as a JSON string in NVS (the trim value lives in car.c).
void car_save_trim(void);
```

- [ ] **Step 2: `main/car.c` — add `car_save_trim` + JSON parse in `car_init`.** Add `#include "cJSON.h"` and `#include <stdio.h>` at the top (alongside `#include "nvs.h"`). Add this function (e.g. right after `car_get_trim`):
```c
// JSON string in NVS under "trim": {"trim_pct":..}
void car_save_trim(void) {
    char buf[32];
    snprintf(buf, sizeof(buf), "{\"trim_pct\":%d}", car_get_trim());
    nvs_handle_t h;
    if (nvs_open("car", NVS_READWRITE, &h) == ESP_OK) {
        esp_err_t e = nvs_set_str(h, "trim", buf);
        if (e == ESP_OK) e = nvs_commit(h);
        if (e != ESP_OK) ESP_LOGW(TAG, "trim save failed: %s", esp_err_to_name(e));
        nvs_close(h);
    }
}
```
In `car_init`, replace the trim NVS read block:
```c
    nvs_handle_t h;
    if (nvs_open("car", NVS_READONLY, &h) == ESP_OK) {
        int8_t t;
        if (nvs_get_i8(h, "trim_pct", &t) == ESP_OK && t >= -30 && t <= 30) g_trim_pct = t;
        nvs_close(h);
    }
```
with:
```c
    nvs_handle_t h;
    if (nvs_open("car", NVS_READONLY, &h) == ESP_OK) {
        char buf[32];
        size_t len = sizeof(buf);
        if (nvs_get_str(h, "trim", buf, &len) == ESP_OK) {
            cJSON *j = cJSON_Parse(buf);
            cJSON *jt = cJSON_GetObjectItemCaseSensitive(j, "trim_pct");
            if (cJSON_IsNumber(jt) && jt->valueint >= -30 && jt->valueint <= 30)
                g_trim_pct = (int8_t)jt->valueint;
            cJSON_Delete(j);
        }
        nvs_close(h);
    }
```
(Note: `g_trim_pct` is set here directly during init, before the mutex matters, exactly as the old code did.)

- [ ] **Step 3: `main/trim_api.c` — call `car_save_trim()`.** Replace the inline NVS block:
```c
    car_set_trim((int8_t)v);
    nvs_handle_t h;
    if (nvs_open("car", NVS_READWRITE, &h) == ESP_OK) {
        esp_err_t e = nvs_set_i8(h, "trim_pct", (int8_t)v);
        if (e == ESP_OK) e = nvs_commit(h);
        if (e != ESP_OK) ESP_LOGW(TAG, "trim save failed: %s", esp_err_to_name(e));
        nvs_close(h);
    }
    return httpd_resp_sendstr(req, "ok");
```
with:
```c
    car_set_trim((int8_t)v);
    car_save_trim();
    return httpd_resp_sendstr(req, "ok");
```

- [ ] **Step 4: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add main/car.h main/car.c main/trim_api.c
git commit -m "feat(fw): trim persists as a JSON string in NVS"
```

---

### Task 4: `calibration` blob → JSON string

**Files:**
- Modify: `main/calibration.c`

- [ ] **Step 1: Rewrite `main/calibration.c`** so the table persists as a JSON string `{"deadzone":..,"wheels":[{"pair":..,"sign":..}×4]}` instead of a raw blob. Add `#include "cJSON.h"` and `#include <stdio.h>`. Replace `calibration_load` + `calibration_save`:
```c
bool calibration_load(motors_config_t *out) {
    nvs_handle_t h;
    if (nvs_open(NS, NVS_READONLY, &h) != ESP_OK) return false;
    char buf[160];
    size_t len = sizeof(buf);
    esp_err_t e = nvs_get_str(h, KEY, buf, &len);
    nvs_close(h);
    if (e != ESP_OK) return false;
    cJSON *j = cJSON_Parse(buf);
    cJSON *jdz = cJSON_GetObjectItemCaseSensitive(j, "deadzone");
    cJSON *arr = cJSON_GetObjectItemCaseSensitive(j, "wheels");
    if (!cJSON_IsNumber(jdz) || !cJSON_IsArray(arr) || cJSON_GetArraySize(arr) != 4) {
        cJSON_Delete(j);
        return false;
    }
    motors_config_t tmp = { .deadzone = (float)jdz->valuedouble };
    for (int i = 0; i < 4; i++) {
        cJSON *w = cJSON_GetArrayItem(arr, i);
        cJSON *jp = cJSON_GetObjectItemCaseSensitive(w, "pair");
        cJSON *js = cJSON_GetObjectItemCaseSensitive(w, "sign");
        if (!cJSON_IsNumber(jp) || !cJSON_IsNumber(js)) { cJSON_Delete(j); return false; }
        tmp.wheels[i].channel_pair = (uint8_t)jp->valueint;
        tmp.wheels[i].sign = (int8_t)js->valueint;
    }
    cJSON_Delete(j);
    if (!calibration_valid(&tmp)) return false;
    *out = tmp;
    ESP_LOGI(TAG, "loaded calibration from NVS");
    return true;
}

esp_err_t calibration_save(const motors_config_t *cfg) {
    if (!calibration_valid(cfg)) return ESP_ERR_INVALID_ARG;
    char buf[160];
    int n = snprintf(buf, sizeof(buf), "{\"deadzone\":%.3f,\"wheels\":[", (double)cfg->deadzone);
    for (int i = 0; i < 4; i++) {
        n += snprintf(buf + n, sizeof(buf) - n, "%s{\"pair\":%u,\"sign\":%d}",
                      i ? "," : "", cfg->wheels[i].channel_pair, cfg->wheels[i].sign);
    }
    snprintf(buf + n, sizeof(buf) - n, "]}");
    nvs_handle_t h;
    esp_err_t e = nvs_open(NS, NVS_READWRITE, &h);
    if (e != ESP_OK) return e;
    e = nvs_set_str(h, KEY, buf);
    if (e == ESP_OK) e = nvs_commit(h);
    nvs_close(h);
    if (e == ESP_OK) ESP_LOGI(TAG, "saved calibration to NVS");
    return e;
}
```
(The `#include <string.h>` at the top is now likely unused — leave it; harmless.)

- [ ] **Step 2: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add main/calibration.c
git commit -m "feat(fw): calibration persists as a JSON string (was an NVS blob)"
```

---

### Task 5: Build + verification

- [ ] **Step 1: Firmware build gate (the real compile check for all storage modules)**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
export PATH=/tmp/py313bin:$PATH
source ~/esp/esp-idf/export.sh >/dev/null 2>&1
idf.py build 2>&1 | tail -6
```
Expected: `Project build complete.` / `Built target app`. Fix any compile error minimally (re-read the offending module), rebuild, report the fix.

- [ ] **Step 2: Host tests still green (the pure `calibration_valid` is unchanged)**

Run: `cd /Users/adamjohnson/VSCode/esp32-p4-car/test && make run 2>&1 | tail -12`
Expected: `test_calibration: all passed` plus all suites (these don't link the storage `.c` files, so they're unaffected — this just confirms no header regression).

- [ ] **Step 3: Mock round-trip sanity (the app↔mock JSON contract is unchanged from Phase 1)**

The mock already stores JSON in memory (Phase 1). Confirm a config POST→GET still round-trips:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
curl -s http://127.0.0.1:8080/status >/dev/null 2>&1 || (cd tools/mock_car && nohup .venv/bin/python -u mock_car.py >/tmp/mock_car.log 2>&1 & sleep 2)
curl -s -X POST -d '{"track_mm":120,"wheelbase_mm":190}' http://127.0.0.1:8080/dims; echo
curl -s http://127.0.0.1:8080/dims; echo
```
Expected: `ok`, `{"track_mm": 120, "wheelbase_mm": 190}`. (This phase is firmware-storage-only; the on-car NVS-JSON round-trip is verified when the board is flashed — out of band.)

- [ ] **Step 4: No commit** (verification only).

**On-device note:** after flashing this firmware, the first boot logs each module's default (`wheel d=65…`, `dims track=130…`, `recovery off/on, window…`) because the old typed NVS keys are not read — this is the accepted reset-to-defaults; the calibration wizard re-runs (`calibrated=false`). Setting any value then re-booting must show the new value loaded from the JSON string (verifies `*_save`→`*_init` round-trip on hardware).

---

## Self-Review

**Spec coverage (storage half):**
- One JSON string per domain in NVS, serialized `snprintf` + parsed cJSON at boot → Tasks 1–4. ✅
- Module owns `*_save()`; api POST drops inline `nvs_set_*` and calls it → Tasks 1–4 (calib_api already calls `calibration_save`). ✅
- `*_init`/`*_load` parses JSON, reuses `*_set`/`calibration_valid` for clamp/validate, falls back to defaults if absent/malformed → Tasks 1–4. ✅
- Calibration blob → JSON string (with deadzone + wheels array) → Task 4. ✅
- Trim (lives in car.c) loads JSON + `car_save_trim()` → Task 3. ✅
- Accepted reset-to-defaults on upgrade (new keys ≠ old keys, no migration) → noted; emergent, nothing to implement. ✅
- cJSON only on the cold boot/save path; pure `calibration_valid` unchanged + host-tested → Tasks 1–4 + Task 5. ✅
- No wire/iOS/mock change (Phase 1 did transport) → out of scope here. ✅

**Placeholder scan:** none — full code per step. The "leave the now-unused `#include`/`#define KEY`" notes are deliberate minimal-diff choices, not placeholders. ✅

**Type/name consistency:** `wheel_save`/`dims_save`/`ramp_save`/`recovery_save`/`car_save_trim` declared in their headers (Tasks 1/2/3) and called from the matching api POST (Tasks 1/2/3); NVS string keys `wheel`/`dims`/`ramp`/`recover`/`trim`/`calib` used consistently in each module's save+load; `calibration_load`/`calibration_save` keep their signatures (Task 4) so `car_init`/`calib_api` callers are unchanged; cJSON API usage matches Phase 1; `wheel_set`/`dims_set` (clamp) + `calibration_valid` reused for validation; `ramp_get_ms`/`recovery_get_config`/`car_get_trim` used to read current values for serialization. ✅
