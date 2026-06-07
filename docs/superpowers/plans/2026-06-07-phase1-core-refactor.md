# Фаза 1: Рефактор ядра + пропорциональная скорость — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Вынести PWM-драйвер в модуль и добавить чистые, хост-тестируемые модули `mixer` (танковое смешивание) и `motors` (планирование ШИМ по бортам с калибровочной таблицей), заменив бинарное управление пропорциональным — всё проверяемо через USB-мост.

**Architecture:** Чистая логика (математика разворота и планирование ШИМ) выделяется в файлы без зависимостей от ESP-IDF, чтобы компилироваться и тестироваться на хосте (clang) по TDD. Аппаратная часть (I2C/PCA9685) изолирована в отдельном модуле. `main.c` лишь связывает их и временно использует USB-консоль как интерфейс (`mix <t> <y>`) для проверки до появления WiFi.

**Tech Stack:** C11, ESP-IDF 5.4 (target esp32c6), clang + GNU Make для хост-тестов, Unity не используется (минимальный assert-раннер).

---

## File Structure

| Файл | Ответственность | Тест |
|---|---|---|
| `main/mixer.h` / `main/mixer.c` | Чистая функция `mixer_mix(t,y) → {left,right}` | хост |
| `main/motors.h` / `main/motors.c` | Чистая функция `motors_plan(left,right,cfg) → 8 duty`; типы калибровки | хост |
| `main/pca9685.h` / `main/pca9685.c` | I2C-инициализация + `pca9685_init` + `pca9685_set_pwm` (вынесено из main) | железо |
| `main/main.c` | Связка: init → дефолтный config → консоль `mix t y` → plan → apply | стенд/мост |
| `main/CMakeLists.txt` | Регистрация новых исходников | — |
| `test/Makefile` | Хост-сборка и запуск тестов | — |
| `test/test_mixer.c` | Тесты `mixer_mix` | — |
| `test/test_motors.c` | Тесты `motors_plan` | — |

**Принцип изоляции:** `mixer.c` и `motors.c` НЕ включают ничего из ESP-IDF (только `<stdint.h>`), поэтому собираются обычным `cc`. Применение к железу (`motors_apply`) живёт в `main.c`, а не в `motors.c`.

---

## Task 0: Инициализация git и тестового каркаса

**Files:**
- Create: `.gitignore`
- Create: `test/Makefile`

- [ ] **Step 1: Инициализировать git и сделать стартовый коммит текущего состояния**

Проект ещё не под git. Инициализируем и фиксируем текущее рабочее состояние, чтобы дальше делать частые коммиты.

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git init
```

- [ ] **Step 2: Создать `.gitignore`**

Create `.gitignore`:

```gitignore
build/
sdkconfig.old
test/test_mixer
test/test_motors
*.o
.DS_Store
```

- [ ] **Step 3: Стартовый коммит**

```bash
git add -A
git commit -m "chore: initial commit of existing firmware before phase 1 refactor"
```

- [ ] **Step 4: Создать `test/Makefile`**

Create `test/Makefile`:

```makefile
CC = cc
CFLAGS = -I../main -Wall -Wextra -Werror -std=c11

all: test_mixer test_motors

test_mixer: test_mixer.c ../main/mixer.c
	$(CC) $(CFLAGS) -o $@ $^

test_motors: test_motors.c ../main/motors.c
	$(CC) $(CFLAGS) -o $@ $^

run: all
	./test_mixer && ./test_motors

clean:
	rm -f test_mixer test_motors
```

- [ ] **Step 5: Коммит каркаса**

```bash
git add test/Makefile .gitignore
git commit -m "test: add host test harness Makefile"
```

---

## Task 1: Модуль `mixer` — смешивание танкового разворота

**Files:**
- Create: `main/mixer.h`
- Create: `main/mixer.c`
- Test: `test/test_mixer.c`

- [ ] **Step 1: Написать заголовок интерфейса**

Create `main/mixer.h`:

```c
#ifndef MIXER_H
#define MIXER_H

// Нормализованные скорости бортов, каждая в диапазоне [-1.0, 1.0].
typedef struct {
    float left;
    float right;
} side_speeds_t;

// Смешать throttle и yaw (каждый в [-1, 1]) в скорости левого/правого борта.
// Результат нормализуется с сохранением пропорции: оба значения попадают в [-1, 1].
//   mix(1,0)   -> {1, 1}    прямо
//   mix(0,1)   -> {1,-1}    разворот на месте
//   mix(0.5,0.5)->{1, 0}    дуга
side_speeds_t mixer_mix(float throttle, float yaw);

