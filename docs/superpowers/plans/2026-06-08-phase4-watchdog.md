# Фаза 4: Watchdog-автостоп (+ перенесённые фиксы) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Добавить watchdog, который автоматически останавливает машину (`car_stop`), если по WebSocket не приходит ни одного кадра дольше N мс (или связь оборвалась) — закрывает пробел безопасности при потере радиосвязи.

**Architecture:** Веб-пульт уже шлёт `t,y` потоком ~10 Гц. `ws_handler` «кормит» watchdog на каждом валидном кадре. Периодический FreeRTOS-таймер (~50 Гц, выполняется в задаче `Tmr Svc`) проверяет, не устарел ли последний корм; если устарел и watchdog «взведён» — зовёт `car_stop()` (мьютекс безопасен, т.к. другая задача). Решающая функция «устарело?» вынесена как чистая `static inline` в заголовок и хост-тестируется (с обработкой переполнения 32-битного тика). Watchdog кормится ТОЛЬКО из WS (консоль — отладочный проводной путь, не под watchdog, чтобы одиночные `mix` не глохли). Заодно вносим перенесённые из ревью Фазы 3 фиксы: ограниченный таймаут мьютекса и понижение лога.

**Tech Stack:** ESP-IDF 5.4, FreeRTOS software timer (`xTimerCreate`), `xTaskGetTickCount`, clang+make хост-тест для чистой функции.

**Вне объёма (отложено):** Ramp (slew-rate limit). Причина: требует настройки на железе (которого нет в автономном прогоне) и отдельного ramp-таска ~50 Гц, иначе одиночные консольные команды не доходят до полной скорости. Дизайн-набросок — в конце файла.

---

## File Structure

| Файл | Ответственность | Проверка |
|---|---|---|
| `main/car.h` / `main/car.c` | фикс: ограниченный таймаут мьютекса; `car_drive` LOGI→LOGD | сборка |
| `main/watchdog.h` | API + **чистая `static inline watchdog_stale()`** | хост-тест |
| `main/watchdog.c` | таймер 50 Гц, корм, автостоп через `car_stop` | сборка |
| `main/ws_control.c` | вызов `watchdog_feed()` на валидном кадре | сборка |
| `main/main.c` | `watchdog_init(300)` после `ws_control_start` | сборка |
| `main/CMakeLists.txt` | + `watchdog.c` | — |
| `test/Makefile`, `test/test_watchdog.c` | хост-тест `watchdog_stale` (вкл. rollover) | — |

---

## Task 1: Перенесённые фиксы в `car.c` (ограниченный таймаут мьютекса, LOGD)

**Files:**
- Modify: `main/car.c`

- [ ] **Step 1: Заменить тело `car_drive` в `main/car.c`**

Find:
```c
void car_drive(float throttle, float yaw) {
    throttle = clamp_unit(throttle);
    yaw = clamp_unit(yaw);
    side_speeds_t s = mixer_mix(throttle, yaw);
    motor_outputs_t out = motors_plan(s.left, s.right, &g_cfg);

    if (g_lock) xSemaphoreTake(g_lock, portMAX_DELAY);
    motors_apply(&out);
    if (g_lock) xSemaphoreGive(g_lock);

    // TODO(phase4): downgrade to ESP_LOGD — at 30 Hz WS driving this floods the log.
    ESP_LOGI(TAG, "drive t=%.2f y=%.2f -> L=%.2f R=%.2f", throttle, yaw, s.left, s.right);
}
```
Replace with:
```c
void car_drive(float throttle, float yaw) {
    throttle = clamp_unit(throttle);
    yaw = clamp_unit(yaw);
    side_speeds_t s = mixer_mix(throttle, yaw);
    motor_outputs_t out = motors_plan(s.left, s.right, &g_cfg);

    // Bounded timeout so a stuck holder can't wedge the watchdog task forever.
    if (g_lock && xSemaphoreTake(g_lock, pdMS_TO_TICKS(200)) != pdTRUE) {
        ESP_LOGW(TAG, "drive: mutex busy >200ms, skipping write");
        return;
    }
    motors_apply(&out);
    if (g_lock) xSemaphoreGive(g_lock);

    ESP_LOGD(TAG, "drive t=%.2f y=%.2f -> L=%.2f R=%.2f", throttle, yaw, s.left, s.right);
}
```

