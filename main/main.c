#include <stdio.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/usb_serial_jtag.h"
#include "esp_log.h"

#include "pca9685.h"
#include "car.h"
#include "nvs_flash.h"
#include "wifi_ap.h"
#include "http_server.h"
#include "ws_control.h"
#include "watchdog.h"

static const char *TAG = "main";

#define I2C_SDA_PIN  22
#define I2C_SCL_PIN  23
#define I2C_FREQ_HZ  400000
#define PWM_FREQ_HZ  1000
#define AP_SSID      "ESP32-Car"
#define AP_PASSWORD  "drive1234"   // >= 8 chars for WPA2; "" for open
#define WDT_TIMEOUT_MS 300

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
    // Reject out-of-range console input early with an error (car_drive also clamps).
    if (*t < -1.0f || *t > 1.0f || *y < -1.0f || *y > 1.0f) return -1;
    return 0;
}

void app_main(void) {
    ESP_ERROR_CHECK(pca9685_bus_init(I2C_SDA_PIN, I2C_SCL_PIN, I2C_FREQ_HZ));
    ESP_ERROR_CHECK(pca9685_init(PWM_FREQ_HZ));
    car_init();

    esp_err_t nvs = nvs_flash_init();
    if (nvs == ESP_ERR_NVS_NO_FREE_PAGES || nvs == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        nvs = nvs_flash_init();
    }
    ESP_ERROR_CHECK(nvs);
    ESP_ERROR_CHECK(wifi_ap_start(AP_SSID, AP_PASSWORD));
    ESP_ERROR_CHECK(http_server_start());
    ESP_ERROR_CHECK(ws_control_start());
    watchdog_init(WDT_TIMEOUT_MS);

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