#endif // MIXER_H
```

- [ ] **Step 2: Написать падающий тест**

Create `test/test_mixer.c`:

```c
#include "mixer.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

static int approx(float a, float b) { return fabsf(a - b) < 1e-4f; }

static void check(float t, float y, float el, float er) {
    side_speeds_t s = mixer_mix(t, y);
    if (!approx(s.left, el) || !approx(s.right, er)) {
        printf("FAIL mix(%.2f,%.2f) = {%.4f,%.4f}, expected {%.4f,%.4f}\n",
               t, y, s.left, s.right, el, er);
        assert(0);
    }
}

int main(void) {
    check(0.0f, 0.0f, 0.0f, 0.0f);   // стоп
    check(1.0f, 0.0f, 1.0f, 1.0f);   // прямо
    check(-1.0f, 0.0f, -1.0f, -1.0f);// назад
    check(0.0f, 1.0f, 1.0f, -1.0f);  // разворот на месте
    check(0.0f, -1.0f, -1.0f, 1.0f); // разворот в другую сторону
    check(0.5f, 0.5f, 1.0f, 0.0f);   // дуга (нормализация t+y=1)
    check(1.0f, 1.0f, 1.0f, 0.0f);   // насыщение: left=2,right=0 -> /2
    printf("test_mixer: all passed\n");
    return 0;
}
```

- [ ] **Step 3: Запустить тест — убедиться, что не компилируется/падает**

Run: `cd test && make test_mixer`
Expected: ошибка линковки/компиляции — `mixer.c` ещё не существует (нет файла `../main/mixer.c`).

- [ ] **Step 4: Реализовать минимально**

Create `main/mixer.c`:

```c
#include "mixer.h"

static float absf(float x) { return x < 0.0f ? -x : x; }

side_speeds_t mixer_mix(float throttle, float yaw) {
    float left = throttle + yaw;
    float right = throttle - yaw;

    float m = absf(left);
    if (absf(right) > m) m = absf(right);
    if (m < 1.0f) m = 1.0f;   // не усиливаем, только нормализуем при насыщении

    side_speeds_t s;
    s.left = left / m;
    s.right = right / m;
    return s;
}
```

- [ ] **Step 5: Запустить тест — убедиться, что проходит**

Run: `cd test && make run`
Expected: `test_mixer: all passed`

- [ ] **Step 6: Коммит**

```bash
git add main/mixer.h main/mixer.c test/test_mixer.c
git commit -m "feat: add mixer module with host tests for tank-turn mixing"
```

---

## Task 2: Модуль `motors` — планирование ШИМ с калибровочной таблицей

**Files:**
- Create: `main/motors.h`
- Create: `main/motors.c`
- Test: `test/test_motors.c`

- [ ] **Step 1: Написать заголовок интерфейса**

Create `main/motors.h`:

```c
#ifndef MOTORS_H
#define MOTORS_H

#include <stdint.h>

// Физические позиции колёс.
typedef enum {
    POS_FL = 0,  // перёд-лево
    POS_FR,      // перёд-право
    POS_RL,      // зад-лево
    POS_RR,      // зад-право
    POS_COUNT
} wheel_pos_t;

// Калибровка одного колеса: какая пара каналов PCA9685 и знак направления.
typedef struct {
    uint8_t channel_pair;  // 0..3 -> каналы (pair*2 = CH_A, pair*2+1 = CH_B)
    int8_t  sign;          // +1 нормально, -1 направление инвертировано
} wheel_calib_t;

// Конфигурация привода: калибровка по позициям + мёртвая зона.
typedef struct {
    wheel_calib_t wheels[POS_COUNT];
    float deadzone;        // |скорость| ниже этого -> мотор стоит
} motors_config_t;

// 8 значений ШИМ-заполнения, каждое 0..4095.
typedef struct {
    uint16_t duty[8];
} motor_outputs_t;

// Спланировать ШИМ по каналам из скоростей бортов (каждая в [-1,1]).
// Левый борт = {FL, RL}, правый = {FR, RR}. Применяет знак калибровки.
// Чистая функция, без ввода-вывода. Forward: CH_A=duty, CH_B=0. Reverse: наоборот.
motor_outputs_t motors_plan(float left, float right, const motors_config_t *cfg);