- [ ] **Step 2: Build**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && export PATH=/tmp/py313bin:$PATH && source ~/esp/esp-idf/export.sh && idf.py build 2>&1 | tail -5
```
Expected: `Project build complete`, no errors/warnings.

- [ ] **Step 3: Commit**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add main/car.c
git commit -m "harden: bound car_drive mutex wait to 200ms; drive log to LOGD"
```

---

## Task 2: Модуль `watchdog` + хост-тест чистой функции

**Files:**
- Create: `main/watchdog.h`
- Create: `main/watchdog.c`
- Create: `test/test_watchdog.c`
- Modify: `test/Makefile`
- Modify: `.gitignore`

- [ ] **Step 1: Создать `main/watchdog.h` (API + чистая inline)**

Create `main/watchdog.h`:

```c
#ifndef WATCHDOG_H
#define WATCHDOG_H

#include <stdint.h>
#include <stdbool.h>

// Start the control-link watchdog: a periodic check that stops the car if no
// watchdog_feed() has happened within timeout_ms. Call once after the WS server.
void watchdog_init(uint32_t timeout_ms);

// Record a fresh control frame (call from the WS handler on each valid frame).
// Also "arms" the watchdog so it only acts once traffic has started.
void watchdog_feed(void);

// Pure: has more than timeout_ms elapsed between last_ms and now_ms?
// Uses unsigned subtraction so 32-bit millisecond-counter rollover is handled.
static inline bool watchdog_stale(uint32_t last_ms, uint32_t now_ms, uint32_t timeout_ms) {
    return (uint32_t)(now_ms - last_ms) > timeout_ms;
}

#endif // WATCHDOG_H
```

- [ ] **Step 2: Написать падающий тест `test/test_watchdog.c`**

Create `test/test_watchdog.c`:

```c
#include "watchdog.h"
#include <assert.h>
#include <stdio.h>

static void check(uint32_t last, uint32_t now, uint32_t to, bool want) {
    bool got = watchdog_stale(last, now, to);
    if (got != want) {
        printf("FAIL stale(%u,%u,%u) = %d, want %d\n", last, now, to, got, want);
        assert(0);
    }
}

int main(void) {
    check(100, 300, 300, false);   // 200ms elapsed, not yet stale
    check(100, 400, 300, false);   // exactly 300ms — strict '>' so not stale
    check(100, 401, 300, true);    // 301ms — stale
    check(0, 0, 300, false);       // no time passed
    check(0, 5000, 300, true);     // long gap
    // 32-bit rollover: last near max, now wrapped past zero
    check(0xFFFFFF00u, 0x00000050u, 300, true);   // (0x50 - 0xFFFFFF00) = 0x150 = 336 > 300
    check(0xFFFFFF00u, 0xFFFFFF00u + 100u, 300, false); // 100ms across wrap, not stale
    printf("test_watchdog: all passed\n");
    return 0;
}
```

- [ ] **Step 3: Добавить цель в `test/Makefile` (до реализации)**

Replace `test/Makefile` ENTIRELY with (recipe lines MUST use literal TABs):

```makefile
CC = cc
CFLAGS = -I../main -Wall -Wextra -Werror -std=c11
LDLIBS = -lm

all: test_mixer test_motors test_control_proto test_watchdog

test_mixer: test_mixer.c ../main/mixer.c
	$(CC) $(CFLAGS) -o $@ $^ $(LDLIBS)

test_motors: test_motors.c ../main/motors.c
	$(CC) $(CFLAGS) -o $@ $^ $(LDLIBS)

test_control_proto: test_control_proto.c ../main/control_proto.c
	$(CC) $(CFLAGS) -o $@ $^ $(LDLIBS)

test_watchdog: test_watchdog.c
	$(CC) $(CFLAGS) -o $@ $^ $(LDLIBS)

run: all
	./test_mixer && ./test_motors && ./test_control_proto && ./test_watchdog

clean:
	rm -f test_mixer test_motors test_control_proto test_watchdog
```
(Note: `test_watchdog` compiles from `test_watchdog.c` ALONE — `watchdog_stale` is a `static inline` in the header, so no `.c` is needed for the test.)

