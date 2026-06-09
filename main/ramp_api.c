#include "ramp_api.h"
#include <stdio.h>
#include <stdlib.h>
#include "esp_http_server.h"
#include "esp_log.h"
#include "esp_check.h"
#include "nvs.h"
#include "http_server.h"
#include "ramp.h"

static const char *TAG = "ramp_api";

static esp_err_t ramp_get(httpd_req_t *req) {
    char buf[32];
    int n = snprintf(buf, sizeof(buf), "{\"ramp_ms\":%u}", ramp_get_ms());
    httpd_resp_set_type(req, "application/json");
    return httpd_resp_send(req, buf, n);
}

static esp_err_t ramp_post(httpd_req_t *req) {
    char body[16] = {0};
    int len = httpd_req_recv(req, body, sizeof(body) - 1);
    if (len <= 0) { httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "empty"); return ESP_FAIL; }
    char *end;
    long v = strtol(body, &end, 10);
    if (end == body || v < 0 || v > 2000) {
        httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "ramp_ms must be 0..2000");
        return ESP_FAIL;
    }
    ramp_set_ms((uint16_t)v);
    nvs_handle_t h;
    if (nvs_open("car", NVS_READWRITE, &h) == ESP_OK) {
        if (nvs_set_u16(h, "ramp_ms", (uint16_t)v) == ESP_OK) nvs_commit(h);
        nvs_close(h);
    }
    return httpd_resp_sendstr(req, "ok");
}

esp_err_t ramp_api_start(void) {
    httpd_handle_t server = http_server_get_handle();
    if (server == NULL) { ESP_LOGE(TAG, "http server not started"); return ESP_FAIL; }
    httpd_uri_t g = { .uri = "/ramp", .method = HTTP_GET, .handler = ramp_get };
    httpd_uri_t p = { .uri = "/ramp", .method = HTTP_POST, .handler = ramp_post };
    ESP_RETURN_ON_ERROR(httpd_register_uri_handler(server, &g), TAG, "reg GET /ramp");
    ESP_RETURN_ON_ERROR(httpd_register_uri_handler(server, &p), TAG, "reg POST /ramp");
    return ESP_OK;
}
