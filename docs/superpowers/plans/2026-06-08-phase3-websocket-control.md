# Фаза 3: WebSocket-управление `t,y` → `car_drive` — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Добавить WebSocket-эндпоинт `/ws` на существующий HTTP-сервер, принимать текстовые кадры `t,y` (~30 Гц) и применять их через `car_drive`, чтобы рулить машинкой с телефона в реальном времени.

**Architecture:** Сначала делаем `car_drive` потокобезопасным (мьютекс вокруг I2C-записи) — пререквизит, т.к. теперь его зовут два таска (консольный REPL и httpd). Парсинг протокола выносим в чистый хост-тестируемый модуль `control_proto`. WS-эндпоинт живёт в отдельном модуле `ws_control`, который регистрирует `/ws` на хэндле из `http_server_get_handle()`, парсит кадр через `control_proto` и зовёт `car_drive`. Минимальный тест-пульт в `index.html` (кнопки удержания) позволяет проверить сквозняк с телефона; полноценные джойстики — Фаза 6.

**Tech Stack:** ESP-IDF 5.4 (esp32c6), `esp_http_server` WebSocket API (`httpd_ws_recv_frame`, `.is_websocket`), FreeRTOS mutex, clang+make хост-тесты, браузерный WebSocket клиент в HTML.

---

## File Structure

| Файл | Ответственность | Проверка |
|---|---|---|
| `main/car.h` / `main/car.c` | + мьютекс вокруг I2C-записи, + `car_stop()` | сборка + мост |
| `main/control_proto.h` / `main/control_proto.c` | **чистый** парсер `"t,y" → throttle,yaw` | хост-тесты |
| `main/ws_control.h` / `main/ws_control.c` | WS-эндпоинт `/ws`: recv → parse → `car_drive` | сборка + браузер |
| `main/web/index.html` | + минимальный WS тест-пульт (кнопки удержания) | браузер |
| `main/main.c` | + вызов `ws_control_start()` после http | сборка |
| `main/CMakeLists.txt` | + `control_proto.c`, `ws_control.c` | — |
| `sdkconfig.defaults` | + `CONFIG_HTTPD_WS_SUPPORT=y` | — |
| `test/Makefile`, `test/test_control_proto.c` | хост-тесты парсера | — |

**Изоляция:** `control_proto.c` без ESP-зависимостей (только `<stdio.h>`) — хост-тестируется. `ws_control` склеивает http_server (хэндл) + control_proto (парсинг) + car (привод). `car.c` остаётся оркестрацией, добавляет лишь синхронизацию.

---

## Task 1: Потокобезопасный `car_drive` + `car_stop`

**Files:**
- Modify: `main/car.h`
- Modify: `main/car.c`

- [ ] **Step 1: Обновить `main/car.h`**

Replace `main/car.h` ENTIRELY with:

```c
#ifndef CAR_H
#define CAR_H

// Initialize the mutex + default calibration table and issue a safety stop.
// Call once after pca9685 is initialized, before any car_drive() call.
void car_init(void);

// Apply a driving intent. throttle and yaw are each clamped to [-1, 1], then
// mixed into side speeds, planned to per-channel PWM, and written to the PCA9685.
// Thread-safe: the I2C write is serialized by an internal mutex, so the console
// task and the WebSocket task may both call it. Last write wins.
void car_drive(float throttle, float yaw);

// Convenience safety stop (equivalent to car_drive(0, 0)).
void car_stop(void);

#endif // CAR_H
```

- [ ] **Step 2: Обновить `main/car.c` (мьютекс + car_stop)**

Replace `main/car.c` ENTIRELY with:

