#include "wheel.h"
#include "esp_log.h"
#include "nvs.h"

static const char *TAG = "wheel";

static wheel_params_t s_params = {
    .diameter_mm = 65, .ppr = 11, .gear_x100 = 2100, .quad = 4,
};

static uint16_t clamp_u16(uint16_t v, uint16_t lo, uint16_t hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

void wheel_set(const wheel_params_t *in) {
    if (!in) return;
    s_params.diameter_mm = clamp_u16(in->diameter_mm, WHEEL_D_MIN_MM, WHEEL_D_MAX_MM);
    s_params.ppr         = clamp_u16(in->ppr, WHEEL_PPR_MIN, WHEEL_PPR_MAX);
    s_params.gear_x100   = clamp_u16(in->gear_x100, WHEEL_GEAR_X100_MIN, WHEEL_GEAR_X100_MAX);
    s_params.quad        = (in->quad == 1 || in->quad == 2 || in->quad == 4) ? in->quad : 4;
}

void wheel_get(wheel_params_t *out) {
    if (out) *out = s_params;
}

void wheel_init(void) {
    nvs_handle_t h;
    if (nvs_open("car", NVS_READONLY, &h) == ESP_OK) {
        uint16_t v; uint8_t b;
        if (nvs_get_u16(h, "wheel_d", &v) == ESP_OK)   s_params.diameter_mm = clamp_u16(v, WHEEL_D_MIN_MM, WHEEL_D_MAX_MM);
        if (nvs_get_u16(h, "enc_ppr", &v) == ESP_OK)   s_params.ppr = clamp_u16(v, WHEEL_PPR_MIN, WHEEL_PPR_MAX);
        if (nvs_get_u16(h, "gear_x100", &v) == ESP_OK) s_params.gear_x100 = clamp_u16(v, WHEEL_GEAR_X100_MIN, WHEEL_GEAR_X100_MAX);
        if (nvs_get_u8(h, "quad", &b) == ESP_OK && (b == 1 || b == 2 || b == 4)) s_params.quad = b;
        nvs_close(h);
    }
    ESP_LOGI(TAG, "wheel d=%u mm ppr=%u gear=%u/100 quad=%u (cpr %.0f)",
             s_params.diameter_mm, s_params.ppr, s_params.gear_x100, s_params.quad,
             (double)wheel_cpr(&s_params));
}
