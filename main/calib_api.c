#include "calib_api.h"
#include <stdio.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_http_server.h"
#include "esp_log.h"
#include "esp_check.h"
#include "http_server.h"
#include "calibration.h"
#include "car.h"
#include "motors.h"

static const char *TAG = "calib_api";

// Read the POST body into buf (NUL-terminated). Returns 0 on success, -1 otherwise.
static int read_body(httpd_req_t *req, char *buf, size_t n) {
    if (req->content_len <= 0 || (size_t)req->content_len >= n) return -1;
    int got = httpd_req_recv(req, buf, req->content_len);
    if (got <= 0) return -1;
    buf[got] = '\0';
    return 0;
}

// GET /calib -> {"calibrated":true|false}
static esp_err_t calib_get(httpd_req_t *req) {
    motors_config_t tmp;
    bool cal = calibration_load(&tmp);
    httpd_resp_set_type(req, "application/json");
    return httpd_resp_sendstr(req, cal ? "{\"calibrated\":true}" : "{\"calibrated\":false}");
}

// POST /calib/spin  body "<pair>,<dir>" (dir 1=forward, 0=reverse). Pulses ~0.6s.
static esp_err_t calib_spin(httpd_req_t *req) {
    char b[32];
    if (read_body(req, b, sizeof(b)) != 0) {
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "bad body");
    }
    unsigned pair, dir;
    if (sscanf(b, "%u,%u", &pair, &dir) != 2 || pair > 3) {
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "bad args");
    }
    ESP_LOGI(TAG, "spin pair %u %s", pair, dir ? "fwd" : "rev");
    car_spin_pair((uint8_t)pair, dir != 0);
    vTaskDelay(pdMS_TO_TICKS(600));
    car_stop();
    return httpd_resp_sendstr(req, "ok");
}

// POST /calib/save  body "<p>:<s>,<p>:<s>,<p>:<s>,<p>:<s>" for FL,FR,RL,RR.
static esp_err_t calib_save(httpd_req_t *req) {
    char b[64];
    if (read_body(req, b, sizeof(b)) != 0) {
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "bad body");
    }
    unsigned p[4];
    int s[4];
    if (sscanf(b, "%u:%d,%u:%d,%u:%d,%u:%d",
               &p[0], &s[0], &p[1], &s[1], &p[2], &s[2], &p[3], &s[3]) != 8) {
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "bad format");
    }
    motors_config_t cfg = { .deadzone = 0.05f };
    for (int i = 0; i < 4; i++) {
        cfg.wheels[i].channel_pair = (uint8_t)p[i];
        cfg.wheels[i].sign = (int8_t)s[i];
    }
    esp_err_t e = calibration_save(&cfg);
    if (e != ESP_OK) {
        ESP_LOGW(TAG, "save rejected: %s", esp_err_to_name(e));
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "invalid calibration");
    }
    car_set_calibration(&cfg);
    ESP_LOGI(TAG, "calibration saved and applied");
    return httpd_resp_sendstr(req, "ok");
}

esp_err_t calib_api_start(void) {
    httpd_handle_t server = http_server_get_handle();
    if (server == NULL) {
        ESP_LOGE(TAG, "http server not started");
        return ESP_FAIL;
    }
    httpd_uri_t get  = { .uri = "/calib",      .method = HTTP_GET,  .handler = calib_get };
    httpd_uri_t spin = { .uri = "/calib/spin", .method = HTTP_POST, .handler = calib_spin };
    httpd_uri_t save = { .uri = "/calib/save", .method = HTTP_POST, .handler = calib_save };
    ESP_RETURN_ON_ERROR(httpd_register_uri_handler(server, &get),  TAG, "reg /calib");
    ESP_RETURN_ON_ERROR(httpd_register_uri_handler(server, &spin), TAG, "reg /calib/spin");
    ESP_RETURN_ON_ERROR(httpd_register_uri_handler(server, &save), TAG, "reg /calib/save");
    ESP_LOGI(TAG, "calibration endpoints registered");
    return ESP_OK;
}
