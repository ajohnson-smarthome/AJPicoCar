# JSON Everywhere — transport + storage

**Date:** 2026-06-17
**Branch:** new feature branch off `main`
**Scope:** firmware (C) + iOS (Swift) + mock. All app↔car data exchange and all on-car persistence move to JSON.

## Goal

Make **every** data channel between the app and the car — and the car's own persistence — use JSON:
- **Config REST POST bodies** (`/wheel`, `/dims`, `/calib/save`, `/ramp`, `/trim`, `/recover`) become JSON objects (GET responses are already JSON).
- **`/ws` both directions**: drive/trick control frames (app→car) become `{"t":..,"y":..}`; telemetry (car→app) is already JSON.
- **NVS storage**: each config domain persists as a single JSON string instead of typed keys / a blob.

## Parsing tiers (the key architectural decision)

JSON is not free on an MCU, so three tiers by hot/cold path:

1. **`cJSON`** (bundled ESP-IDF component `json`, added to `main/CMakeLists.txt` `REQUIRES`) — used ONLY on the
   **cold** config POST handlers (rare, user-initiated) and the boot-time NVS parse. Heap alloc per parse is fine here.
2. **Zero-alloc hand parser** — the **hot** `/ws` control frame (drive + tricks, 10 Hz). `control_proto` gains a pure
   `control_parse_json()` that scans the fixed shape `{"t":<num>,"y":<num>}` without malloc, rejects NaN/inf, and
   stays host-testable. NO cJSON on the hot path (no per-frame heap churn / jitter / fragmentation in the control path).
3. **`snprintf`** — building JSON for GET responses and 5 Hz telemetry. Already the case, already valid JSON on the
   wire, zero alloc. Unchanged.

## Transport: `/ws` (both directions)

- **app→car (drive + tricks):** the frame becomes `{"t":0.5,"y":0}` (2-dp floats) instead of `"0.5,0"`. Tricks ride
  the same control frame, so they convert automatically. iOS `ControlModel.frame(t:y:)` (pure, host-tested) emits the
  JSON object; `ws_control` parses it via the new `control_parse_json`.
- **car→app (telemetry):** already JSON (`telemetry_fields`/`telemetry_json` → `snprintf "{...}"`, 5 Hz). No change;
  the app already parses it.
- **JSON-only, no back-compat:** the old `"t,y"` format is dropped. App and firmware ship together (the launch gate
  force-updates the board to the app's bundled build), so there is no mixed-version window to support.
- **Out of scope:** the USB-console `mix <t> <y>` REPL is local debug, not a socket — it stays plain text.

## Config REST: POST bodies → JSON (GET already JSON)

| Endpoint | New POST body | Notes |
|---|---|---|
| `POST /wheel` | `{"diameter_mm":65,"ppr":11,"gear_x100":2100,"quad":4}` | clamp/validate as today |
| `POST /dims` | `{"track_mm":130,"wheelbase_mm":210}` | |
| `POST /calib/save` | `{"wheels":[{"pair":0,"sign":1},{"pair":1,"sign":-1},{"pair":2,"sign":1},{"pair":3,"sign":-1}]}` | array order FL,FR,RL,RR (4 entries); `deadzone` stays the firmware default 0.05 |
| `POST /ramp` | `{"ramp_ms":300}` | 0..2000 |
| `POST /trim` | `{"trim_pct":10}` | −30..30 |
| `POST /recover` | `{"enabled":true,"window_ms":3000}` | window 1000..10000 |

Each POST handler: `cJSON_Parse` → null-check → extract each field with type/range validation → on any failure
`HTTPD_400` with a short message → `cJSON_Delete`. GET handlers keep their hand-built `snprintf` JSON.

## Storage: one JSON string per domain in NVS

Each owning module centralizes load+save as JSON (parse with cJSON, serialize with `snprintf`):
- `wheel.c`, `dims.c`, `ramp.c`, `trim` (its store), `recovery.c`, `calibration.c` each get a `*_save()` that
  serializes the current struct to a JSON string and `nvs_set_str` under one key (e.g. `wheel`/`dims`/`ramp`/`trim`/
  `recover`/`calib`); `*_init()`/`*_load()` does `nvs_get_str` → `cJSON_Parse` → fill struct, falling back to the
  compiled defaults if the key is absent or the JSON is malformed/out-of-range.
- The API POST handlers call `*_set()` then `*_save()` (the inline `nvs_set_u16/i8/blob` writes are removed — storage
  lives in the module, the API just validates + applies + persists).
- Calibration moves from an opaque blob to a JSON string; `calibration_valid` still validates the parsed struct.

**Upgrade behavior (accepted):** the new JSON string keys do not match the old typed keys (`wheel_d`, `track_mm`,
the `calib` blob, `ramp_ms`, …), so after flashing this firmware the old values are not read → **every domain
resets to its compiled default.** Calibration is mandatory, so its wizard re-runs; wheel/dims/ramp/trim/recover
return to defaults. No one-time migration of the old keys (deliberate — the board is re-flashed anyway).

## iOS

- **Clients** (`WheelClient`, `DimsClient`, `RampClient`, `TrimClient`, `RecoverClient`, `CalibClient`) build JSON
  POST bodies via `JSONSerialization` (GET parsing already uses `JSONSerialization`, unchanged).
- **`ControlModel.frame(t:y:)`** returns `{"t":%.2f,"y":%.2f}` (clamped) instead of `"%.2f,%.2f"` — pure, host-tested.
  `CarConnection` (the 10 Hz `/ws` sender) and the trick streamer in `DriveView` use it unchanged.
- Telemetry parsing in the app is already JSON — no change.

## Mock car

`tools/mock_car/mock_car.py` — `/ws` parses `{"t","y"}` frames; all config POSTs accept the JSON bodies above and
store JSON; GET responses already return JSON. Keeps the simulator dev loop working.

## Testing

- **Firmware pure:** `control_parse_json` host-tested in `test/` (valid frame, whitespace, NaN/inf rejected, malformed
  → −1) — mirrors/replaces the old `control_parse_ty` tests. `calibration_valid` unchanged (still pure).
- **iOS pure:** `ControlModel.frame` host-tested (emits the JSON object, clamps, 2-dp).
- **Round-trip:** for each config domain, a firmware test (or a documented manual check) that a JSON body →
  struct → serialized JSON round-trips through `*_set`/`*_save`/`*_load` (where a host harness exists).
- **Build gates:** `idf.py build` (firmware compiles with cJSON), `xcodebuild` (iOS), `cd test && make run`
  (host modules), mock smoke (`curl` a JSON POST, drive a JSON `/ws` frame).

## Out of scope

- Backward compatibility with the old wire formats.
- Migrating existing NVS values across the upgrade.
- The USB-console `mix` command.
- Rebuilding GET/telemetry responses via cJSON (they are already JSON via `snprintf`).
