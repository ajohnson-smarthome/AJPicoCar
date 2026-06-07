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
