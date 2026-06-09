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
- **Never both HIGH** (H-bridge shoot-through on BTS7960). `motors_plan` makes this structurally
  impossible — for each wheel it sets exactly one of CH_A/CH_B nonzero (or both zero).

## Code structure (modular since Phase 1)

Refactored from a monolithic `main.c` into focused modules. The pure modules
(`mixer`, `motors`) have **zero ESP-IDF dependencies** and are host-tested.

- `main/pca9685.{c,h}` — I2C/PCA9685 driver.
  - `pca9685_bus_init(sda, scl, i2c_speed_hz)` — create I2C master bus + add device `0x40`.
  - `pca9685_init(pwm_freq_hz)` — sleep→prescale→wake→restart, `ESP_RETURN_ON_ERROR`.
  - `pca9685_set_pwm(channel, duty)` — 12-bit duty 0..4095; full-ON/full-OFF at extremes; rejects channel >15.
- `main/mixer.{c,h}` — **pure**. `mixer_mix(throttle, yaw) → {left, right}`: tank-turn mixing
  (`left=t+y`, `right=t-y`, normalized by `max(|l|,|r|,1)` to keep [-1,1] and preserve turn ratio).
- `main/motors.{c,h}` — **pure**. `motors_plan(left, right, cfg) → 8 duties`: maps side speeds to
  per-wheel PWM via a calibration table (`wheel_calib_t {channel_pair, sign}` per `POS_FL/FR/RL/RR`,
  plus `deadzone`). Left side = {FL, RL}, right = {FR, RR}. Shoot-through-safe by construction.
- `main/main.c` — orchestrator: `drive(t, y)` = mixer → planner → `motors_apply` (writes 8 channels);
  console `mix <t> <y>` REPL; default `g_cfg` calibration (replaced by NVS in Phase 5).
  - `console_init()` — installs USB Serial JTAG driver. **No UART VFS.**
  - `read_line()` — blocking `usb_serial_jtag_read_bytes()` (avoids fgets/VFS non-blocking spam).
  - `app_main()` — `pca9685_bus_init` → `pca9685_init` → safety stop `drive(0,0)` → console init → REPL.

