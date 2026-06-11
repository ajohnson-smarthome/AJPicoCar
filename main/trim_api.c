#include "trim_api.h"
#include <stdio.h>
#include <stdlib.h>
#include "esp_http_server.h"
#include "esp_log.h"
#include "esp_check.h"
#include "nvs.h"
#include "http_server.h"
#include "car.h"

static const char *TAG = "trim_api";

static esp_err_t trim_get(httpd_req_t *req) {
    char buf[32];
    int n = snprintf(buf, sizeof(buf), "{\"trim_pct\":%d}", (int)car_get_trim());
    httpd_resp_set_type(req, "application/json");
    return httpd_resp_send(req, buf, n);
}

static esp_err_t trim_post(httpd_req_t *req) {
    char body[16] = {0};
    int len = httpd_req_recv(req, body, sizeof(body) - 1);
    if (len <= 0) return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "empty");
    char *end;
    long v = strtol(body, &end, 10);
    if (end == body || v < -30 || v > 30) {
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "trim_pct must be -30..30");
    }
    car_set_trim((int8_t)v);
    nvs_handle_t h;
    if (nvs_open("car", NVS_READWRITE, &h) == ESP_OK) {
        esp_err_t e = nvs_set_i8(h, "trim_pct", (int8_t)v);
        if (e == ESP_OK) e = nvs_commit(h);
        if (e != ESP_OK) ESP_LOGW(TAG, "trim save failed: %s", esp_err_to_name(e));
        nvs_close(h);
    }
    return httpd_resp_sendstr(req, "ok");
}

esp_err_t trim_api_start(void) {
    httpd_handle_t server = http_server_get_handle();
    if (server == NULL) { ESP_LOGE(TAG, "http server not started"); return ESP_FAIL; }
    httpd_uri_t g = { .uri = "/trim", .method = HTTP_GET, .handler = trim_get };
    httpd_uri_t p = { .uri = "/trim", .method = HTTP_POST, .handler = trim_post };
    ESP_RETURN_ON_ERROR(httpd_register_uri_handler(server, &g), TAG, "reg GET /trim");
    ESP_RETURN_ON_ERROR(httpd_register_uri_handler(server, &p), TAG, "reg POST /trim");
    return ESP_OK;
}
