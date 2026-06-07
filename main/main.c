#include <stdio.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/i2c_master.h"
#include "driver/usb_serial_jtag.h"
#include "esp_log.h"
#include "esp_check.h"

static const char *TAG = "motor";

// XIAO ESP32-C6 I2C pins (D4=GPIO22, D5=GPIO23)
#define I2C_SDA_PIN         22
#define I2C_SCL_PIN         23
#define I2C_FREQ_HZ         400000

// PCA9685
#define PCA9685_ADDR        0x40
#define PCA9685_MODE1       0x00
#define PCA9685_PRESCALE    0xFE
#define PCA9685_LED0_ON_L   0x06

static i2c_master_bus_handle_t bus_handle;
static i2c_master_dev_handle_t pca9685_handle;

static esp_err_t pca9685_write_reg(uint8_t reg, uint8_t value)
{
    uint8_t buf[2] = {reg, value};
    return i2c_master_transmit(pca9685_handle, buf, sizeof(buf), -1);
}

static esp_err_t pca9685_read_reg(uint8_t reg, uint8_t *value)
{
    return i2c_master_transmit_receive(pca9685_handle, &reg, 1, value, 1, -1);
}

// MODE1 register bits (PCA9685 datasheet, Table 5).
#define PCA9685_MODE1_RESTART   0x80
#define PCA9685_MODE1_AI        0x20  // Register auto-increment
#define PCA9685_MODE1_SLEEP     0x10

static esp_err_t pca9685_init(uint16_t freq_hz)
{
    uint8_t prescale = (uint8_t)((25000000.0 / (4096.0 * freq_hz)) - 0.5);
    ESP_LOGI(TAG, "PCA9685 prescale = %d for %d Hz", prescale, freq_hz);

    ESP_RETURN_ON_ERROR(pca9685_write_reg(PCA9685_MODE1, PCA9685_MODE1_SLEEP), TAG, "sleep failed");
    vTaskDelay(pdMS_TO_TICKS(5));
    ESP_RETURN_ON_ERROR(pca9685_write_reg(PCA9685_PRESCALE, prescale), TAG, "prescale failed");
    ESP_RETURN_ON_ERROR(pca9685_write_reg(PCA9685_MODE1, PCA9685_MODE1_AI), TAG, "wake failed");
    vTaskDelay(pdMS_TO_TICKS(5));

    uint8_t mode1;
    ESP_RETURN_ON_ERROR(pca9685_read_reg(PCA9685_MODE1, &mode1), TAG, "mode1 read failed");
    ESP_RETURN_ON_ERROR(pca9685_write_reg(PCA9685_MODE1, mode1 | PCA9685_MODE1_RESTART), TAG, "restart failed");

    ESP_LOGI(TAG, "PCA9685 initialized");
    return ESP_OK;
}

static esp_err_t pca9685_set_pwm(uint8_t channel, uint16_t duty)
{
    uint8_t base_reg = PCA9685_LED0_ON_L + 4 * channel;
    uint16_t on = 0;
    uint16_t off = duty;

    if (duty == 0) {
        on = 0;
        off = 0x1000;
    } else if (duty >= 4095) {
        on = 0x1000;
        off = 0;
    }

    uint8_t buf[5] = {
        base_reg,
        on & 0xFF,
        (on >> 8) & 0x1F,
        off & 0xFF,
        (off >> 8) & 0x1F,
    };

    return i2c_master_transmit(pca9685_handle, buf, sizeof(buf), -1);
}

static esp_err_t i2c_init(void)
{
    i2c_master_bus_config_t bus_cfg = {
        .i2c_port = I2C_NUM_0,
        .sda_io_num = I2C_SDA_PIN,
        .scl_io_num = I2C_SCL_PIN,
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .glitch_ignore_cnt = 7,
        .flags.enable_internal_pullup = true,
    };
    ESP_RETURN_ON_ERROR(i2c_new_master_bus(&bus_cfg, &bus_handle), TAG, "I2C bus init failed");

    i2c_device_config_t dev_cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = PCA9685_ADDR,
        .scl_speed_hz = I2C_FREQ_HZ,
    };
    ESP_RETURN_ON_ERROR(i2c_master_bus_add_device(bus_handle, &dev_cfg, &pca9685_handle), TAG, "PCA9685 add failed");

    return ESP_OK;
}