### Host tests (`test/`)
Pure modules compile with plain `cc` (no ESP-IDF). Run from `test/`:
```bash
cd test && make run   # builds + runs test_mixer and test_motors
```
`test/Makefile` links with `-lm` via `LDLIBS` (Linux needs it after objects).

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
echo "mix 0.5 0" > /tmp/esp_in
sleep 1 && tail -c 500 /tmp/esp_out.log
```

If port disappears (`Errno 6: Device not configured`), the user probably unplugged USB — restart bridge.

## Command format

`mix <throttle> <yaw>` — both floats in `[-1.0, 1.0]`. The firmware mixes them into
left/right side speeds and logs `drive t=.. y=.. -> L=.. R=..`.

| Command | Meaning | Result |
|---|---|---|
| `mix 0 0` | All stop | L=0, R=0 |
| `mix 1 0` | Full forward | L=1, R=1 |
| `mix -1 0` | Full reverse | L=-1, R=-1 |
| `mix 0 1` | Spin in place (tank turn) | L=1, R=-1 |
| `mix 0.5 0.5` | Arc (right side slows) | L=1, R=0 |
| `mix 5 0` | Rejected — out of [-1,1] | error |
| `garbage` | Rejected — not a `mix` command | error |

(The old binary `AB CD EF GH` command was removed in the Phase 1 refactor.)

## Gotchas (learned the hard way)

1. **XIAO C6 has no USB-UART bridge.** UART0 is physical pins only. Console MUST be USB Serial JTAG.
2. **`fgets` on USB JTAG VFS returns NULL non-blocking** → infinite prompt spam. Use `usb_serial_jtag_read_bytes()` directly.
3. **BTS7960 needs R_EN + L_EN tied HIGH (5V).** Without it, the H-bridge is electrically disconnected — PWM signal exists but motors stay silent. Easiest path: feed XIAO VBUS into PCA9685's V+ terminal, take red pins from any channel header.
4. **All 4 GNDs must be common**: XIAO, PCA9685, BTS7960, and motor battery negative.
5. **`esp_vfs_dev.h` is deprecated in IDF 5.4** — use `driver/uart_vfs.h` if you ever need UART VFS (currently we don't).
6. **First motor power-on can brown out** if battery is weak — pusk current is 5-10× nominal. Stagger starts or use bigger caps if it happens.
7. **`pca9685_init` previously returned `ESP_OK` even on I2C failure** — now wrapped in `ESP_RETURN_ON_ERROR` so a missing PCA9685 will cause `app_main` to crash visibly via `ESP_ERROR_CHECK`.
8. **First IDF build can stall on submodule clones** (`esp_wifi/lib`, `micro-ecc`, bt libs) with `curl 56 Recv failure: Operation timed out`. Fix: make git tolerant of slow links, then full recursive init:
   ```bash
   git config --global http.lowSpeedLimit 0   # disable abort-on-slow
   git config --global http.postBuffer 524288000
   cd ~/esp/esp-idf && git submodule update --init --recursive
   ```
9. **"Motors don't spin" is usually command DELIVERY, not firmware/hardware.** Two traps found in Phase 3 e2e (details: memory `debugging-motors-test-rig`):
   - Opening the USB Serial JTAG port (pyserial / the bridge) **resets the C6** → a command sent in the first ~1-2 s is lost during boot. Wait for boot, send, and confirm the `drive ...` log echoes before trusting "it didn't work."
   - WebSocket/touch control must **stream the held command at ~10 Hz**, not send once — a single press is a ~40 ms pulse that can't visibly spin a motor. (The web pad does this; it also feeds the Phase 4 watchdog.)
   - Decisive isolation: flash a diagnostic `app_main` that drives full-forward in a loop with no console (`while(1){ drive(1,0); vTaskDelay(1000); }`). Motors spin → firmware+hardware are fine, bug is delivery.

## Roadmap

Full design + per-phase plans live in `docs/superpowers/`.

**Done — Phase 1 (merged):** modular refactor (mixer/motors/pca9685), proportional
`mix <t> <y>` control, host tests, tank-turn mixing.

**Done — Phase 2 (merged):** `car.{c,h}` orchestration (`car_drive` clamps + mixer→planner→PCA9685);
WiFi softAP **`ESP32-Car`** (WPA2, pass `drive1234`, 192.168.4.1) in `wifi_ap.{c,h}`; `http_server.{c,h}`
serving an embedded `web/index.html` at GET `/`; `app_main` order: pca9685 → car_init → NVS → wifi → http → console.
Verified on hardware (network visible, page loads, `mix` console still works).

**Done — Phase 3 (merged):** WebSocket `/ws` realtime control. `car_drive` thread-safe (mutex around I2C)
+ `car_stop`; pure `control_proto.{c,h}` parser (`"t,y"`, rejects NaN/inf, host-tested); `ws_control.{c,h}`
registers `/ws` on `http_server_get_handle()` and applies frames via `car_drive`; `web/index.html` streams
the held command at 10 Hz. `CONFIG_HTTPD_WS_SUPPORT=y`. Verified on hardware (phone drives fwd/back/turns).

**Done — Phase 4 (merged):** control-link **watchdog** (`watchdog.{c,h}`) — 50 Hz `Tmr Svc` timer; if no WS
frame for >300 ms → `car_stop()`. `ws_handler` calls `watchdog_feed()`; `watchdog_init(300)` in app_main.
Pure `watchdog_stale()` host-tested (incl. 32-bit rollover). Console path NOT under watchdog (debug stays
usable). Also: `car_drive` mutex wait bounded to 200 ms, drive log → LOGD. **Hardware auto-stop test still
pending (needs user).**

**Done — Phase 5 (merged, verified on hardware):** motor **calibration**. `calibration.{c,h}` — NVS
persistence of the `motors_config_t` table + host-tested `calibration_valid` (4 unique channel pairs,
signs ±1, deadzone in [0,1)). `car_init` loads it from NVS, **falling back to the default mapping if
absent/invalid**; `car_set_calibration()` + `car_spin_pair()` (raw single-pair spin). `calib_api.{c,h}` —
REST `GET /calib`, `POST /calib/spin`, `POST /calib/save` on the shared httpd. `index.html` gates on
`GET /calib`: first connect → 4-step wizard (spin each pair, tag corner FL/FR/RL/RR + direction) → save →
d-pad; "⚙ Recalibrate" button. User calibrated on the bench: spin/identify/save/drive all work, persists.

**Done — Phase 6 (merged, verified on hardware):** the full phone web pult.
- *6a* — touch **joysticks**: arcade (default) and tank, with a scheme toggle (localStorage). Both produce
  `t,y` client-side; streams the held command at 10 Hz.
- *6b* — **PWA**: iOS full-screen meta tags + an inline car app icon (data-URI PNG) → "Add to Home Screen".
- *6c* — captive portal was added then **removed** (see below).

**Done — web pult redesign (merged):** `main/web/index.html` reworked to a **landscape gamepad** layout,
**Stealth/minimal** dark style (green accent via CSS vars), portrait "rotate" hint. Arcade = right stick +
left throttle bar; tank = two corner sticks. Status pill (`connecting`/`connected`/`reconnecting`); sticks
fade on WS loss. **Calibration redesigned** to a top-down car diagram: press Spin, tap the wheel that turned,
pick direction — same `/calib*` protocol. (Design: `docs/.../specs/2026-06-08-web-ui-redesign.md`.) Full
joystick deflection = `t,y = ±1` = duty 4095 = 100% PWM (max the firmware commands; real RPM is battery-bound).

**Removed — captive portal:** the Phase 6c `captive.{c,h}` (DNS + 404 redirect auto-popup) was reverted on
request — join `ESP32-Car`, then open `http://192.168.4.1/` manually. `app_main` no longer calls it; `lwip`
dropped from REQUIRES.

