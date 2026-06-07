# Фаза 2: WiFi softAP + HTTP-сервер — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Поднять на ESP32-C6 точку доступа `ESP32-Car` и встроенный HTTP-сервер, отдающий статическую страницу с `192.168.4.1`, не ломая существующее консольное управление `mix <t> <y>`.

**Architecture:** Оркестрацию привода выносим из `main.c` в модуль `car.{c,h}` (`car_drive` с клэмпом входов) — это общий seam для будущего WebSocket-обработчика. Сеть поднимаем двумя сфокусированными модулями: `wifi_ap.{c,h}` (softAP) и `http_server.{c,h}` (esp_http_server + один GET-хендлер, отдающий вшитый `web/index.html`). `app_main` инициализирует NVS → PCA9685 → car → WiFi AP → HTTP-сервер → консольный REPL.

**Tech Stack:** ESP-IDF 5.4 (esp32c6), `esp_wifi` (softAP), `esp_http_server`, `nvs_flash`, `esp_netif`/`esp_event`, CMake `EMBED_TXTFILES` для вшивания HTML. Хост-тесты (clang+make) для существующих чистых модулей не меняются.

---

## File Structure

| Файл | Ответственность | Проверка |
|---|---|---|
| `main/car.h` / `main/car.c` | Оркестрация привода: `car_init`, `car_drive(t,y)` с клэмпом; владеет `g_cfg`, `motors_apply` | сборка + мост |
| `main/wifi_ap.h` / `main/wifi_ap.c` | softAP bring-up: `wifi_ap_start(ssid, pass)` | сборка + логи + телефон видит SSID |
| `main/http_server.h` / `main/http_server.c` | `http_server_start()`: esp_http_server + GET `/` → вшитый HTML | браузер `192.168.4.1` |
| `main/web/index.html` | Минимальная статическая страница (полноценный пульт — Фаза 6) | браузер |
| `main/main.c` | Связка: NVS → PCA9685 → car → wifi → http → REPL | сборка + e2e |
| `main/CMakeLists.txt` | Новые исходники + REQUIRES + EMBED_TXTFILES | — |

**Изоляция:** `car.c` зависит от железа (pca9685) — не хост-тестируется, проверяется через мост. `wifi_ap`/`http_server` — сетевые, проверяются на устройстве. Чистые модули `mixer`/`motors` не трогаем.

---

## Task 1: Вынести оркестрацию привода в `car.{c,h}`

**Files:**
- Create: `main/car.h`
- Create: `main/car.c`
- Modify: `main/main.c`
- Modify: `main/CMakeLists.txt`

- [ ] **Step 1: Создать `main/car.h`**

Create `main/car.h`:

```c
#ifndef CAR_H
#define CAR_H

// Initialize the default calibration table and issue a safety stop.
// Call once after pca9685 is initialized.
void car_init(void);

// Apply a driving intent. throttle and yaw are each clamped to [-1, 1],
// then mixed into side speeds, planned to per-channel PWM, and written to the
// PCA9685. Safe to call from any task once car_init() has run.
void car_drive(float throttle, float yaw);

#endif // CAR_H
```

- [ ] **Step 2: Создать `main/car.c` (перенос `g_cfg`, `motors_apply`, `drive` из main.c)**

Create `main/car.c`:

```c
#include "car.h"
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
    motors_apply(&out);
    ESP_LOGI(TAG, "drive t=%.2f y=%.2f -> L=%.2f R=%.2f", throttle, yaw, s.left, s.right);
}

void car_init(void) {
    car_drive(0.0f, 0.0f);  // safety stop
}
```

- [ ] **Step 3: Упростить `main/main.c` — использовать `car.h`**

Replace `main/main.c` entirely with:

