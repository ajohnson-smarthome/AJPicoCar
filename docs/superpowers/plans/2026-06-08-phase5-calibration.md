# Фаза 5: Калибровка моторов (NVS) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Дать пользователю при первом подключении откалибровать машину — назначить каждому из 4 моторов угол (FL/FR/RL/RR) и направление, наблюдая за колёсами, — и сохранить таблицу в NVS, чтобы маппинг перестал быть угаданным.

**Architecture:** Калибровка хранится как `motors_config_t` в NVS. `car.c` при старте грузит её (`calibration_load`); если нет/невалидна — **остаётся прежний дефолт** (езда не ломается). Чистая `calibration_valid()` (4 уникальных канала + знаки ±1) хост-тестируется. Для опознания моторов `car.c` умеет крутить ОДНУ сырую пару каналов (`car_spin_pair`, в обход таблицы). Интерактивная часть — REST-эндпоинты `/calib*` + экран калибровки в `index.html`, гейтящий пульт, пока не откалибровано.

**Tech Stack:** ESP-IDF 5.4, NVS (`nvs_flash`), `esp_http_server` REST, clang+make хост-тест.

**Статус исполнения:** Task 1–2 (фундамент: модуль + интеграция в car) реализуются автономно (сборка + хост-тесты, безопасный fallback). Task 3–5 (REST + UI + гейтинг + сам акт калибровки) исполняются **с пользователем** (нужно смотреть на колёса).

---

## File Structure

| Файл | Ответственность | Проверка |
|---|---|---|
| `main/calibration.h/.c` | NVS load/save + чистая `calibration_valid` | хост-тест + сборка |
| `main/car.{c,h}` | load-or-default; `car_set_calibration`; `car_spin_pair` (сырая пара) | сборка |
| `main/calib_api.{c,h}` *(Task 3)* | REST `/calib`, `/calib/spin`, `/calib/save` | сборка + e2e |
| `main/web/index.html` *(Task 4)* | экран калибровки + гейтинг | браузер + e2e |
| `test/test_calibration.c` | хост-тест `calibration_valid` | — |

---

## Task 1: Модуль `calibration` (NVS + чистая валидация) — АВТОНОМНО

**Files:**
- Create: `main/calibration.h`, `main/calibration.c`, `test/test_calibration.c`
- Modify: `test/Makefile`, `.gitignore`

- [ ] **Step 1: Создать `main/calibration.h`**
```c
#ifndef CALIBRATION_H
#define CALIBRATION_H

#include <stdbool.h>
#include "esp_err.h"
#include "motors.h"

// Validate a calibration table: the 4 wheels must map to channel_pairs
// {0,1,2,3} each exactly once, every sign must be +1 or -1, and deadzone must
// be in [0,1). Pure (no I/O).
bool calibration_valid(const motors_config_t *cfg);

// Load the saved calibration from NVS into *out. Returns true only if a VALID
// table was found; otherwise returns false and leaves *out untouched (caller
// keeps its default).
bool calibration_load(motors_config_t *out);

// Validate and persist a calibration table to NVS. Returns ESP_ERR_INVALID_ARG
// if invalid, otherwise the NVS commit result.
esp_err_t calibration_save(const motors_config_t *cfg);

#endif // CALIBRATION_H
```

- [ ] **Step 2: Создать `test/test_calibration.c` (хост-тест чистой части)**
```c
#include "calibration.h"
#include <assert.h>
#include <stdio.h>

static motors_config_t good(void) {
    motors_config_t c = {
        .wheels = {
            [POS_FL] = { .channel_pair = 0, .sign = 1 },
            [POS_FR] = { .channel_pair = 1, .sign = -1 },
            [POS_RL] = { .channel_pair = 2, .sign = 1 },
            [POS_RR] = { .channel_pair = 3, .sign = -1 },
        },
        .deadzone = 0.05f,
    };
    return c;
}

int main(void) {
    motors_config_t c = good();
    assert(calibration_valid(&c));

    c = good(); c.wheels[POS_FR].channel_pair = 0;   // duplicate pair 0
    assert(!calibration_valid(&c));

    c = good(); c.wheels[POS_RR].channel_pair = 4;    // out of range
    assert(!calibration_valid(&c));

    c = good(); c.wheels[POS_FL].sign = 0;            // bad sign
    assert(!calibration_valid(&c));

    c = good(); c.deadzone = -0.1f;                   // bad deadzone
    assert(!calibration_valid(&c));

    c = good(); c.deadzone = 1.0f;                    // deadzone must be < 1
    assert(!calibration_valid(&c));

    printf("test_calibration: all passed\n");
    return 0;
}
```

