#include <stdio.h>
#include <string.h>
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

// Default calibration (Phase 1). Replaced by an NVS-stored table in Phase 5.
static motors_config_t g_cfg = {
    .wheels = {
        [POS_FL] = { .channel_pair = 0, .sign = 1 },
        [POS_FR] = { .channel_pair = 1, .sign = 1 },
        [POS_RL] = { .channel_pair = 2, .sign = 1 },
        [POS_RR] = { .channel_pair = 3, .sign = 1 },
    },
    .deadzone = 0.05f,
};

// Apply planned PWM to the 8 PCA9685 channels.
static void motors_apply(const motor_outputs_t *out) {
    for (uint8_t ch = 0; ch < 8; ch++) {
        esp_err_t e = pca9685_set_pwm(ch, out->duty[ch]);
        if (e != ESP_OK) {
            ESP_LOGE(TAG, "ch%d write failed: %s", ch, esp_err_to_name(e));
        }
    }
}

// Apply intent (throttle, yaw) -> mixer -> planner -> hardware.
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