#endif // MOTORS_H
```

- [ ] **Step 2: Написать падающий тест**

Create `test/test_motors.c`:

```c
#include "motors.h"
#include <assert.h>
#include <stdio.h>

// Дефолтная калибровка: FL->пара0, FR->пара1, RL->пара2, RR->пара3, без инверсии.
static motors_config_t default_cfg(void) {
    motors_config_t c = {
        .wheels = {
            [POS_FL] = { .channel_pair = 0, .sign = 1 },
            [POS_FR] = { .channel_pair = 1, .sign = 1 },
            [POS_RL] = { .channel_pair = 2, .sign = 1 },
            [POS_RR] = { .channel_pair = 3, .sign = 1 },
        },
        .deadzone = 0.05f,
    };
    return c;
}

static void expect(const char *name, uint16_t got, uint16_t want) {
    if (got != want) {
        printf("FAIL %s: got %u, want %u\n", name, got, want);
        assert(0);
    }
}

int main(void) {
    motors_config_t cfg = default_cfg();

    // Прямо на полной: все CH_A=4095, CH_B=0.
    motor_outputs_t o = motors_plan(1.0f, 1.0f, &cfg);
    expect("fwd ch0", o.duty[0], 4095); expect("fwd ch1", o.duty[1], 0);
    expect("fwd ch2", o.duty[2], 4095); expect("fwd ch3", o.duty[3], 0);
    expect("fwd ch4", o.duty[4], 4095); expect("fwd ch5", o.duty[5], 0);
    expect("fwd ch6", o.duty[6], 4095); expect("fwd ch7", o.duty[7], 0);

    // Стоп: всё 0.
    o = motors_plan(0.0f, 0.0f, &cfg);
    for (int i = 0; i < 8; i++) expect("stop", o.duty[i], 0);

    // Танк (left=+1, right=-1): левый борт вперёд (CH_A), правый назад (CH_B).
    o = motors_plan(1.0f, -1.0f, &cfg);
    expect("tank FL A", o.duty[0], 4095); expect("tank FL B", o.duty[1], 0);
    expect("tank RL A", o.duty[4], 4095); expect("tank RL B", o.duty[5], 0);
    expect("tank FR A", o.duty[2], 0);    expect("tank FR B", o.duty[3], 4095);
    expect("tank RR A", o.duty[6], 0);    expect("tank RR B", o.duty[7], 4095);

    // Половина газа: duty ~ 2048.
    o = motors_plan(0.5f, 0.5f, &cfg);
    expect("half ch0", o.duty[0], 2048); expect("half ch1", o.duty[1], 0);

    // Мёртвая зона: малая скорость -> стоп.
    o = motors_plan(0.02f, 0.0f, &cfg);
    for (int i = 0; i < 8; i++) expect("deadzone", o.duty[i], 0);

    // Инверсия знака FL: left=+1 -> FL едет назад (CH_B), а не вперёд.
    cfg.wheels[POS_FL].sign = -1;
    o = motors_plan(1.0f, 0.0f, &cfg);
    expect("rev FL A", o.duty[0], 0); expect("rev FL B", o.duty[1], 4095);
    expect("rev RL A (unchanged)", o.duty[4], 4095);

    printf("test_motors: all passed\n");
    return 0;
}
```

- [ ] **Step 3: Запустить тест — убедиться, что не компилируется**

Run: `cd test && make test_motors`
Expected: ошибка — нет `../main/motors.c`.

- [ ] **Step 4: Реализовать минимально**

Create `main/motors.c`:

```c
#include "motors.h"

static float absf(float x) { return x < 0.0f ? -x : x; }

static float side_for(wheel_pos_t pos, float left, float right) {
    switch (pos) {
        case POS_FL:
        case POS_RL: return left;
        case POS_FR:
        case POS_RR: return right;
        default:     return 0.0f;
    }
}