- [ ] **Step 3: Add `test_calibration` target to `test/Makefile`** (compiles from `test_calibration.c` + `../main/calibration.c`)... NOTE: `calibration.c` includes NVS headers (ESP-only), so it can't host-compile. Instead, put `calibration_valid` in its OWN pure translation unit OR make it a `static inline` in the header. **Decision: make `calibration_valid` a `static inline` in `calibration.h`** so the test compiles from `test_calibration.c` ALONE (no `.c`). Update Step 1's header accordingly: move the body inline:
```c
static inline bool calibration_valid(const motors_config_t *cfg) {
    if (cfg->deadzone < 0.0f || cfg->deadzone >= 1.0f) return false;
    unsigned seen = 0;
    for (int p = 0; p < POS_COUNT; p++) {
        uint8_t pair = cfg->wheels[p].channel_pair;
        int8_t sign = cfg->wheels[p].sign;
        if (pair > 3) return false;
        if (sign != 1 && sign != -1) return false;
        if (seen & (1u << pair)) return false;  // duplicate
        seen |= (1u << pair);
    }
    return seen == 0x0F;  // pairs 0..3 all present
}
```
(`calibration.h` then needs `#include <stdint.h>` and `motors.h` only for the inline; the NVS functions are declared but defined in `calibration.c`.)
Add to Makefile `all`/`run`/`clean` a `test_calibration` built from `test_calibration.c` alone.

- [ ] **Step 4: Red step** — `make test_calibration` fails before header exists (or passes if header already written; note it).

- [ ] **Step 5: Create `main/calibration.c`** (NVS load/save; uses the inline validator):
```c
#include "calibration.h"
#include <string.h>
#include "nvs.h"
#include "esp_log.h"

static const char *TAG = "calib";
#define NS  "car"
#define KEY "calib"

bool calibration_load(motors_config_t *out) {
    nvs_handle_t h;
    if (nvs_open(NS, NVS_READONLY, &h) != ESP_OK) return false;
    motors_config_t tmp;
    size_t len = sizeof(tmp);
    esp_err_t e = nvs_get_blob(h, KEY, &tmp, &len);
    nvs_close(h);
    if (e != ESP_OK || len != sizeof(tmp) || !calibration_valid(&tmp)) return false;
    *out = tmp;
    ESP_LOGI(TAG, "loaded calibration from NVS");
    return true;
}

esp_err_t calibration_save(const motors_config_t *cfg) {
    if (!calibration_valid(cfg)) return ESP_ERR_INVALID_ARG;
    nvs_handle_t h;
    esp_err_t e = nvs_open(NS, NVS_READWRITE, &h);
    if (e != ESP_OK) return e;
    e = nvs_set_blob(h, KEY, cfg, sizeof(*cfg));
    if (e == ESP_OK) e = nvs_commit(h);
    nvs_close(h);
    if (e == ESP_OK) ESP_LOGI(TAG, "saved calibration to NVS");
    return e;
}
```

- [ ] **Step 6: `make clean && make run`** — all host tests pass (incl. `test_calibration`).
- [ ] **Step 7:** Append `test/test_calibration` to `.gitignore`.
- [ ] **Step 8: Commit** `feat: add calibration module (NVS persistence + host-tested validator)`.

(NOTE: `calibration.c` is NOT added to CMake here; Task 2 adds it with the car integration so it builds in firmware together.)

---

## Task 2: Интеграция в `car.c` (load-or-default, set, spin-pair) — АВТОНОМНО

**Files:**
- Modify: `main/car.h`, `main/car.c`, `main/CMakeLists.txt`

- [ ] **Step 1: Extend `main/car.h`** — add after `car_stop`:
```c
// Replace the active calibration table (e.g. after the user saves one).
void car_set_calibration(const motors_config_t *cfg);

// Calibration helper: spin ONE raw PCA9685 channel pair (0..3) at low duty to
// identify which wheel it is. Bypasses the calibration table. forward=true uses
// CH_A, false uses CH_B. Call car_stop() to halt.
void car_spin_pair(uint8_t pair, bool forward);
```
Add `#include "motors.h"` and `#include <stdbool.h>`/`<stdint.h>` to car.h as needed for the types.