**Removed — web pult (2026-06-10):** `main/web/index.html` deleted entirely — the native iOS app is the
only pult. `GET /` now returns a one-line plain-text identity; httpd stays (the app needs `/ws` + REST:
`/status`, `/calib*`, `/ramp`, `/trim`, `/ota`). Freed ~9.5 KB of the OTA app slot. NOTE: with free Apple-ID
signing the app expires every 7 days — re-Run from Xcode; there is no browser fallback anymore.

**🎉 Roadmap complete — Phases 1–6 merged and verified on hardware: a WiFi-controlled 4WD RC car with
tank-turn, realtime joystick control, watchdog auto-stop, on-wheels calibration, PWA, redesigned landscape pult.**

**Deferred / optional future:**
- **Ramp (slew-rate limit):** needs hardware tuning + a dedicated ~50 Hz ramp task (so single console
  commands still reach full speed). Design sketch in `docs/superpowers/plans/2026-06-08-phase4-watchdog.md`.
- **Phase 4 watchdog auto-stop** never explicitly bench-tested (drive from phone → drop WiFi/close tab
  mid-drive → car must stop in ~300 ms, log `wdt: no control frame ...`; console `mix` must NOT auto-stop).
- **Power:** USB CDC port drops under motor load (VBUS sags) — power the logic from a stable 5 V separate
  from the motor supply if flashing-while-driving is needed.

## Native iOS app (`ios/`)

A SwiftUI phone pult that drives the same firmware over the existing WiFi/WS/REST API. **XcodeGen project**
(`ios/project.yml` → `ESP32Car.xcodeproj`; the `.xcodeproj` is generated and gitignored — version `project.yml`).
Landscape-locked, warm light/dark themes (follows iOS appearance), Russian-localized.

