#include "wheel.h"
#include <stdio.h>
#include "cJSON.h"
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

// JSON string in NVS under "wheel": {"diameter_mm":..,"ppr":..,"gear_x100":..,"quad":..}
void wheel_save(void) {
    char buf[96];
    snprintf(buf, sizeof(buf), "{\"diameter_mm\":%u,\"ppr\":%u,\"gear_x100\":%u,\"quad\":%u}",
             s_params.diameter_mm, s_params.ppr, s_params.gear_x100, s_params.quad);
    nvs_handle_t h;
    if (nvs_open("car", NVS_READWRITE, &h) == ESP_OK) {
        esp_err_t e = nvs_set_str(h, "wheel", buf);
        if (e == ESP_OK) e = nvs_commit(h);
        if (e != ESP_OK) ESP_LOGW(TAG, "wheel save failed: %s", esp_err_to_name(e));
        nvs_close(h);
    }
}

void wheel_init(void) {
    nvs_handle_t h;
    if (nvs_open("car", NVS_READONLY, &h) == ESP_OK) {
        char buf[96];
        size_t len = sizeof(buf);
        if (nvs_get_str(h, "wheel", buf, &len) == ESP_OK) {
            cJSON *j = cJSON_Parse(buf);
            cJSON *jd = cJSON_GetObjectItemCaseSensitive(j, "diameter_mm");
            cJSON *jp = cJSON_GetObjectItemCaseSensitive(j, "ppr");
            cJSON *jg = cJSON_GetObjectItemCaseSensitive(j, "gear_x100");
            cJSON *jq = cJSON_GetObjectItemCaseSensitive(j, "quad");
            if (cJSON_IsNumber(jd) && cJSON_IsNumber(jp) && cJSON_IsNumber(jg) && cJSON_IsNumber(jq)) {
                wheel_params_t w = { .diameter_mm = (uint16_t)jd->valueint, .ppr = (uint16_t)jp->valueint,
                                     .gear_x100 = (uint16_t)jg->valueint, .quad = (uint8_t)jq->valueint };
                wheel_set(&w);   // clamps + applies
            }
            cJSON_Delete(j);
        }
        nvs_close(h);
    }
    ESP_LOGI(TAG, "wheel d=%u mm ppr=%u gear=%u/100 quad=%u (cpr %.0f)",
             s_params.diameter_mm, s_params.ppr, s_params.gear_x100, s_params.quad,
             (double)wheel_cpr(&s_params));
}