- [ ] **Step 4: Запустить тест — убедиться, что падает (нет watchdog.h)**

Run: `cd /Users/adamjohnson/VSCode/esp32-p4-car/test && make test_watchdog`
Expected: ошибка — `watchdog.h` ещё не создан (fatal error: 'watchdog.h' file not found). Это «красный» шаг TDD. (Если ты делаешь Step 1 до Step 4, тест вместо этого пройдёт — тогда просто отметь, что собралось и прошло.)

- [ ] **Step 5: Создать `main/watchdog.c`**

Create `main/watchdog.c`:

```c
#include "watchdog.h"
#include "freertos/FreeRTOS.h"
#include "freertos/timers.h"
#include "esp_log.h"
#include "car.h"

static const char *TAG = "wdt";

#define WDT_PERIOD_MS 20  // 50 Hz check

static volatile uint32_t s_last_feed_ms = 0;
static volatile bool     s_armed = false;
static uint32_t          s_timeout_ms = 300;
static TimerHandle_t     s_timer = NULL;

static uint32_t now_ms(void) {
    return (uint32_t)(xTaskGetTickCount() * portTICK_PERIOD_MS);
}

void watchdog_feed(void) {
    s_last_feed_ms = now_ms();
    s_armed = true;
}

static void wdt_cb(TimerHandle_t t) {
    (void)t;
    if (!s_armed) return;
    if (watchdog_stale(s_last_feed_ms, now_ms(), s_timeout_ms)) {
        ESP_LOGW(TAG, "no control frame for >%ums — stopping car", (unsigned)s_timeout_ms);
        car_stop();
        s_armed = false;  // disarm until traffic resumes
    }
}

void watchdog_init(uint32_t timeout_ms) {
    s_timeout_ms = timeout_ms;
    s_timer = xTimerCreate("wdt", pdMS_TO_TICKS(WDT_PERIOD_MS), pdTRUE, NULL, wdt_cb);
    if (s_timer == NULL || xTimerStart(s_timer, 0) != pdPASS) {
        ESP_LOGE(TAG, "failed to start watchdog timer");
        return;
    }
    ESP_LOGI(TAG, "watchdog armed, timeout %ums", (unsigned)timeout_ms);
}
```

- [ ] **Step 6: Запустить все хост-тесты — PASS**

Run: `cd /Users/adamjohnson/VSCode/esp32-p4-car/test && make clean && make run`
Expected: `test_mixer`, `test_motors`, `test_control_proto`, `test_watchdog` — все `all passed`.

- [ ] **Step 7: Добавить бинарник теста в `.gitignore`**

Append `test/test_watchdog` to `.gitignore` (keep existing lines).

- [ ] **Step 8: Commit**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add main/watchdog.h main/watchdog.c test/test_watchdog.c test/Makefile .gitignore
git commit -m "feat: add control-link watchdog with host-tested staleness check"
```

---

## Task 3: Подключить watchdog (корм из WS + init в main + CMake)

**Files:**
- Modify: `main/ws_control.c`
- Modify: `main/main.c`
- Modify: `main/CMakeLists.txt`

- [ ] **Step 1: Кормить watchdog в `main/ws_control.c`**

Add include after `#include "car.h"`:
```c
#include "watchdog.h"
```
Find:
```c
    float t, y;
    if (control_parse_ty((const char *)buf, &t, &y) == 0) {
        // TODO(phase4): stamp a "last frame received" timestamp here for the watchdog.
        car_drive(t, y);
    } else {
```
Replace with:
```c
    float t, y;
    if (control_parse_ty((const char *)buf, &t, &y) == 0) {
        watchdog_feed();
        car_drive(t, y);
    } else {
```

- [ ] **Step 2: Инициализировать watchdog в `main/main.c`**

