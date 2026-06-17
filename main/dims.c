#include "dims.h"
#include <stdio.h>
#include "cJSON.h"
#include "esp_log.h"
#include "nvs.h"

static const char *TAG = "dims";

static dims_params_t s_params = { .track_mm = 130, .wheelbase_mm = 210 };

static uint16_t clamp_u16(uint16_t v, uint16_t lo, uint16_t hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

void dims_set(const dims_params_t *in) {
    if (!in) return;
    s_params.track_mm     = clamp_u16(in->track_mm, DIMS_TRACK_MIN_MM, DIMS_TRACK_MAX_MM);
    s_params.wheelbase_mm = clamp_u16(in->wheelbase_mm, DIMS_WHEELBASE_MIN_MM, DIMS_WHEELBASE_MAX_MM);
}

void dims_get(dims_params_t *out) {
    if (out) *out = s_params;
}

// JSON string in NVS under "dims": {"track_mm":..,"wheelbase_mm":..}
void dims_save(void) {
    char buf[64];
    snprintf(buf, sizeof(buf), "{\"track_mm\":%u,\"wheelbase_mm\":%u}",
             s_params.track_mm, s_params.wheelbase_mm);
    nvs_handle_t h;
    if (nvs_open("car", NVS_READWRITE, &h) == ESP_OK) {
        esp_err_t e = nvs_set_str(h, "dims", buf);
        if (e == ESP_OK) e = nvs_commit(h);
        if (e != ESP_OK) ESP_LOGW(TAG, "dims save failed: %s", esp_err_to_name(e));
        nvs_close(h);
    }
}

void dims_init(void) {
    nvs_handle_t h;
    if (nvs_open("car", NVS_READONLY, &h) == ESP_OK) {
        char buf[64];
        size_t len = sizeof(buf);
        if (nvs_get_str(h, "dims", buf, &len) == ESP_OK) {
            cJSON *j = cJSON_Parse(buf);
            cJSON *jt = cJSON_GetObjectItemCaseSensitive(j, "track_mm");
            cJSON *jw = cJSON_GetObjectItemCaseSensitive(j, "wheelbase_mm");
            if (cJSON_IsNumber(jt) && cJSON_IsNumber(jw)) {
                dims_params_t d = { .track_mm = (uint16_t)jt->valueint, .wheelbase_mm = (uint16_t)jw->valueint };
                dims_set(&d);   // clamps + applies
            }
            cJSON_Delete(j);
        }
        nvs_close(h);
    }
    ESP_LOGI(TAG, "dims track=%u mm wheelbase=%u mm", s_params.track_mm, s_params.wheelbase_mm);
}