// Input format: "AB CD EF GH" — 4 motor pairs separated by single spaces.
// Each pair: A = CH_A state ('0'/'1'), B = CH_B state ('0'/'1').
// Motor N uses channels (N*2) and (N*2+1): M1=CH0/CH1, M2=CH2/CH3, M3=CH4/CH5, M4=CH6/CH7.
// Forbidden: both channels of one motor = '1' (shoot-through on BTS7960 H-bridge).
static esp_err_t apply_motors(const char *input)
{
    const size_t expected_len = 11; // 2+1+2+1+2+1+2
    if (strlen(input) != expected_len) {
        ESP_LOGE(TAG, "Bad input length: expected %d chars in format 'AB CD EF GH', got %d",
                 (int)expected_len, (int)strlen(input));
        return ESP_ERR_INVALID_ARG;
    }

    const int pair_offsets[4] = {0, 3, 6, 9};
    const int space_positions[3] = {2, 5, 8};

    for (int i = 0; i < 3; i++) {
        if (input[space_positions[i]] != ' ') {
            ESP_LOGE(TAG, "Bad format: expected space at position %d, got '%c'",
                     space_positions[i], input[space_positions[i]]);
            return ESP_ERR_INVALID_ARG;
        }
    }

    for (int m = 0; m < 4; m++) {
        char a = input[pair_offsets[m]];
        char b = input[pair_offsets[m] + 1];
        if ((a != '0' && a != '1') || (b != '0' && b != '1')) {
            ESP_LOGE(TAG, "Motor %d: expected '0'/'1' chars, got '%c%c'", m + 1, a, b);
            return ESP_ERR_INVALID_ARG;
        }
        if (a == '1' && b == '1') {
            ESP_LOGE(TAG, "Motor %d: both channels ON is forbidden (H-bridge shoot-through)", m + 1);
            return ESP_ERR_INVALID_ARG;
        }
    }

    ESP_LOGI(TAG, "Setting motors: %s", input);
    for (int m = 0; m < 4; m++) {
        char a = input[pair_offsets[m]];
        char b = input[pair_offsets[m] + 1];
        esp_err_t e1 = pca9685_set_pwm(m * 2,     (a == '1') ? 4095 : 0);
        esp_err_t e2 = pca9685_set_pwm(m * 2 + 1, (b == '1') ? 4095 : 0);
        if (e1 != ESP_OK || e2 != ESP_OK) {
            ESP_LOGE(TAG, "Motor %d I2C write failed: ch%d=%s ch%d=%s",
                     m + 1, m * 2, esp_err_to_name(e1), m * 2 + 1, esp_err_to_name(e2));
        }
    }

    printf("Motor:  1   2   3   4\n");
    printf("       %c%c  %c%c  %c%c  %c%c\n",
           input[0], input[1],
           input[3], input[4],
           input[6], input[7],
           input[9], input[10]);
    return ESP_OK;
}

static void console_init(void)
{
    usb_serial_jtag_driver_config_t cfg = USB_SERIAL_JTAG_DRIVER_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(usb_serial_jtag_driver_install(&cfg));
}

// Blocking read of one CR/LF-terminated line from USB Serial JTAG.
// Returns line length (without terminator) or -1 on overflow.
static int read_line(char *buf, size_t maxlen)
{
    size_t pos = 0;
    while (pos < maxlen - 1) {
        uint8_t c;
        int n = usb_serial_jtag_read_bytes(&c, 1, portMAX_DELAY);
        if (n <= 0) continue;
        if (c == '\r' || c == '\n') {
            buf[pos] = '\0';
            return (int)pos;
        }
        buf[pos++] = (char)c;
    }
    buf[pos] = '\0';
    return -1; // overflow
}

void app_main(void)
{
    ESP_ERROR_CHECK(i2c_init());
    ESP_ERROR_CHECK(pca9685_init(1000));

    // Safety: stop all motors immediately after init.
    apply_motors("00 00 00 00");

    console_init();

    ESP_LOGI(TAG, "Ready. Enter command in format 'AB CD EF GH' (e.g. '10 10 10 10'):");

    char line[32];
    while (1) {
        printf("> ");
        fflush(stdout);
        int len = read_line(line, sizeof(line));
        if (len <= 0) {
            if (len < 0) ESP_LOGE(TAG, "input overflow");
            continue;
        }
        apply_motors(line);
    }
}
