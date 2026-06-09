#include "status_api.h"
#include <stdio.h>
#include <stdint.h>
#include "esp_http_server.h"
#include "esp_timer.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_check.h"
#include "esp_app_desc.h"
#include "esp_wifi.h"
#include "http_server.h"
#include "calibration.h"
#include "motors.h"
#include "ws_control.h"
#include "watchdog.h"

static const char *TAG = "status_api";

// RSSI of the first (and only) connected softAP client; 0 = no data.
static int ap_client_rssi(void) {
    wifi_sta_list_t sta;
    if (esp_wifi_ap_get_sta_list(&sta) != ESP_OK || sta.num == 0) return 0;
    return sta.sta[0].rssi;
}

// WS frames/sec between two consecutive /status polls (0 on first call or after a >10s gap).
static int ws_fps_since_last_poll(void) {
    static uint32_t last_frames = 0;
    static int64_t last_us = 0;
    uint32_t frames = ws_control_frames();
    int64_t now = esp_timer_get_time();
    int fps = 0;
    if (last_us != 0) {
        int64_t dt = now - last_us;
        if (dt > 0 && dt < 10 * 1000000LL) {
            fps = (int)(((int64_t)(uint32_t)(frames - last_frames) * 1000000LL) / dt);
        }
    }
    last_frames = frames;
    last_us = now;
    return fps;
}

static esp_err_t status_get(httpd_req_t *req) {
    motors_config_t tmp;
    bool calibrated = calibration_load(&tmp);
    long uptime_s = (long)(esp_timer_get_time() / 1000000);
    uint32_t heap = (uint32_t)esp_get_free_heap_size();
    const char *fw = esp_app_get_description()->version;

    char buf[224];
    int n = snprintf(buf, sizeof(buf),
        "{\"device\":\"esp32-car\",\"fw\":\"%s\",\"uptime_s\":%ld,\"calibrated\":%s,\"heap\":%u,"
        "\"rssi\":%d,\"ws_fps\":%d,\"wdt_trips\":%u}",
        fw, uptime_s, calibrated ? "true" : "false", (unsigned)heap,
        ap_client_rssi(), ws_fps_since_last_poll(), (unsigned)watchdog_trips());
    if (n < 0 || n >= (int)sizeof(buf)) n = (int)sizeof(buf) - 1;  // guard against truncation
    httpd_resp_set_type(req, "application/json");
    return httpd_resp_send(req, buf, n);
}

esp_err_t status_api_start(void) {
    httpd_handle_t server = http_server_get_handle();
    if (server == NULL) { ESP_LOGE(TAG, "http server not started"); return ESP_FAIL; }
    httpd_uri_t u = { .uri = "/status", .method = HTTP_GET, .handler = status_get };
    ESP_RETURN_ON_ERROR(httpd_register_uri_handler(server, &u), TAG, "reg /status");
    ESP_LOGI(TAG, "status endpoint registered");
    return ESP_OK;
}