```c
#include "car.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "esp_log.h"
#include "esp_err.h"
#include "pca9685.h"
#include "mixer.h"
#include "motors.h"

static const char *TAG = "car";

// Default calibration (Phase 2). Replaced by an NVS-stored table in Phase 5.
static motors_config_t g_cfg = {
    .wheels = {
        [POS_FL] = { .channel_pair = 0, .sign = 1 },
        [POS_FR] = { .channel_pair = 1, .sign = 1 },
        [POS_RL] = { .channel_pair = 2, .sign = 1 },
        [POS_RR] = { .channel_pair = 3, .sign = 1 },
    },
    .deadzone = 0.05f,
};

// Serializes the 8-channel I2C write so concurrent callers (console + WebSocket
// tasks) can't interleave transactions on the shared PCA9685 handle.
static SemaphoreHandle_t g_lock;

static float clamp_unit(float v) {
    if (v > 1.0f) return 1.0f;
    if (v < -1.0f) return -1.0f;
    return v;
}

// Write planned PWM to the 8 PCA9685 channels.
static void motors_apply(const motor_outputs_t *out) {
    for (uint8_t ch = 0; ch < 8; ch++) {
        esp_err_t e = pca9685_set_pwm(ch, out->duty[ch]);
        if (e != ESP_OK) {
            ESP_LOGE(TAG, "ch%d write failed: %s", ch, esp_err_to_name(e));
        }
    }
}

void car_drive(float throttle, float yaw) {
    throttle = clamp_unit(throttle);
    yaw = clamp_unit(yaw);
    side_speeds_t s = mixer_mix(throttle, yaw);
    motor_outputs_t out = motors_plan(s.left, s.right, &g_cfg);

    if (g_lock) xSemaphoreTake(g_lock, portMAX_DELAY);
    motors_apply(&out);
    if (g_lock) xSemaphoreGive(g_lock);

    ESP_LOGI(TAG, "drive t=%.2f y=%.2f -> L=%.2f R=%.2f", throttle, yaw, s.left, s.right);
}

void car_stop(void) {
    car_drive(0.0f, 0.0f);
}

void car_init(void) {
    g_lock = xSemaphoreCreateMutex();
    if (g_lock == NULL) {
        ESP_LOGE(TAG, "failed to create drive mutex");
    }
    car_stop();  // safety stop
}
```

- [ ] **Step 3: Собрать**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && export PATH=/tmp/py313bin:$PATH && source ~/esp/esp-idf/export.sh && idf.py build 2>&1 | tail -5
```
Expected: `Project build complete`, no errors/warnings.

- [ ] **Step 4: Коммит**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add main/car.h main/car.c
git commit -m "feat: make car_drive thread-safe with a mutex; add car_stop"
```

---

## Task 2: Чистый парсер протокола `control_proto`

**Files:**
- Create: `main/control_proto.h`
- Create: `main/control_proto.c`
- Create: `test/test_control_proto.c`
- Modify: `test/Makefile`
- Modify: `.gitignore`

- [ ] **Step 1: Создать `main/control_proto.h`**

Create `main/control_proto.h`:

```c
#ifndef CONTROL_PROTO_H
#define CONTROL_PROTO_H

// Parse a "t,y" control message — two floats separated by a comma — into
// throttle and yaw. Whitespace around the numbers/comma is tolerated.
// Returns 0 on success, -1 on malformed input. Does NOT range-check the values
// (car_drive clamps them). On failure, *throttle/*yaw are left unchanged.
int control_parse_ty(const char *msg, float *throttle, float *yaw);

#endif // CONTROL_PROTO_H
```

- [ ] **Step 2: Написать падающий тест `test/test_control_proto.c`**

Create `test/test_control_proto.c`:

