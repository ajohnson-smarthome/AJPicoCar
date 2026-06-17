#include "calibration.h"
#include <string.h>
#include <stdio.h>
#include "nvs.h"
#include "esp_log.h"
#include "cJSON.h"

static const char *TAG = "calib";
#define NS  "car"
#define KEY "calib"

bool calibration_load(motors_config_t *out) {
    nvs_handle_t h;
    if (nvs_open(NS, NVS_READONLY, &h) != ESP_OK) return false;
    char buf[160];
    size_t len = sizeof(buf);
    esp_err_t e = nvs_get_str(h, KEY, buf, &len);
    nvs_close(h);
    if (e != ESP_OK) return false;
    cJSON *j = cJSON_Parse(buf);
    cJSON *jdz = cJSON_GetObjectItemCaseSensitive(j, "deadzone");
    cJSON *arr = cJSON_GetObjectItemCaseSensitive(j, "wheels");
    if (!cJSON_IsNumber(jdz) || !cJSON_IsArray(arr) || cJSON_GetArraySize(arr) != 4) {
        cJSON_Delete(j);
        return false;
    }
    motors_config_t tmp = { .deadzone = (float)jdz->valuedouble };
    for (int i = 0; i < 4; i++) {
        cJSON *w = cJSON_GetArrayItem(arr, i);
        cJSON *jp = cJSON_GetObjectItemCaseSensitive(w, "pair");
        cJSON *js = cJSON_GetObjectItemCaseSensitive(w, "sign");
        if (!cJSON_IsNumber(jp) || !cJSON_IsNumber(js)) { cJSON_Delete(j); return false; }
        tmp.wheels[i].channel_pair = (uint8_t)jp->valueint;
        tmp.wheels[i].sign = (int8_t)js->valueint;
    }
    cJSON_Delete(j);
    if (!calibration_valid(&tmp)) return false;
    *out = tmp;
    ESP_LOGI(TAG, "loaded calibration from NVS");
    return true;
}

esp_err_t calibration_save(const motors_config_t *cfg) {
    if (!calibration_valid(cfg)) return ESP_ERR_INVALID_ARG;
    char buf[160];
    int n = snprintf(buf, sizeof(buf), "{\"deadzone\":%.3f,\"wheels\":[", (double)cfg->deadzone);
    for (int i = 0; i < 4; i++) {
        n += snprintf(buf + n, sizeof(buf) - n, "%s{\"pair\":%u,\"sign\":%d}",
                      i ? "," : "", cfg->wheels[i].channel_pair, cfg->wheels[i].sign);
    }
    snprintf(buf + n, sizeof(buf) - n, "]}");
    nvs_handle_t h;
    esp_err_t e = nvs_open(NS, NVS_READWRITE, &h);
    if (e != ESP_OK) return e;
    e = nvs_set_str(h, KEY, buf);
    if (e == ESP_OK) e = nvs_commit(h);
    nvs_close(h);
    if (e == ESP_OK) ESP_LOGI(TAG, "saved calibration to NVS");
    return e;
}