```c
#include <stdio.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/usb_serial_jtag.h"
#include "esp_log.h"
#include "esp_check.h"

#include "pca9685.h"
#include "car.h"

static const char *TAG = "main";

#define I2C_SDA_PIN  22
#define I2C_SCL_PIN  23
#define I2C_FREQ_HZ  400000
#define PWM_FREQ_HZ  1000

static void console_init(void) {
    usb_serial_jtag_driver_config_t cfg = USB_SERIAL_JTAG_DRIVER_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(usb_serial_jtag_driver_install(&cfg));
}

static int read_line(char *buf, size_t maxlen) {
    size_t pos = 0;
    while (pos < maxlen - 1) {
        uint8_t c;
        int n = usb_serial_jtag_read_bytes(&c, 1, portMAX_DELAY);
        if (n <= 0) continue;
        if (c == '\r' || c == '\n') {
            buf[pos] = '\0';
            return (int)pos;
        }
        buf[pos++] = (char)c;
    }
    buf[pos] = '\0';
    return -1;
}

// Parse "mix <t> <y>", t,y in [-1,1]. Returns 0 on success.
static int parse_mix(const char *line, float *t, float *y) {
    char cmd[8];
    if (sscanf(line, "%7s %f %f", cmd, t, y) != 3) return -1;
    if (strcmp(cmd, "mix") != 0) return -1;
    if (*t < -1.0f || *t > 1.0f || *y < -1.0f || *y > 1.0f) return -1;
    return 0;
}

void app_main(void) {
    ESP_ERROR_CHECK(pca9685_bus_init(I2C_SDA_PIN, I2C_SCL_PIN, I2C_FREQ_HZ));
    ESP_ERROR_CHECK(pca9685_init(PWM_FREQ_HZ));
    car_init();

    console_init();
    ESP_LOGI(TAG, "Ready. Enter 'mix <throttle> <yaw>' (each -1..1), e.g. 'mix 0.5 0.2':");

    char line[48];
    while (1) {
        printf("> ");
        fflush(stdout);
        int len = read_line(line, sizeof(line));
        if (len <= 0) {
            if (len < 0) ESP_LOGE(TAG, "input overflow");
            continue;
        }
        float t, y;
        if (parse_mix(line, &t, &y) == 0) {
            car_drive(t, y);
        } else {
            ESP_LOGE(TAG, "bad command, expected 'mix <t> <y>' with t,y in [-1,1]");
        }
    }
}
```

- [ ] **Step 4: Добавить `car.c` в `main/CMakeLists.txt`**

Replace `main/CMakeLists.txt` with:

```cmake
idf_component_register(
    SRCS "main.c" "pca9685.c" "mixer.c" "motors.c" "car.c"
    INCLUDE_DIRS "."
)
```

- [ ] **Step 5: Собрать**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && export PATH=/tmp/py313bin:$PATH && source ~/esp/esp-idf/export.sh && idf.py build 2>&1 | tail -5
```
Expected: `Project build complete`, без ошибок и варнингов.

- [ ] **Step 6: Прошить и проверить через мост (поведение `mix` не изменилось)**

Run (порт сверить через `ls /dev/cu.usbmodem*`; если мост висит — `pkill -f esp_bridge.py` перед прошивкой):
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && export PATH=/tmp/py313bin:$PATH && source ~/esp/esp-idf/export.sh && idf.py -p /dev/cu.usbmodem* flash 2>&1 | tail -4
```
Then restart bridge and test:
```bash
~/.espressif/python_env/idf5.4_py3.13_env/bin/python /tmp/esp_bridge.py /dev/cu.usbmodem* > /tmp/esp_bridge.log 2>&1 &
sleep 2
: > /tmp/esp_out.log; echo "mix 0.5 0" > /tmp/esp_in; sleep 1.5; tail -c 200 /tmp/esp_out.log | tr -d '\r'
```
Expected: `drive t=0.50 y=0.00 -> L=0.50 R=0.50`. (Колёса на подставке — закрутятся; затем `echo "mix 0 0" > /tmp/esp_in` для стопа.)

- [ ] **Step 7: Коммит**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add main/car.h main/car.c main/main.c main/CMakeLists.txt
git commit -m "refactor: extract car module (car_drive with input clamp) from main"
```

---

## Task 2: WiFi softAP `ESP32-Car`

**Files:**
- Create: `main/wifi_ap.h`
- Create: `main/wifi_ap.c`
- Modify: `main/main.c` (NVS init + start AP)
- Modify: `main/CMakeLists.txt` (sources + REQUIRES)

- [ ] **Step 1: Создать `main/wifi_ap.h`**

Create `main/wifi_ap.h`:

```c
#ifndef WIFI_AP_H
#define WIFI_AP_H

#include "esp_err.h"

// Bring up a WiFi softAP. If password is empty (""), the AP is open; otherwise
// WPA2-PSK (password must be >= 8 chars). Initializes netif + default event loop.
// NVS must already be initialized (esp_wifi stores calibration there).
esp_err_t wifi_ap_start(const char *ssid, const char *password);

#endif // WIFI_AP_H
```

- [ ] **Step 2: Создать `main/wifi_ap.c`**

Create `main/wifi_ap.c`:

```c
#include "wifi_ap.h"
#include <string.h>
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_netif.h"
#include "esp_log.h"
#include "esp_check.h"

static const char *TAG = "wifi_ap";