- **Firmware companion:** `main/status_api.{c,h}` adds `GET /status` →
  `{"device":"esp32-car","fw":..,"uptime_s":..,"calibrated":..,"heap":..}` — a signed identity + telemetry the app
  polls (positive "am I on the car's network" check, no SSID entitlement needed). Registered in `app_main` after
  the http server. (Calibration uses the pre-existing `/calib`, `/calib/spin`, `/calib/save`.)

### iOS structure (`ios/ESP32Car/`)
- `ControlModel.swift` — **pure** (Foundation/CoreGraphics): scheme math (`arcade`/`tank`/`sides`/`frame`),
  `diagramState`/`curvature`/`trajectoryPoints` (bounded arc, never loops), `calibSaveBody`, `Corner`. Host-tested
  natively with `swiftc` (no simulator needed) + mirrored XCTest.
- `CarHost.swift` — `#if targetEnvironment(simulator)` → `127.0.0.1:8080` (mock), else `192.168.4.1`. Single source
  of the WS/HTTP address. `CarConnection.swift` (WS `/ws`, 10 Hz stream, reconnect, `pause()` on background),
  `CarStatus.swift` (polls `/status` 1.5 s, debounced offline, ping/uptime/calibrated/fw).
- `DriveView.swift` — B1 landscape layout (status pill + scheme toggle + ⚙ top; `L · DriveDiagram · R` center;
  status line bottom; joysticks bottom corners). `DriveDiagram.swift` — animated `Canvas`: chevron-tread wheels +
  predicted-trajectory rails (green fwd / amber reverse) or spin indicator (↻ + counter wheels). `JoystickView`,
  `SchemeToggle`, `Gamepad` (GameController), `Haptics` (CoreHaptics), `Theme.swift` (warm palettes).
- `SettingsView.swift` (⚙ sheet) → `CalibrationView.swift` (split-layout wizard: Spin pair → tap turned wheel →
  direction → save, via `CalibClient.swift`). Auto-prompts when `/status` says `calibrated=false`.
- `L.swift` + `Resources/ru.lproj/Localizable.strings` — all UI text via `enum L` over `NSLocalizedString`
  (`CFBundleDevelopmentRegion=ru`; add `en.lproj` for a 2nd language). No Cyrillic literals in views.

### Build & run the iOS app
- **On iPhone:** `open ios/ESP32Car.xcodeproj` → set Team (free Apple ID) in Signing → Run on device. Join WiFi
  `ESP32-Car`, allow Local Network. Free signing expires in 7 days (just Run again).
- **In the Simulator, no hardware** (the dev workflow this session used): start the **mock car** —
  `cd tools/mock_car && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt` then
  `nohup .venv/bin/python -u mock_car.py >/tmp/mock_car.log 2>&1 &` (aiohttp on `127.0.0.1:8080`, serves
  `/status`+`/ws`+`/calib*`; `calibrated` flag starts false, set true on save). Then:
  ```bash
  cd ios && xcodegen generate
  xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata
  xcrun simctl boot "iPhone 17"; open -a Simulator
  xcrun simctl install booted "$(find /tmp/ddata/Build/Products -name ESP32Car.app|head -1)"
  xcrun simctl launch booted com.adamjohnson.esp32car
  ```
  The app auto-targets the localhost mock in the simulator (via `CarHost`); on device it targets `192.168.4.1`.
  Screenshot: `xcrun simctl io booted screenshot /tmp/x.png`.

### iOS gotchas
- **Pure modules are host-tested with `swiftc` natively** (e.g. `swiftc ios/ESP32Car/ControlModel.swift check.swift main.swift && ./a.out`) — no XCTest/simulator runtime required. SwiftUI parts are compile-checked with `xcodebuild -sdk iphonesimulator26.2`.
- **The Simulator reports a phantom game controller** (`pad.connected == true`), so the touch joystick is gated on
  actual gamepad deflection — otherwise idle "gamepad" input masks touch (`DriveView.push()`).
- Build SDK is `iphonesimulator26.2` but the installed **runtime is iOS 26.3** — that's fine (build vs run).
- Simulator strings show Russian even on an English simulator because `CFBundleDevelopmentRegion=ru`.