motor_outputs_t motors_plan(float left, float right, const motors_config_t *cfg) {
    motor_outputs_t out = { .duty = {0} };

    for (int p = 0; p < POS_COUNT; p++) {
        const wheel_calib_t *w = &cfg->wheels[p];
        float s = side_for((wheel_pos_t)p, left, right) * (float)w->sign;

        uint8_t ch_a = (uint8_t)(w->channel_pair * 2);
        uint8_t ch_b = (uint8_t)(ch_a + 1);

        float mag = absf(s);
        if (mag > 1.0f) mag = 1.0f;
        uint16_t duty = (uint16_t)(mag * 4095.0f + 0.5f);

        if (s > cfg->deadzone) {          // вперёд
            out.duty[ch_a] = duty;
            out.duty[ch_b] = 0;
        } else if (s < -cfg->deadzone) {  // назад
            out.duty[ch_a] = 0;
            out.duty[ch_b] = duty;
        } else {                          // стоп
            out.duty[ch_a] = 0;
            out.duty[ch_b] = 0;
        }
    }
    return out;
}
```

- [ ] **Step 5: Запустить тесты — убедиться, что проходят**

Run: `cd test && make run`
Expected: `test_mixer: all passed` и `test_motors: all passed`

- [ ] **Step 6: Коммит**

```bash
git add main/motors.h main/motors.c test/test_motors.c
git commit -m "feat: add motors planner with calibration table and host tests"
```

---

## Task 3: Вынести PCA9685/I2C в модуль `pca9685`

**Files:**
- Create: `main/pca9685.h`
- Create: `main/pca9685.c`
- Modify: `main/main.c` (удалить вынесенный код, добавить include)

- [ ] **Step 1: Написать заголовок `pca9685.h`**

Create `main/pca9685.h`:

```c
#ifndef PCA9685_H
#define PCA9685_H

#include <stdint.h>
#include "esp_err.h"

// Инициализировать I2C-шину и устройство PCA9685. Вызвать один раз до остального.
esp_err_t pca9685_bus_init(int sda_pin, int scl_pin, uint32_t freq_hz);

// Настроить ШИМ-частоту PCA9685 (sleep->prescale->wake->restart).
esp_err_t pca9685_init(uint16_t pwm_freq_hz);

// Выставить ШИМ-заполнение канала 0..15, duty 0..4095.
esp_err_t pca9685_set_pwm(uint8_t channel, uint16_t duty);

#endif // PCA9685_H
```

- [ ] **Step 2: Реализовать `pca9685.c` переносом из текущего `main.c`**

Create `main/pca9685.c` (перенос строк 12–106 текущего `main/main.c`, обёрнуто в новый API):

```c
#include "pca9685.h"
#include "driver/i2c_master.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_check.h"

static const char *TAG = "pca9685";

#define PCA9685_ADDR        0x40
#define PCA9685_MODE1       0x00
#define PCA9685_PRESCALE    0xFE
#define PCA9685_LED0_ON_L   0x06

#define PCA9685_MODE1_RESTART  0x80
#define PCA9685_MODE1_AI       0x20
#define PCA9685_MODE1_SLEEP    0x10

static i2c_master_bus_handle_t bus_handle;
static i2c_master_dev_handle_t pca9685_handle;

static esp_err_t pca9685_write_reg(uint8_t reg, uint8_t value) {
    uint8_t buf[2] = {reg, value};
    return i2c_master_transmit(pca9685_handle, buf, sizeof(buf), -1);
}

static esp_err_t pca9685_read_reg(uint8_t reg, uint8_t *value) {
    return i2c_master_transmit_receive(pca9685_handle, &reg, 1, value, 1, -1);
}

esp_err_t pca9685_bus_init(int sda_pin, int scl_pin, uint32_t freq_hz) {
    i2c_master_bus_config_t bus_cfg = {
        .i2c_port = I2C_NUM_0,
        .sda_io_num = sda_pin,
        .scl_io_num = scl_pin,
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .glitch_ignore_cnt = 7,
        .flags.enable_internal_pullup = true,
    };
    ESP_RETURN_ON_ERROR(i2c_new_master_bus(&bus_cfg, &bus_handle), TAG, "I2C bus init failed");

    i2c_device_config_t dev_cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = PCA9685_ADDR,
        .scl_speed_hz = freq_hz,
    };
    ESP_RETURN_ON_ERROR(i2c_master_bus_add_device(bus_handle, &dev_cfg, &pca9685_handle), TAG, "PCA9685 add failed");
    return ESP_OK;
}