- [ ] **Step 2: Modify `main/car.c`:**
  (a) make `g_cfg` non-const (drop nothing else); add `#include "calibration.h"`.
  (b) `car_init`: after creating the mutex, before the safety stop, add:
```c
    motors_config_t loaded;
    if (calibration_load(&loaded)) {
        g_cfg = loaded;
    } else {
        ESP_LOGW(TAG, "no NVS calibration — using default mapping");
    }
```
  (c) add:
```c
void car_set_calibration(const motors_config_t *cfg) {
    if (g_lock) xSemaphoreTake(g_lock, pdMS_TO_TICKS(200));
    g_cfg = *cfg;
    if (g_lock) xSemaphoreGive(g_lock);
}

void car_spin_pair(uint8_t pair, bool forward) {
    if (pair > 3) return;
    motor_outputs_t out = { .duty = {0} };
    const uint16_t duty = 1600;  // ~40% for identification
    out.duty[pair * 2]     = forward ? duty : 0;
    out.duty[pair * 2 + 1] = forward ? 0 : duty;
    if (g_lock && xSemaphoreTake(g_lock, pdMS_TO_TICKS(200)) != pdTRUE) return;
    motors_apply(&out);
    if (g_lock) xSemaphoreGive(g_lock);
}
```
  (Note: `car_init` must run AFTER `nvs_flash_init()`. Currently `app_main` does `car_init()` BEFORE NVS init — **Task 2 Step 3 reorders app_main so NVS init precedes car_init**.)

- [ ] **Step 3: Reorder `main/main.c` app_main** so `nvs_flash_init()` (the erase/retry block) runs BEFORE `car_init()`. New order: `pca9685_bus_init → pca9685_init → NVS init → car_init → wifi → http → ws → watchdog → console`.

- [ ] **Step 4: Add `calibration.c` to `main/CMakeLists.txt` SRCS.**

- [ ] **Step 5: Build** → `Project build complete`.
- [ ] **Step 6: Commit** `feat: load calibration from NVS in car_init (default fallback); add set/spin helpers`.

---

## Task 3: REST-эндпоинты `/calib*` — С ПОЛЬЗОВАТЕЛЕМ

`main/calib_api.{c,h}` registering on `http_server_get_handle()`:
- `GET /calib` → `{"calibrated": <bool>}` (calibration_load probe).
- `POST /calib/spin` body `pair=N&dir=fwd|rev` → `car_spin_pair(N, fwd)`, auto-stop after ~600 ms (one-shot timer → `car_stop`).
- `POST /calib/save` body = 4 assignments (e.g. `FL=0:1,FR=1:-1,RL=2:1,RR=3:-1,dz=0.05`) → build `motors_config_t`, `calibration_save`, on success `car_set_calibration` + reply OK; on invalid → 400.
Call `calib_api_start()` in app_main after `ws_control_start()`. (Full code to be written at execution.)

## Task 4: Экран калибровки + гейтинг в `index.html` — С ПОЛЬЗОВАТЕЛЕМ

On load: `fetch('/calib')`. If `calibrated=false` → show ONLY the calibration screen:
step through pairs 0..3; for each, button "Spin" (`POST /calib/spin`), radios for corner (FL/FR/RL/RR, each pickable once) + direction; "Next"; after 4 → "Save" (`POST /calib/save`). On success → reveal the d-pad. Add a "⚙ Recalibrate" button on the pad. (Full HTML/JS at execution.)

## Task 5: Сквозная калибровка на железе — С ПОЛЬЗОВАТЕЛЕМ

Flash; first connect → calibration screen; spin each motor, tag corner+direction watching the wheels; save; confirm the d-pad then drives the correct wheels the correct way; power-cycle → calibration persists (no re-prompt).

---

## Self-Review заметки

- **Безопасный fallback:** если NVS пуст/битый, `car_init` оставляет дефолтный `g_cfg` — текущая езда не ломается. Это делает Task 1–2 безопасными для автономного мёржа.
- **Тип-консистентность:** `calibration_valid/load/save(motors_config_t*)`; `car_set_calibration`/`car_spin_pair` в car.h; NVS namespace `car`/key `calib`.
- **Порядок init:** NVS перед `car_init` (Task 2 Step 3) — обязателен, иначе `calibration_load` упадёт.
- **Чистая валидация** хост-тестируется (дубль канала, вне диапазона, плохой знак, deadzone).