```c
#include "control_proto.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

static int approx(float a, float b) { return fabsf(a - b) < 1e-4f; }

static void ok(const char *msg, float et, float ey) {
    float t = 999.0f, y = 999.0f;
    int r = control_parse_ty(msg, &t, &y);
    if (r != 0 || !approx(t, et) || !approx(y, ey)) {
        printf("FAIL ok('%s') -> r=%d t=%.4f y=%.4f (want t=%.4f y=%.4f)\n",
               msg, r, t, y, et, ey);
        assert(0);
    }
}

static void bad(const char *msg) {
    float t = 7.0f, y = 7.0f;
    int r = control_parse_ty(msg, &t, &y);
    if (r != -1 || t != 7.0f || y != 7.0f) {  // unchanged on failure
        printf("FAIL bad('%s') -> r=%d t=%.4f y=%.4f (want r=-1, unchanged)\n",
               msg ? msg : "(null)", r, t, y);
        assert(0);
    }
}

int main(void) {
    ok("0.5,0", 0.5f, 0.0f);
    ok("0,1", 0.0f, 1.0f);
    ok("-1,-0.5", -1.0f, -0.5f);
    ok("1.0,-1.0", 1.0f, -1.0f);
    ok(" 0.25 , 0.75 ", 0.25f, 0.75f);   // whitespace tolerated

    bad("abc");
    bad("0.5");        // missing comma + second value
    bad("0.5,");       // missing second value
    bad(",0.5");       // missing first value
    bad("");
    bad(NULL);

    printf("test_control_proto: all passed\n");
    return 0;
}
```

- [ ] **Step 3: Добавить цель в `test/Makefile` (до реализации — чтобы тест был компилируем)**

Replace `test/Makefile` ENTIRELY with:

```makefile
CC = cc
CFLAGS = -I../main -Wall -Wextra -Werror -std=c11
LDLIBS = -lm

all: test_mixer test_motors test_control_proto

test_mixer: test_mixer.c ../main/mixer.c
	$(CC) $(CFLAGS) -o $@ $^ $(LDLIBS)

test_motors: test_motors.c ../main/motors.c
	$(CC) $(CFLAGS) -o $@ $^ $(LDLIBS)

test_control_proto: test_control_proto.c ../main/control_proto.c
	$(CC) $(CFLAGS) -o $@ $^ $(LDLIBS)

run: all
	./test_mixer && ./test_motors && ./test_control_proto

clean:
	rm -f test_mixer test_motors test_control_proto
```
(Recipe lines MUST use literal TABs.)

- [ ] **Step 4: Запустить тест — убедиться, что падает (нет control_proto.c)**

Run: `cd /Users/adamjohnson/VSCode/esp32-p4-car/test && make test_control_proto`
Expected: ошибка сборки — `../main/control_proto.c` не существует (no rule / missing file). Это и есть «красный» шаг TDD.

- [ ] **Step 5: Реализовать `main/control_proto.c`**

Create `main/control_proto.c`:

```c
#include "control_proto.h"
#include <stdio.h>

int control_parse_ty(const char *msg, float *throttle, float *yaw) {
    if (msg == NULL) return -1;
    float t, y;
    // "%f , %f" — leading spaces in the format skip whitespace; the comma must
    // match literally. sscanf returns the count of successfully parsed fields.
    if (sscanf(msg, " %f , %f", &t, &y) != 2) return -1;
    *throttle = t;
    *yaw = y;
    return 0;
}
```

- [ ] **Step 6: Запустить все хост-тесты — убедиться, что проходят**

Run: `cd /Users/adamjohnson/VSCode/esp32-p4-car/test && make clean && make run`
Expected: `test_mixer: all passed`, `test_motors: all passed`, `test_control_proto: all passed`.

- [ ] **Step 7: Добавить новый бинарник теста в `.gitignore`**

Append the line `test/test_control_proto` to `.gitignore` (keep existing entries). After editing, `.gitignore` must contain a line exactly: `test/test_control_proto`.

- [ ] **Step 8: Коммит**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add main/control_proto.h main/control_proto.c test/test_control_proto.c test/Makefile .gitignore
git commit -m "feat: add pure control_proto t,y parser with host tests"
```

---

## Task 3: WebSocket-эндпоинт `ws_control`

**Files:**
- Create: `main/ws_control.h`
- Create: `main/ws_control.c`
- Modify: `main/main.c`
- Modify: `main/CMakeLists.txt`
- Modify: `sdkconfig.defaults`

- [ ] **Step 1: Гарантировать поддержку WS в `sdkconfig.defaults`**

Append this line to `sdkconfig.defaults` (keep existing lines):
```
CONFIG_HTTPD_WS_SUPPORT=y
```

- [ ] **Step 2: Создать `main/ws_control.h`**

Create `main/ws_control.h`:

```c
#ifndef WS_CONTROL_H
#define WS_CONTROL_H

