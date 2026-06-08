#include "calibration.h"
#include <string.h>
#include "nvs.h"
#include "esp_log.h"

static const char *TAG = "calib";
#define NS  "car"
#define KEY "calib"

bool calibration_load(motors_config_t *out) {
    nvs_handle_t h;
    if (nvs_open(NS, NVS_READONLY, &h) != ESP_OK) return false;
    motors_config_t tmp;
    size_t len = sizeof(tmp);
    esp_err_t e = nvs_get_blob(h, KEY, &tmp, &len);
    nvs_close(h);
    if (e != ESP_OK || len != sizeof(tmp) || !calibration_valid(&tmp)) return false;
    *out = tmp;
    ESP_LOGI(TAG, "loaded calibration from NVS");
    return true;
}

esp_err_t calibration_save(const motors_config_t *cfg) {
    if (!calibration_valid(cfg)) return ESP_ERR_INVALID_ARG;
    nvs_handle_t h;
    esp_err_t e = nvs_open(NS, NVS_READWRITE, &h);
    if (e != ESP_OK) return e;
    e = nvs_set_blob(h, KEY, cfg, sizeof(*cfg));
    if (e == ESP_OK) e = nvs_commit(h);
    nvs_close(h);
    if (e == ESP_OK) ESP_LOGI(TAG, "saved calibration to NVS");
    return e;
}
