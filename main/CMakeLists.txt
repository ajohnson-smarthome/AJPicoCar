idf_component_register(
    SRCS "main.c" "pca9685.c" "mixer.c" "motors.c" "car.c" "wifi_ap.c"
    INCLUDE_DIRS "."
    REQUIRES esp_wifi esp_netif esp_event nvs_flash
    PRIV_REQUIRES esp_driver_usb_serial_jtag esp_driver_i2c
)