Add include after `#include "ws_control.h"`:
```c
#include "watchdog.h"
```
Add a define after `#define AP_PASSWORD ...`:
```c
#define WDT_TIMEOUT_MS 300
```
In `app_main`, immediately AFTER `ESP_ERROR_CHECK(ws_control_start());`, insert:
```c
    watchdog_init(WDT_TIMEOUT_MS);
```

- [ ] **Step 3: Добавить `watchdog.c` в `main/CMakeLists.txt`**

Replace `main/CMakeLists.txt` ENTIRELY with:
```cmake
idf_component_register(
    SRCS "main.c" "pca9685.c" "mixer.c" "motors.c" "car.c" "wifi_ap.c" "http_server.c" "control_proto.c" "ws_control.c" "watchdog.c"
    INCLUDE_DIRS "."
    REQUIRES esp_wifi esp_netif esp_event nvs_flash esp_http_server
    PRIV_REQUIRES esp_driver_usb_serial_jtag esp_driver_i2c
    EMBED_TXTFILES "web/index.html"
)
```

- [ ] **Step 4: Build**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && export PATH=/tmp/py313bin:$PATH && source ~/esp/esp-idf/export.sh && idf.py build 2>&1 | tail -6
```
Expected: `Project build complete`, no errors.

- [ ] **Step 5: Commit**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add main/ws_control.c main/main.c main/CMakeLists.txt
git commit -m "feat: feed watchdog from WS frames and start it in app_main"
```

---

## Task 4: Аппаратная проверка (ОТЛОЖЕНА — нужен пользователь)

Выполнить, когда пользователь за пультом и машинка на подставке:
- [ ] Прошить, подключиться телефоном, поехать (удержание ▲).
- [ ] **Отпустить палец / закрыть вкладку / уйти из зоны WiFi во время езды** → машина должна остановиться сама в пределах ~300 мс. В логе: `wdt: no control frame for >300ms — stopping car`.
- [ ] Консольный `mix 0.6 0` (через мост) НЕ должен автоматически глохнуть (консоль не под watchdog) — подтверждает, что отладочный путь не задет.

---

## Self-Review заметки

- **Покрытие фазы:** watchdog-автостоп (Task 2/3), перенесённые фиксы — ограниченный таймаут мьютекса + LOGD (Task 1). Ramp осознанно отложен (см. ниже). Аппаратная проверка — Task 4 (отложена).
- **Тип-консистентность:** `watchdog_init(uint32_t)`, `watchdog_feed(void)`, inline `watchdog_stale(last,now,timeout)` едины в .h/.c/тесте/вызовах; `car_stop()` — точка автостопа.
- **Конкуренция:** `wdt_cb` выполняется в `Tmr Svc`, `car_stop`→`car_drive` берёт мьютекс — другая задача, без рекурсии/дедлока. Таймаут мьютекса теперь ограничен 200 мс.
- **Консоль не под watchdog:** кормит только `ws_handler`, поэтому одиночные `mix` для отладки не глохнут.

## Отложено: дизайн Ramp (для будущей фазы, нужна настройка на железе)

Цель — гасить рывки и пусковой ток (грабли #6, брауны-аут 5-10× номинала). Правильный дизайн, не зависящий от частоты команд:
- В `car.c`: `s_target[8]` (цель) и `s_current[8]` (применённое). `car_drive`/`car_stop` пишут `s_target` под мьютексом.
- Отдельный ramp-таск ~50 Гц: шагает `s_current` к `s_target` (рост ограничен `RAMP_MAX_UP`, падение мгновенно — для безопасного стопа) и пишет PCA9685. Тогда единственный писатель в I2C — ramp-таск, мьютекс защищает только `s_target`.
- Чистая `ramp_step(current, target, max_up)` — хост-тест.
- Константу `RAMP_MAX_UP` подобрать на стенде (старт ~1365/тик ≈ 0.27с до полного газа при 50 Гц).
Почему не сейчас: одношаговый ramp в `car_drive` ломает одиночные консольные команды (доходят лишь на один шаг), а ramp-таск + настройку нельзя проверить без железа.