esp_err_t pca9685_init(uint16_t pwm_freq_hz) {
    uint8_t prescale = (uint8_t)((25000000.0 / (4096.0 * pwm_freq_hz)) - 0.5);
    ESP_LOGI(TAG, "PCA9685 prescale = %d for %d Hz", prescale, pwm_freq_hz);

    ESP_RETURN_ON_ERROR(pca9685_write_reg(PCA9685_MODE1, PCA9685_MODE1_SLEEP), TAG, "sleep failed");
    vTaskDelay(pdMS_TO_TICKS(5));
    ESP_RETURN_ON_ERROR(pca9685_write_reg(PCA9685_PRESCALE, prescale), TAG, "prescale failed");
    ESP_RETURN_ON_ERROR(pca9685_write_reg(PCA9685_MODE1, PCA9685_MODE1_AI), TAG, "wake failed");
    vTaskDelay(pdMS_TO_TICKS(5));

    uint8_t mode1;
    ESP_RETURN_ON_ERROR(pca9685_read_reg(PCA9685_MODE1, &mode1), TAG, "mode1 read failed");
    ESP_RETURN_ON_ERROR(pca9685_write_reg(PCA9685_MODE1, mode1 | PCA9685_MODE1_RESTART), TAG, "restart failed");

    ESP_LOGI(TAG, "PCA9685 initialized");
    return ESP_OK;
}

esp_err_t pca9685_set_pwm(uint8_t channel, uint16_t duty) {
    uint8_t base_reg = PCA9685_LED0_ON_L + 4 * channel;
    uint16_t on = 0;
    uint16_t off = duty;

    if (duty == 0) {
        on = 0; off = 0x1000;
    } else if (duty >= 4095) {
        on = 0x1000; off = 0;
    }

    uint8_t buf[5] = {
        base_reg,
        on & 0xFF, (on >> 8) & 0x1F,
        off & 0xFF, (off >> 8) & 0x1F,
    };
    return i2c_master_transmit(pca9685_handle, buf, sizeof(buf), -1);
}
```

- [ ] **Step 3: Удалить вынесенный код из `main.c`**

В `main/main.c` удалить: define-ы PCA9685/I2C (строки ~12–24, 37–40), функции `pca9685_write_reg`, `pca9685_read_reg`, `pca9685_init`, `pca9685_set_pwm`, `i2c_init` (строки ~26–106). Добавить вверху `#include "pca9685.h"`. (Полный новый `main.c` собирается в Task 4 — этот шаг только удаляет дубли и проверяет компиляцию.)

- [ ] **Step 4: Обновить `main/CMakeLists.txt`**

Replace `main/CMakeLists.txt` содержимым:

```cmake
idf_component_register(
    SRCS "main.c" "pca9685.c" "mixer.c" "motors.c"
    INCLUDE_DIRS "."
)
```

- [ ] **Step 5: Собрать прошивку**

Run:
```bash
mkdir -p /tmp/py313bin && ln -sf /opt/homebrew/bin/python3.13 /tmp/py313bin/python3
export PATH=/tmp/py313bin:$PATH
source ~/esp/esp-idf/export.sh
cd /Users/adamjohnson/VSCode/esp32-p4-car && idf.py build
```
Expected: сборка проходит (возможны временные предупреждения о неиспользуемых функциях в main.c — будут устранены в Task 4).

- [ ] **Step 6: Коммит**

```bash
git add main/pca9685.h main/pca9685.c main/main.c main/CMakeLists.txt
git commit -m "refactor: extract PCA9685/I2C driver into pca9685 module"
```

---

## Task 4: Связать модули в `main.c` — пропорциональная консольная команда

**Files:**
- Modify: `main/main.c` (полная новая версия)

- [ ] **Step 1: Заменить `main/main.c` целиком**

Replace `main/main.c`:

```c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/usb_serial_jtag.h"
#include "esp_log.h"
#include "esp_check.h"

#include "pca9685.h"
#include "mixer.h"
#include "motors.h"

static const char *TAG = "motor";

#define I2C_SDA_PIN  22
#define I2C_SCL_PIN  23
#define I2C_FREQ_HZ  400000
#define PWM_FREQ_HZ  1000

// Дефолтная калибровка (Фаза 1). В Фазе 5 заменяется значением из NVS.
static motors_config_t g_cfg = {
    .wheels = {
        [POS_FL] = { .channel_pair = 0, .sign = 1 },
        [POS_FR] = { .channel_pair = 1, .sign = 1 },
        [POS_RL] = { .channel_pair = 2, .sign = 1 },
        [POS_RR] = { .channel_pair = 3, .sign = 1 },
    },
    .deadzone = 0.05f,
};

// Применить спланированные ШИМ к 8 каналам PCA9685.
static void motors_apply(const motor_outputs_t *out) {
    for (uint8_t ch = 0; ch < 8; ch++) {
        esp_err_t e = pca9685_set_pwm(ch, out->duty[ch]);
        if (e != ESP_OK) {
            ESP_LOGE(TAG, "ch%d write failed: %s", ch, esp_err_to_name(e));
        }
    }
}

// Применить намерение (throttle, yaw) -> mixer -> planner -> железо.
static void drive(float throttle, float yaw) {
    side_speeds_t s = mixer_mix(throttle, yaw);
    motor_outputs_t out = motors_plan(s.left, s.right, &g_cfg);
    motors_apply(&out);
    ESP_LOGI(TAG, "drive t=%.2f y=%.2f -> L=%.2f R=%.2f", throttle, yaw, s.left, s.right);
}

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

// Парсинг "mix <t> <y>", где t,y в [-1,1]. Возвращает 0 при успехе.
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

    drive(0.0f, 0.0f);  // safety stop

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
            drive(t, y);
        } else {
            ESP_LOGE(TAG, "bad command, expected 'mix <t> <y>' with t,y in [-1,1]");
        }
    }
}
```

