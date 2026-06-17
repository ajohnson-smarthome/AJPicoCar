#include "dims.h"
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

void dims_init(void) {
    nvs_handle_t h;
    if (nvs_open("car", NVS_READONLY, &h) == ESP_OK) {
        uint16_t v;
        if (nvs_get_u16(h, "track_mm", &v) == ESP_OK)     s_params.track_mm = clamp_u16(v, DIMS_TRACK_MIN_MM, DIMS_TRACK_MAX_MM);
        if (nvs_get_u16(h, "wheelbase_mm", &v) == ESP_OK) s_params.wheelbase_mm = clamp_u16(v, DIMS_WHEELBASE_MIN_MM, DIMS_WHEELBASE_MAX_MM);
        nvs_close(h);
    }
    ESP_LOGI(TAG, "dims track=%u mm wheelbase=%u mm", s_params.track_mm, s_params.wheelbase_mm);
}
