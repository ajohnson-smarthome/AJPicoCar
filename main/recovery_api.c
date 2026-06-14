#include "recovery_api.h"
#include <stdio.h>
#include "esp_http_server.h"
#include "esp_log.h"
#include "esp_check.h"
#include "nvs.h"
#include "http_server.h"
#include "recovery.h"

static const char *TAG = "recovery_api";

static esp_err_t recover_get(httpd_req_t *req) {
    bool en; uint16_t win;
    recovery_get_config(&en, &win);
    char buf[48];
    int n = snprintf(buf, sizeof(buf), "{\"enabled\":%s,\"window_ms\":%u}",
                     en ? "true" : "false", win);
    httpd_resp_set_type(req, "application/json");
    return httpd_resp_send(req, buf, n);
}

static esp_err_t recover_post(httpd_req_t *req) {
    char body[32] = {0};
    int len = httpd_req_recv(req, body, sizeof(body) - 1);
    if (len <= 0) return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "empty");
    // Body is two ints: "<0|1> <window_ms>" (avoids a JSON parser dependency).
    int en = -1; long win = -1;
    if (sscanf(body, "%d %ld", &en, &win) != 2 || (en != 0 && en != 1) ||
        win < RECOVER_WIN_MIN_MS || win > RECOVER_WIN_MAX_MS) {
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "need: <0|1> <1000..10000>");
    }
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
}

esp_err_t recovery_api_start(void) {
    httpd_handle_t server = http_server_get_handle();
    if (server == NULL) { ESP_LOGE(TAG, "http server not started"); return ESP_FAIL; }
    httpd_uri_t g = { .uri = "/recover", .method = HTTP_GET,  .handler = recover_get };
    httpd_uri_t p = { .uri = "/recover", .method = HTTP_POST, .handler = recover_post };
    ESP_RETURN_ON_ERROR(httpd_register_uri_handler(server, &g), TAG, "reg GET /recover");
    ESP_RETURN_ON_ERROR(httpd_register_uri_handler(server, &p), TAG, "reg POST /recover");
    return ESP_OK;
}