- [ ] **Step 2: Собрать прошивку**

Run:
```bash
export PATH=/tmp/py313bin:$PATH
source ~/esp/esp-idf/export.sh
cd /Users/adamjohnson/VSCode/esp32-p4-car && idf.py build
```
Expected: сборка без ошибок и без предупреждений о неиспользуемых функциях.

- [ ] **Step 3: Прошить плату**

Run:
```bash
ls /dev/cu.usbmodem*
idf.py -p /dev/cu.usbmodem<NNN> flash
```
Expected: `Hash of data verified.` и перезагрузка.

- [ ] **Step 4: Проверить через мост — половина газа прямо**

Перезапустить мост, если порт изменился (см. CLAUDE.md), затем:
```bash
: > /tmp/esp_out.log
echo "mix 0.5 0.0" > /tmp/esp_in
sleep 1.5 && tail -c 400 /tmp/esp_out.log | cat -v
```
Expected: лог содержит `drive t=0.50 y=0.00 -> L=0.50 R=0.50`. На стенде (колёса вывешены) все 4 колеса крутятся вперёд вполовину скорости.

- [ ] **Step 5: Проверить через мост — танковый разворот на месте**

```bash
: > /tmp/esp_out.log
echo "mix 0.0 1.0" > /tmp/esp_in
sleep 1.5 && tail -c 400 /tmp/esp_out.log | cat -v
echo "mix 0.0 0.0" > /tmp/esp_in   # стоп
```
Expected: лог `drive t=0.00 y=1.00 -> L=1.00 R=-1.00`. Левый борт крутится вперёд, правый — назад (разворот на месте).

- [ ] **Step 6: Коммит**

```bash
git add main/main.c
git commit -m "feat: wire mixer+motors into main with proportional 'mix t y' console command"
```

---

## Self-Review заметки

- **Покрытие спеки (Фаза 1):** рефактор `pca9685` (Task 3), `mixer` (Task 1), `motors` с калибровочной таблицей-типом (Task 2), пропорциональная скорость (Task 2/4), хост-тесты (Task 1/2), проверка через мост (Task 4). Watchdog/ramp/WiFi/калибровочный UX — последующие фазы, вне объёма этого плана.
- **Тип-консистентность:** `side_speeds_t {left,right}` (mixer) → входы `motors_plan(left,right,cfg)`; `motors_config_t`/`wheel_calib_t`/`motor_outputs_t` едины в `motors.h`, тесте и `main.c`. `motors_plan` и `pca9685_set_pwm` сигнатуры совпадают с использованием в `motors_apply`.
- **Калибровочная таблица** введена уже в Фазе 1 как структура с дефолтом в `main.c` — в Фазе 5 источник меняется на NVS без переписывания `motors_plan`.
- **Граница хост/железо:** `mixer.c` и `motors.c` без ESP-зависимостей (только `<stdint.h>`), собираются `cc`; `motors_apply` живёт в `main.c`.

## Что дальше (последующие фазы — отдельные планы)

2. WiFi softAP + HTTP-сервер (отдача статической страницы).
3. WebSocket + протокол `t,y` → `drive()`.
4. Watchdog-автостоп + ramp (slew-rate limit в новом слое перед `motors_apply`).
5. Калибровка: модуль `calibration` + NVS + эндпоинты + калибровочный экран-гейт.
6. Captive-portal + PWA + обе схемы UI.