#include "esp_err.h"

// Register the "/ws" WebSocket endpoint on the already-running HTTP server
// (obtained via http_server_get_handle()). Incoming "t,y" text frames are
// parsed and applied via car_drive(). Call after http_server_start().
esp_err_t ws_control_start(void);

#endif // WS_CONTROL_H
```

- [ ] **Step 3: Создать `main/ws_control.c`**

Create `main/ws_control.c`:

```c
#include "ws_control.h"
#include "esp_http_server.h"
#include "esp_log.h"
#include "esp_check.h"
#include "http_server.h"
#include "control_proto.h"
#include "car.h"

static const char *TAG = "ws";

static esp_err_t ws_handler(httpd_req_t *req) {
    if (req->method == HTTP_GET) {
        // WebSocket handshake completed; nothing to send back.
        ESP_LOGI(TAG, "ws client connected");
        return ESP_OK;
    }

    // First call with max_len = 0 fills frame.len so we know the payload size.
    httpd_ws_frame_t frame = { .type = HTTPD_WS_TYPE_TEXT };
    esp_err_t ret = httpd_ws_recv_frame(req, &frame, 0);
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "recv len failed: %s", esp_err_to_name(ret));
        return ret;
    }
    if (frame.len == 0 || frame.len > 31) {
        return ESP_OK;  // ignore empty / oversized frames
    }

    uint8_t buf[32];
    frame.payload = buf;
    ret = httpd_ws_recv_frame(req, &frame, sizeof(buf) - 1);
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "recv payload failed: %s", esp_err_to_name(ret));
        return ret;
    }
    buf[frame.len] = '\0';

    float t, y;
    if (control_parse_ty((const char *)buf, &t, &y) == 0) {
        car_drive(t, y);
    } else {
        ESP_LOGW(TAG, "bad ws msg: '%s'", (const char *)buf);
    }
    return ESP_OK;
}

esp_err_t ws_control_start(void) {
    httpd_handle_t server = http_server_get_handle();
    if (server == NULL) {
        ESP_LOGE(TAG, "http server not started");
        return ESP_FAIL;
    }
    httpd_uri_t ws = {
        .uri = "/ws",
        .method = HTTP_GET,
        .handler = ws_handler,
        .is_websocket = true,
    };
    ESP_RETURN_ON_ERROR(httpd_register_uri_handler(server, &ws), TAG, "register /ws");
    ESP_LOGI(TAG, "WebSocket endpoint registered at /ws");
    return ESP_OK;
}
```

- [ ] **Step 4: Подключить в `main/main.c`**

In `main/main.c`, add this include right after the existing `#include "http_server.h"` line:
```c
#include "ws_control.h"
```
In `app_main`, immediately AFTER the `ESP_ERROR_CHECK(http_server_start());` line, insert:
```c
    ESP_ERROR_CHECK(ws_control_start());
```

- [ ] **Step 5: Обновить `main/CMakeLists.txt`**

Replace `main/CMakeLists.txt` ENTIRELY with:

```cmake
idf_component_register(
    SRCS "main.c" "pca9685.c" "mixer.c" "motors.c" "car.c" "wifi_ap.c" "http_server.c" "control_proto.c" "ws_control.c"
    INCLUDE_DIRS "."
    REQUIRES esp_wifi esp_netif esp_event nvs_flash esp_http_server
    PRIV_REQUIRES esp_driver_usb_serial_jtag esp_driver_i2c
    EMBED_TXTFILES "web/index.html"
)
```

