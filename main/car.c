#include "car.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "esp_log.h"
#include "esp_err.h"
#include "pca9685.h"
#include "mixer.h"
#include "motors.h"
#include "calibration.h"

static const char *TAG = "car";

// Default calibration (Phase 2). Replaced by an NVS-stored table in Phase 5.
static motors_config_t g_cfg = {
    .wheels = {
        [POS_FL] = { .channel_pair = 0, .sign = 1 },
        [POS_FR] = { .channel_pair = 1, .sign = 1 },
        [POS_RL] = { .channel_pair = 2, .sign = 1 },
        [POS_RR] = { .channel_pair = 3, .sign = 1 },
    },
    .deadzone = 0.05f,
};

// Serializes the 8-channel I2C write so concurrent callers (console + WebSocket
// tasks) can't interleave transactions on the shared PCA9685 handle.
static SemaphoreHandle_t g_lock;

static float clamp_unit(float v) {
    if (v > 1.0f) return 1.0f;
    if (v < -1.0f) return -1.0f;
    return v;
}

// Write planned PWM to the 8 PCA9685 channels.
static void motors_apply(const motor_outputs_t *out) {
    for (uint8_t ch = 0; ch < 8; ch++) {
        esp_err_t e = pca9685_set_pwm(ch, out->duty[ch]);
        if (e != ESP_OK) {
            ESP_LOGE(TAG, "ch%d write failed: %s", ch, esp_err_to_name(e));
        }
    }
}

void car_drive(float throttle, float yaw) {
    throttle = clamp_unit(throttle);
    yaw = clamp_unit(yaw);
    side_speeds_t s = mixer_mix(throttle, yaw);
    motor_outputs_t out = motors_plan(s.left, s.right, &g_cfg);

    // Bounded timeout so a stuck holder can't wedge the watchdog task forever.
    if (g_lock && xSemaphoreTake(g_lock, pdMS_TO_TICKS(200)) != pdTRUE) {
        ESP_LOGW(TAG, "drive: mutex busy >200ms, skipping write");
        return;
    }
    motors_apply(&out);
    if (g_lock) xSemaphoreGive(g_lock);

    ESP_LOGD(TAG, "drive t=%.2f y=%.2f -> L=%.2f R=%.2f", throttle, yaw, s.left, s.right);
}

void car_stop(void) {
    car_drive(0.0f, 0.0f);
}

void car_set_calibration(const motors_config_t *cfg) {
    if (g_lock) xSemaphoreTake(g_lock, pdMS_TO_TICKS(200));
    g_cfg = *cfg;
    if (g_lock) xSemaphoreGive(g_lock);
}

void car_spin_pair(uint8_t pair, bool forward) {
    if (pair > 3) return;
    motor_outputs_t out = { .duty = {0} };
    const uint16_t duty = 1600;  // ~40% for identification
    out.duty[pair * 2]     = forward ? duty : 0;
    out.duty[pair * 2 + 1] = forward ? 0 : duty;
    if (g_lock && xSemaphoreTake(g_lock, pdMS_TO_TICKS(200)) != pdTRUE) return;
    motors_apply(&out);
    if (g_lock) xSemaphoreGive(g_lock);
}

void car_init(void) {
    g_lock = xSemaphoreCreateMutex();
    // A missing mutex would mean unsynchronized I2C from console + WS tasks; fail visibly.
    ESP_ERROR_CHECK(g_lock ? ESP_OK : ESP_ERR_NO_MEM);

    motors_config_t loaded;
    if (calibration_load(&loaded)) {
        g_cfg = loaded;
    } else {
        ESP_LOGW(TAG, "no NVS calibration — using default mapping");
    }

    car_stop();  // safety stop
}