static void wifi_event_handler(void *arg, esp_event_base_t base,
                               int32_t id, void *data) {
    if (id == WIFI_EVENT_AP_STACONNECTED) {
        wifi_event_ap_staconnected_t *e = (wifi_event_ap_staconnected_t *)data;
        ESP_LOGI(TAG, "station " MACSTR " joined, AID=%d", MAC2STR(e->mac), e->aid);
    } else if (id == WIFI_EVENT_AP_STADISCONNECTED) {
        wifi_event_ap_stadisconnected_t *e = (wifi_event_ap_stadisconnected_t *)data;
        ESP_LOGI(TAG, "station " MACSTR " left, AID=%d", MAC2STR(e->mac), e->aid);
    }
}

esp_err_t wifi_ap_start(const char *ssid, const char *password) {
    ESP_RETURN_ON_ERROR(esp_netif_init(), TAG, "netif init");
    ESP_RETURN_ON_ERROR(esp_event_loop_create_default(), TAG, "event loop");
    esp_netif_create_default_wifi_ap();

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_RETURN_ON_ERROR(esp_wifi_init(&cfg), TAG, "wifi init");

    ESP_RETURN_ON_ERROR(esp_event_handler_instance_register(
        WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler, NULL, NULL),
        TAG, "event reg");

    wifi_config_t wc = {
        .ap = {
            .channel = 1,
            .max_connection = 4,
            .authmode = WIFI_AUTH_WPA2_PSK,
            .pmf_cfg = { .required = false },
        },
    };
    size_t slen = strlen(ssid);
    if (slen > sizeof(wc.ap.ssid)) slen = sizeof(wc.ap.ssid);
    memcpy(wc.ap.ssid, ssid, slen);
    wc.ap.ssid_len = slen;
    strlcpy((char *)wc.ap.password, password, sizeof(wc.ap.password));
    if (strlen(password) == 0) {
        wc.ap.authmode = WIFI_AUTH_OPEN;
    }

    ESP_RETURN_ON_ERROR(esp_wifi_set_mode(WIFI_MODE_AP), TAG, "set mode");
    ESP_RETURN_ON_ERROR(esp_wifi_set_config(WIFI_IF_AP, &wc), TAG, "set config");
    ESP_RETURN_ON_ERROR(esp_wifi_start(), TAG, "wifi start");

    ESP_LOGI(TAG, "softAP started: SSID='%s' %s, IP 192.168.4.1",
             ssid, strlen(password) ? "WPA2" : "OPEN");
    return ESP_OK;
}
```

- [ ] **Step 3: Подключить NVS + старт AP в `main/main.c`**

In `main/main.c`, add includes after `#include "car.h"`:
```c
#include "nvs_flash.h"
#include "wifi_ap.h"
```
Add these defines after `#define PWM_FREQ_HZ  1000`:
```c
#define AP_SSID      "ESP32-Car"
#define AP_PASSWORD  "drive1234"   // >= 8 chars for WPA2; "" for open
```
In `app_main`, immediately after `car_init();` and BEFORE `console_init();`, insert:
```c
    esp_err_t nvs = nvs_flash_init();
    if (nvs == ESP_ERR_NVS_NO_FREE_PAGES || nvs == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        nvs = nvs_flash_init();
    }
    ESP_ERROR_CHECK(nvs);
    ESP_ERROR_CHECK(wifi_ap_start(AP_SSID, AP_PASSWORD));
```

- [ ] **Step 4: Обновить `main/CMakeLists.txt` (sources + REQUIRES)**

Replace `main/CMakeLists.txt` with:

```cmake
idf_component_register(
    SRCS "main.c" "pca9685.c" "mixer.c" "motors.c" "car.c" "wifi_ap.c"
    INCLUDE_DIRS "."
    REQUIRES esp_wifi esp_netif esp_event nvs_flash
)
```

- [ ] **Step 5: Собрать**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && export PATH=/tmp/py313bin:$PATH && source ~/esp/esp-idf/export.sh && idf.py build 2>&1 | tail -6
```
Expected: `Project build complete`, без ошибок.

- [ ] **Step 6: Прошить и проверить старт AP по логам**

Бридж не показывает boot-лог надёжно — используем `idf.py monitor` коротко. Run (Ctrl-] чтобы выйти; или прочитать первые строки):
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && export PATH=/tmp/py313bin:$PATH && source ~/esp/esp-idf/export.sh && (pkill -f esp_bridge.py 2>/dev/null; idf.py -p /dev/cu.usbmodem* flash) 2>&1 | tail -4
```
Then capture early boot log via the bridge log file (restart bridge, it appends RX):
```bash
~/.espressif/python_env/idf5.4_py3.13_env/bin/python /tmp/esp_bridge.py /dev/cu.usbmodem* > /tmp/esp_bridge.log 2>&1 &
sleep 3
grep -i "softAP started" /tmp/esp_out.log || echo "(если пусто — нажми reset на плате и проверь снова)"
```
Expected: лог содержит `softAP started: SSID='ESP32-Car' WPA2, IP 192.168.4.1`.