- [ ] **Step 6: Собрать**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && export PATH=/tmp/py313bin:$PATH && source ~/esp/esp-idf/export.sh && idf.py build 2>&1 | tail -8
```
Expected: `Project build complete`, no errors. If `httpd_ws_frame_t`/`httpd_ws_recv_frame`/`.is_websocket` are undefined, WS support is off — confirm `CONFIG_HTTPD_WS_SUPPORT=y` made it into the generated sdkconfig (a clean reconfigure may be needed: `idf.py reconfigure`). If it still fails, report BLOCKED with the error.

- [ ] **Step 7: Коммит**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add main/ws_control.h main/ws_control.c main/main.c main/CMakeLists.txt sdkconfig.defaults
git commit -m "feat: add /ws WebSocket endpoint applying t,y via car_drive"
```

---

## Task 4: Минимальный WS тест-пульт в `index.html`

**Files:**
- Modify: `main/web/index.html`

- [ ] **Step 1: Заменить `main/web/index.html` тест-пультом**

Replace `main/web/index.html` ENTIRELY with:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
  <title>ESP32-Car</title>
  <style>
    body { font-family:-apple-system,system-ui,sans-serif; background:#111; color:#eee;
           display:flex; flex-direction:column; align-items:center; gap:14px;
           height:100vh; margin:0; justify-content:center; touch-action:none; }
    #status { font-size:0.95rem; }
    .dot { width:12px; height:12px; border-radius:50%; display:inline-block; margin-right:6px;
           background:#c33; vertical-align:middle; }
    .dot.on { background:#3c3; }
    .pad { display:grid; grid-template-columns:repeat(3,84px); grid-template-rows:repeat(3,84px);
           gap:8px; }
    button { font-size:1.6rem; border:none; border-radius:14px; background:#333; color:#eee; }
    button:active { background:#3a6; }
    .fwd{grid-area:1/2;} .left{grid-area:2/1;} .stop{grid-area:2/2;background:#622;}
    .right{grid-area:2/3;} .back{grid-area:3/2;}
    .note { font-size:0.75rem; color:#888; max-width:260px; text-align:center; }
  </style>
</head>
<body>
  <div id="status"><span class="dot" id="dot"></span><span id="txt">connecting…</span></div>
  <div class="pad">
    <button class="fwd"   data-ty="0.6,0">&#9650;</button>
    <button class="left"  data-ty="0,-0.6">&#9664;</button>
    <button class="stop"  data-ty="0,0">&#9632;</button>
    <button class="right" data-ty="0,0.6">&#9654;</button>
    <button class="back"  data-ty="-0.6,0">&#9660;</button>
  </div>
  <div class="note">Temporary test pad — hold to drive, release to stop. Joystick UI comes later.</div>
  <script>
    var dot = document.getElementById('dot');
    var txt = document.getElementById('txt');
    var ws;
    function connect() {
      ws = new WebSocket('ws://' + location.host + '/ws');
      ws.onopen  = function(){ dot.classList.add('on'); txt.textContent = 'connected'; };
      ws.onclose = function(){ dot.classList.remove('on'); txt.textContent = 'disconnected — retrying'; setTimeout(connect, 1000); };
      ws.onerror = function(){ ws.close(); };
    }
    function send(ty) { if (ws && ws.readyState === 1) ws.send(ty); }
    var btns = document.querySelectorAll('button[data-ty]');
    for (var i = 0; i < btns.length; i++) {
      (function(b){
        var ty = b.getAttribute('data-ty');
        b.addEventListener('pointerdown',  function(e){ e.preventDefault(); send(ty); });
        b.addEventListener('pointerup',     function(e){ e.preventDefault(); send('0,0'); });
        b.addEventListener('pointercancel', function(){ send('0,0'); });
        b.addEventListener('pointerleave',  function(){ send('0,0'); });
      })(btns[i]);
    }
    connect();
  </script>
</body>
</html>
```

- [ ] **Step 2: Собрать (страница вшита — пересборка переэмбедит её)**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && export PATH=/tmp/py313bin:$PATH && source ~/esp/esp-idf/export.sh && idf.py build 2>&1 | tail -5
```
Expected: `Project build complete`, no errors.

- [ ] **Step 3: Коммит**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add main/web/index.html
git commit -m "feat: minimal WebSocket test pad in served page"
```

---

## Task 5: Сквозная проверка на железе (с участием пользователя)

**Files:** (без изменений кода — только проверка; выполняется контроллером с пользователем)

- [ ] **Step 1: Прошить финальную сборку**

Сверить порт (`ls /dev/cu.usbmodem*`), остановить мост если висит (`pkill -f esp_bridge.py`), затем:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && export PATH=/tmp/py313bin:$PATH && source ~/esp/esp-idf/export.sh && idf.py -p /dev/cu.usbmodem* flash 2>&1 | tail -4
```
Expected: `Hash of data verified.` и reset. (Колёса на подставке.)

- [ ] **Step 2: Регресс консоли (мост) — поведение `mix` не сломалось мьютексом**

Поднять мост, прогнать:
```bash
: > /tmp/esp_out.log; echo "mix 0.5 0" > /tmp/esp_in; sleep 1.5; tail -c 200 /tmp/esp_out.log | tr -d '\r'
echo "mix 0 0" > /tmp/esp_in
```
Expected: `drive t=0.50 y=0.00 -> L=0.50 R=0.50`.

- [ ] **Step 3: Сквозной WS-тест с телефона**

На айфоне: подключиться к WiFi `ESP32-Car` (пароль `drive1234`), открыть `http://192.168.4.1/`.
Expected:
- индикатор статуса становится зелёным с надписью **connected** (WS-соединение установлено);
- удержание стрелок крутит моторы (на подставке), отпускание — стоп;
- кнопка ■ — стоп.
В логе ESP (через мост `/tmp/esp_out.log`) на каждое нажатие появляется `ws client connected` (один раз при коннекте) и `drive t=.. y=.. -> L=.. R=..` на каждую команду.

- [ ] **Step 4: Проверить две схемы одновременно (последний-выигрывает)**

Пока телефон подключён, параллельно через мост отправить `mix 0 0`. Убедиться, что консоль и WS не конфликтуют (нет зависаний/перезагрузок) — мьютекс сериализует доступ к I2C.
Expected: обе стороны работают, моторы реагируют на последнюю команду, плата не перезагружается.

- [ ] **Step 5: Финальная проверка чистоты дерева**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && git status --short
```
Expected: чисто (всё закоммичено в Task 1–4).

---

## Self-Review заметки

- **Покрытие фазы:** мьютекс+`car_stop` (Task 1, пререквизит ревью Фазы 2), чистый парсер `t,y` (Task 2, TDD), WS-эндпоинт `/ws` → `car_drive` (Task 3), тест-пульт для e2e (Task 4), сквозная проверка (Task 5). Watchdog/ramp — Фаза 4; полноценные джойстики/обе схемы/PWA — Фаза 6; калибровка/NVS — Фаза 5.
- **Тип-консистентность:** `control_parse_ty(msg, *throttle, *yaw)` (control_proto.h) используется в ws_control.c; `ws_control_start()` зовётся в main.c после `http_server_start()`; `http_server_get_handle()` (из Фазы 2) даёт хэндл; `car_drive`/`car_stop` (car.h) — точки применения.
- **Конкуренция:** `car_drive` теперь под мьютексом → httpd-таск (WS) и консольный таск безопасно делят I2C. Семантика last-write-wins задокументирована в `car.h`.
- **Хост-тесты:** только `control_proto` (чистый). `ws_control`/`car` сетевые/аппаратные — сборка + e2e.
- **Зависимость от конфигурации:** WS требует `CONFIG_HTTPD_WS_SUPPORT=y` (Task 3 Step 1); при отказе сборки — `idf.py reconfigure`.

## Что дальше (Фаза 4)

Watchdog-автостоп: таск/таймер ~50 Гц; если с момента последнего WS-кадра прошло >300 мс (или WS закрылся) → `car_stop()`. Плюс ramp (slew-rate limit) в слое перед `motors_apply`, чтобы гасить рывки и брауны-ауты. WS-обработчик будет обновлять метку времени «последний кадр».
