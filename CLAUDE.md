# ESP32-P4-Car

4-wheel RC car: XIAO ESP32-C6 → PCA9685 (I2C PWM) → 4× BTS7960 H-bridge → motors.

## Hardware

| Component | Details |
|---|---|
| MCU | Seeed Studio XIAO ESP32-C6 (native USB, no UART bridge) |
| PWM driver | PCA9685 (Osoyoo board, I2C addr `0x40`) |
| Motor driver | 4× BTS7960 (full H-bridge, ~43A) |
| Framework | ESP-IDF 5.4 at `~/esp/esp-idf` |

### Pin mapping (XIAO ESP32-C6 → PCA9685)
- D4 (GPIO22) = SDA
- D5 (GPIO23) = SCL
- 3V3 → VCC (logic)
- VBUS (5V from USB) → V+ terminal (powers BTS7960 R_EN/L_EN through red pins of channel headers)
- GND → GND (common with battery and BTS7960)

### Motor channel mapping (sequential, stride 2)
| Motor | CH_A (forward) | CH_B (reverse) |
|---|---|---|
| 1 | CH0 | CH1 |
| 2 | CH2 | CH3 |
| 3 | CH4 | CH5 |
| 4 | CH6 | CH7 |

- Forward: CH_A=HIGH, CH_B=LOW
- Reverse: CH_A=LOW, CH_B=HIGH
- **Never both HIGH** (H-bridge shoot-through on BTS7960). The firmware validates and rejects this.

## Code structure (`main/main.c`)

- `pca9685_init(freq_hz)` — sleep→prescale→wake→restart sequence, errors checked with `ESP_RETURN_ON_ERROR`.
- `pca9685_set_pwm(channel, duty)` — 12-bit duty 0..4095; uses full-ON/full-OFF bits at extremes.
- `apply_motors("AB CD EF GH")` — parses 11-char command, validates format and shoot-through, writes 8 channels. Returns `esp_err_t`.
- `console_init()` — installs USB Serial JTAG driver. **No UART VFS.**
- `read_line()` — blocking `usb_serial_jtag_read_bytes()` (avoids fgets/VFS non-blocking spam).
- `app_main()` — init I2C → init PCA9685 → safety stop (`00 00 00 00`) → console init → REPL.

### sdkconfig.defaults
```
CONFIG_IDF_TARGET="esp32c6"
CONFIG_ESP_CONSOLE_USB_SERIAL_JTAG=y
CONFIG_ESP_CONSOLE_UART_DEFAULT=n
```
Critical: console MUST be USB Serial JTAG (XIAO has no USB-UART bridge — UART0 pins go to D6/D7 only).

## Build & flash

System python is 3.14 but IDF 5.4 venv was built with 3.13 → `export.sh` fails. Workaround:

```bash
mkdir -p /tmp/py313bin && ln -sf /opt/homebrew/bin/python3.13 /tmp/py313bin/python3
export PATH=/tmp/py313bin:$PATH
source ~/esp/esp-idf/export.sh
idf.py build
idf.py -p /dev/cu.usbmodem* flash
```

USB port number changes after each reset (`usbmodem1101`, `usbmodem2101`, ...). Always re-check with `ls /dev/cu.usbmodem*`.

## Claude↔board bridge

For interactive control from this chat without `idf.py monitor` blocking the terminal:

```bash
~/.espressif/python_env/idf5.4_py3.13_env/bin/python /tmp/esp_bridge.py /dev/cu.usbmodem* > /tmp/esp_bridge.log 2>&1 &
```

The bridge (`/tmp/esp_bridge.py`):
- Opens serial port at 115200
- Reads commands from FIFO `/tmp/esp_in` (one line per `echo "..." > /tmp/esp_in`)
- Appends serial RX to `/tmp/esp_out.log`
- Sends `\r` after each command (matches firmware's `ESP_LINE_ENDINGS_CR` expectation)

Send command:
```bash
echo "10 10 10 10" > /tmp/esp_in
sleep 1 && tail -c 500 /tmp/esp_out.log
```

If port disappears (`Errno 6: Device not configured`), the user probably unplugged USB — restart bridge.

## Command format

11-char strict format: `AB CD EF GH` (spaces mandatory).

| Command | Meaning |
|---|---|
| `00 00 00 00` | All stop |
| `10 10 10 10` | All forward |
| `01 01 01 01` | All reverse |
| `10 01 10 01` | Diagonal mix (tank turn) |
| `11 ...` | Rejected — shoot-through guard |
| `10101010` | Rejected — missing spaces |

## Gotchas (learned the hard way)

1. **XIAO C6 has no USB-UART bridge.** UART0 is physical pins only. Console MUST be USB Serial JTAG.
2. **`fgets` on USB JTAG VFS returns NULL non-blocking** → infinite prompt spam. Use `usb_serial_jtag_read_bytes()` directly.
3. **BTS7960 needs R_EN + L_EN tied HIGH (5V).** Without it, the H-bridge is electrically disconnected — PWM signal exists but motors stay silent. Easiest path: feed XIAO VBUS into PCA9685's V+ terminal, take red pins from any channel header.
4. **All 4 GNDs must be common**: XIAO, PCA9685, BTS7960, and motor battery negative.
5. **`esp_vfs_dev.h` is deprecated in IDF 5.4** — use `driver/uart_vfs.h` if you ever need UART VFS (currently we don't).
6. **First motor power-on can brown out** if battery is weak — pusk current is 5-10× nominal. Stagger starts or use bigger caps if it happens.
7. **`pca9685_init` previously returned `ESP_OK` even on I2C failure** — now wrapped in `ESP_RETURN_ON_ERROR` so a missing PCA9685 will cause `app_main` to crash visibly via `ESP_ERROR_CHECK`.

## Future ideas (not yet implemented)

- Variable speed (duty 0..4095 instead of 0/4095 binary)
- Smooth ramp-up to reduce brownout risk
- WiFi/BLE control instead of console
- Per-motor command (`m1 fwd 50%`) instead of bitmap
- Watchdog: auto-stop if no command for N seconds