- [ ] **Step 7: Проверить, что сеть видна с телефона/Mac**

Manual: на телефоне/Mac в списке WiFi должна появиться сеть **`ESP32-Car`**. Подключиться с паролем `drive1234`. Подключение должно пройти (получишь IP вида `192.168.4.x`). В логе появится `station .. joined`.
Expected: SSID виден, подключение успешно, лог показывает присоединение станции.

- [ ] **Step 8: Коммит**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add main/wifi_ap.h main/wifi_ap.c main/main.c main/CMakeLists.txt
git commit -m "feat: bring up WiFi softAP 'ESP32-Car' with NVS init"
```

---

## Task 3: HTTP-сервер отдаёт статическую страницу

**Files:**
- Create: `main/web/index.html`
- Create: `main/http_server.h`
- Create: `main/http_server.c`
- Modify: `main/main.c` (start server)
- Modify: `main/CMakeLists.txt` (source + REQUIRES + EMBED_TXTFILES)

- [ ] **Step 1: Создать минимальную страницу `main/web/index.html`**

Create `main/web/index.html`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
  <title>ESP32-Car</title>
  <style>
    body { font-family: -apple-system, system-ui, sans-serif; background:#111; color:#eee;
           display:flex; flex-direction:column; align-items:center; justify-content:center;
           height:100vh; margin:0; }
    h1 { font-size:2rem; }
    .dot { width:14px; height:14px; border-radius:50%; background:#3c3; display:inline-block;
           margin-right:8px; }
  </style>
</head>
<body>
  <h1><span class="dot"></span>ESP32-Car online</h1>
  <p>Static page served from the car. Joystick UI arrives in Phase 6.</p>
</body>
</html>
```

- [ ] **Step 2: Создать `main/http_server.h`**

Create `main/http_server.h`:

```c
#ifndef HTTP_SERVER_H
#define HTTP_SERVER_H

#include "esp_err.h"

// Start the embedded HTTP server. Serves the embedded index.html at GET "/".
esp_err_t http_server_start(void);

#endif // HTTP_SERVER_H
```

- [ ] **Step 3: Создать `main/http_server.c`**

Create `main/http_server.c`:

```c
#include "http_server.h"
#include "esp_http_server.h"
#include "esp_log.h"
#include "esp_check.h"

static const char *TAG = "http";

// Embedded via EMBED_TXTFILES "web/index.html" in CMakeLists.
extern const char index_html_start[] asm("_binary_index_html_start");
extern const char index_html_end[]   asm("_binary_index_html_end");

static esp_err_t root_get_handler(httpd_req_t *req) {
    const size_t len = index_html_end - index_html_start;
    httpd_resp_set_type(req, "text/html");
    return httpd_resp_send(req, index_html_start, len);
}

esp_err_t http_server_start(void) {
    httpd_config_t config = HTTPD_DEFAULT_CONFIG();
    config.lru_purge_enable = true;
    httpd_handle_t server = NULL;
    ESP_RETURN_ON_ERROR(httpd_start(&server, &config), TAG, "httpd start");

    httpd_uri_t root = {
        .uri = "/",
        .method = HTTP_GET,
        .handler = root_get_handler,
    };
    ESP_RETURN_ON_ERROR(httpd_register_uri_handler(server, &root), TAG, "register /");

    ESP_LOGI(TAG, "HTTP server started, serving / at 192.168.4.1");
    return ESP_OK;
}
```

- [ ] **Step 4: Запустить сервер в `main/main.c`**

In `main/main.c`, add include after `#include "wifi_ap.h"`:
```c
#include "http_server.h"
```
In `app_main`, immediately after `ESP_ERROR_CHECK(wifi_ap_start(AP_SSID, AP_PASSWORD));`, insert:
```c
    ESP_ERROR_CHECK(http_server_start());
```

- [ ] **Step 5: Обновить `main/CMakeLists.txt` (source + REQUIRES + embed)**

Replace `main/CMakeLists.txt` with:

```cmake
idf_component_register(
    SRCS "main.c" "pca9685.c" "mixer.c" "motors.c" "car.c" "wifi_ap.c" "http_server.c"
    INCLUDE_DIRS "."
    REQUIRES esp_wifi esp_netif esp_event nvs_flash esp_http_server
    EMBED_TXTFILES "web/index.html"
)
```

- [ ] **Step 6: Собрать**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && export PATH=/tmp/py313bin:$PATH && source ~/esp/esp-idf/export.sh && idf.py build 2>&1 | tail -6
```
Expected: `Project build complete`. (Если линкер ругается на `_binary_index_html_start` — проверь, что путь в EMBED_TXTFILES именно `web/index.html` относительно `main/`.)

- [ ] **Step 7: Прошить**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && export PATH=/tmp/py313bin:$PATH && source ~/esp/esp-idf/export.sh && (pkill -f esp_bridge.py 2>/dev/null; idf.py -p /dev/cu.usbmodem* flash) 2>&1 | tail -4
```
Expected: `Hash of data verified.` и reset.

- [ ] **Step 8: Проверить страницу из браузера**

Manual: подключи Mac/телефон к WiFi `ESP32-Car` (пароль `drive1234`), открой в браузере **http://192.168.4.1/**.
Expected: страница «● ESP32-Car online».

Либо с Mac после подключения к AP — через curl:
```bash
curl -s http://192.168.4.1/ | head -5
```
Expected: HTML, начинающийся с `<!DOCTYPE html>`.

- [ ] **Step 9: Коммит**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add main/web/index.html main/http_server.h main/http_server.c main/main.c main/CMakeLists.txt
git commit -m "feat: serve embedded static page over HTTP at 192.168.4.1"
```

---

## Task 4: Сквозная проверка и финал фазы

**Files:** (без изменений кода — только проверка)

- [ ] **Step 1: Проверить, что консольное управление и сеть сосуществуют**

С платой, прошитой финальной версией:
1. Подними мост, отправь `mix 0.5 0` → должно быть `drive t=0.50 y=0.00 -> L=0.50 R=0.50` (моторы на подставке крутятся), затем `mix 0 0`.
2. Параллельно с подключённым телефоном открой `http://192.168.4.1/` → страница грузится.
Expected: и консоль (`mix`), и HTTP-страница работают одновременно — REPL и HTTP-сервер не мешают друг другу.

- [ ] **Step 2: Проверить полный набор движений ещё раз (регресс Фазы 1)**

```bash
run() { : > /tmp/esp_out.log; echo "$1" > /tmp/esp_in; sleep 1.5; printf "%-12s -> " "$1"; tail -c 200 /tmp/esp_out.log | tr -d '\r' | grep -o 'drive.*'; }
run "mix 1 0"; run "mix -1 0"; run "mix 0 1"; run "mix 0 -1"; run "mix 0 0"
```
Expected: `L=1,R=1` / `L=-1,R=-1` / `L=1,R=-1` / `L=-1,R=1` / `L=0,R=0`.

- [ ] **Step 3: Финальный коммит-метка (если были некоммиченные правки проверки — иначе пропустить)**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && git status --short
```
Expected: чисто (всё уже закоммичено в Task 1–3).

---

## Self-Review заметки

- **Покрытие фазы:** softAP `ESP32-Car` (Task 2), HTTP-сервер + статическая страница (Task 3), извлечение `car.{c,h}` с клэмпом — рекомендация ревью Фазы 1 (Task 1), сквозная проверка сосуществования сети и консоли (Task 4). WebSocket, watchdog, калибровка, captive-portal, PWA — последующие фазы, вне объёма.
- **Тип-консистентность:** `car_init`/`car_drive` (car.h) вызываются в main.c; `wifi_ap_start(ssid,pass)` и `http_server_start()` сигнатуры совпадают с вызовами в app_main; символы `_binary_index_html_start/end` соответствуют `EMBED_TXTFILES "web/index.html"`.
- **Нет хост-тестов в этой фазе:** новая логика сетевая/аппаратная; проверяется сборкой, логами устройства и браузером. Чистые модули `mixer`/`motors` и их тесты не изменяются.
- **Безопасность привода:** `car_drive` теперь клэмпит вход — будущий WS-обработчик (Фаза 3) не сможет передать значение вне [-1,1].

## Что дальше (Фаза 3)

WebSocket-канал: добавить в `http_server` WS-эндпоинт `/ws`, принимать текст `t,y` ~30 Гц и вызывать `car_drive(t, y)`; отдавать heartbeat назад. Затем Фаза 4 — watchdog-автостоп (`car_drive(0,0)` при отсутствии сообщений >300 мс) + ramp.
