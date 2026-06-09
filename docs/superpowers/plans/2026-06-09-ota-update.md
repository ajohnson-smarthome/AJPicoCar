# OTA-обновление прошивки через апп — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Обновлять прошивку «по воздуху» из iOS-аппа: апп берёт `.bin` из GitHub Releases и заливает на машинку (`POST /ota`), которая пишет в свободный OTA-раздел, валидирует, перезагружается, при сбое откатывается.

**Architecture:** Прошивка — dual-OTA разметка + `/ota` (esp_ota) + версия из app-desc + rollback. Апп — `UpdateClient` (GitHub latest → скачать → залить с прогрессом) + `FirmwareView` в настройках. Mock получает `/ota` для теста в симуляторе.

**Tech Stack:** ESP-IDF 5.4 (esp_ota_ops, partition table), Swift 6 / SwiftUI (async URLSession), Python/aiohttp (mock). Ветка `ota-update`. Репо релизов: `ajohnson-smarthome/AJPicoCar` (public).

---

## File Structure

| Файл | Изменение |
|---|---|
| `sdkconfig.defaults` | + dual-OTA partition table, rollback, 4MB flash |
| `main/status_api.c` | `fw` = `esp_app_get_description()->version` |
| `main/ota_api.{c,h}` *(new)* | `POST /ota` (esp_ota begin/write/end/set_boot/restart) |
| `main/main.c` | `ota_api_start()` + rollback mark-valid после старта сервисов |
| `main/CMakeLists.txt` | + `ota_api.c` + `app_update` в REQUIRES |
| `tools/mock_car/mock_car.py` | + `POST /ota` (лог, ok) |
| `ios/ESP32Car/UpdateClient.swift` *(new)* | GitHub latest + download + upload(progress) |
| `ios/ESP32Car/FirmwareView.swift` *(new)* | экран обновления (шаги/прогресс) |
| `ios/ESP32Car/SettingsView.swift` | + строка «Прошивка» → `FirmwareView` |
| `ios/ESP32Car/L.swift` + `ru.lproj/Localizable.strings` | + ключи `firmware.*` |

---

## Task 1: Прошивка — dual-OTA разметка + rollback

**Files:** Modify `sdkconfig.defaults`.

- [ ] **Step 1: Добавить в `sdkconfig.defaults`** (в конец)
```
CONFIG_ESPTOOLPY_FLASHSIZE_4MB=y
CONFIG_PARTITION_TABLE_TWO_OTA=y
CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE=y
```

- [ ] **Step 2: Удалить старый sdkconfig (чтобы defaults применились) и собрать**
```bash
mkdir -p /tmp/py313bin && ln -sf /opt/homebrew/bin/python3.13 /tmp/py313bin/python3
cd /Users/adamjohnson/VSCode/esp32-p4-car && export PATH=/tmp/py313bin:$PATH && source ~/esp/esp-idf/export.sh >/dev/null 2>&1
rm -f sdkconfig && idf.py build 2>&1 | grep -iE "Project build complete|error:|app partition|partition table" | grep -viE "rv32|march" | tail -6
```
Expected: `Project build complete`; в выводе видно, что app влезает в OTA-слот (~1.5 МБ). Если «does not fit» — увеличить слоты кастомной `partitions.csv` (но для ~0.95 МБ app слот 1.5 МБ хватает).

- [ ] **Step 3: Commit** (бинарь/конфиг разметки)
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add sdkconfig.defaults
git commit -m "feat: dual-OTA partition table + rollback (CONFIG_PARTITION_TABLE_TWO_OTA)"
```
> ⚠️ На железе разметка применится только после **разовой прошивки по USB** (`idf.py flash`). Это сменит NVS-разметку → калибровку нужно будет один раз переснять.

---

## Task 2: Версия прошивки из app-desc

**Files:** Modify `main/status_api.c`.

- [ ] **Step 1: В `main/status_api.c` использовать версию приложения**
Add include near the top:
```c
#include "esp_app_desc.h"
```
In `status_get`, replace the `FW_VERSION` usage. Find the `snprintf(... "fw":"%s" ... FW_VERSION ...)` and change `FW_VERSION` to `esp_app_get_description()->version`. Concretely, the version string:
```c
    const char *fw = esp_app_get_description()->version;
```
and use `fw` in the `snprintf` where `FW_VERSION` was (`"\"fw\":\"%s\"...", ..., fw, ...`). Remove the now-unused `#define FW_VERSION ...` if present.

- [ ] **Step 2: Build**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && export PATH=/tmp/py313bin:$PATH && source ~/esp/esp-idf/export.sh >/dev/null 2>&1
idf.py build 2>&1 | grep -iE "Project build complete|error:" | grep -viE "rv32|march" | tail -2
```
Expected: `Project build complete`. (Версия теперь из `PROJECT_VER`/`git describe`; для релиза собирать на теге `vX.Y`.)

- [ ] **Step 3: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add main/status_api.c && git commit -m "feat: report app-desc version in /status fw"
```

---

## Task 3: Эндпоинт `/ota` + rollback mark-valid

**Files:** Create `main/ota_api.{c,h}`; Modify `main/main.c`, `main/CMakeLists.txt`.

- [ ] **Step 1: `main/ota_api.h`**
```c
#ifndef OTA_API_H
#define OTA_API_H
#include "esp_err.h"
// Register POST /ota — streams an app image into the next OTA slot, validates, reboots.
esp_err_t ota_api_start(void);
#endif // OTA_API_H
```

- [ ] **Step 2: `main/ota_api.c`**
```c
#include "ota_api.h"
#include <string.h>
#include "esp_http_server.h"
#include "esp_ota_ops.h"
#include "esp_partition.h"
#include "esp_system.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "http_server.h"
#include "car.h"

static const char *TAG = "ota_api";

static esp_err_t ota_post(httpd_req_t *req) {
    car_stop();  // motors off during flashing
    const esp_partition_t *part = esp_ota_get_next_update_partition(NULL);
    if (part == NULL) {
        httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "no ota partition");
        return ESP_FAIL;
    }
    esp_ota_handle_t handle = 0;
    if (esp_ota_begin(part, OTA_SIZE_UNKNOWN, &handle) != ESP_OK) {
        httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "ota begin failed");
        return ESP_FAIL;
    }
    ESP_LOGI(TAG, "OTA → %s, %d bytes", part->label, req->content_len);

    char buf[1024];
    int remaining = req->content_len;
    while (remaining > 0) {
        int chunk = remaining < (int)sizeof(buf) ? remaining : (int)sizeof(buf);
        int r = httpd_req_recv(req, buf, chunk);
        if (r <= 0) {
            if (r == HTTPD_SOCK_ERR_TIMEOUT) continue;
            esp_ota_abort(handle);
            httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "recv error");
            return ESP_FAIL;
        }
        if (esp_ota_write(handle, buf, r) != ESP_OK) {
            esp_ota_abort(handle);
            httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "ota write failed");
            return ESP_FAIL;
        }
        remaining -= r;
    }
    if (esp_ota_end(handle) != ESP_OK) {
        httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "image invalid");
        return ESP_FAIL;
    }
    if (esp_ota_set_boot_partition(part) != ESP_OK) {
        httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "set boot failed");
        return ESP_FAIL;
    }
    httpd_resp_sendstr(req, "ok");
    ESP_LOGI(TAG, "OTA done — rebooting");
    vTaskDelay(pdMS_TO_TICKS(500));
    esp_restart();
    return ESP_OK;
}

esp_err_t ota_api_start(void) {
    httpd_handle_t server = http_server_get_handle();
    if (server == NULL) { ESP_LOGE(TAG, "http server not started"); return ESP_FAIL; }
    httpd_uri_t u = { .uri = "/ota", .method = HTTP_POST, .handler = ota_post };
    return httpd_register_uri_handler(server, &u);
}
```

- [ ] **Step 3: `main/main.c` — старт + rollback mark-valid**
Add `#include "ota_api.h"` and `#include "esp_ota_ops.h"` near the other includes. After the line `ESP_ERROR_CHECK(status_api_start());`, add:
```c
    ESP_ERROR_CHECK(ota_api_start());
```
At the END of `app_main` (after all services started — wifi/http/ws/etc.), add the rollback confirmation:
```c
    // OTA rollback: mark this freshly-flashed image valid so the bootloader won't roll back.
    const esp_partition_t *running = esp_ota_get_running_partition();
    esp_ota_img_states_t ota_state;
    if (esp_ota_get_state_partition(running, &ota_state) == ESP_OK &&
        ota_state == ESP_OTA_IMG_PENDING_VERIFY) {
        esp_ota_mark_app_valid_cancel_rollback();
    }
```

- [ ] **Step 4: `main/CMakeLists.txt`** — add `"ota_api.c"` to `SRCS` and `app_update` to `REQUIRES` (esp_ota_ops lives in the `app_update` component).

- [ ] **Step 5: Build**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && export PATH=/tmp/py313bin:$PATH && source ~/esp/esp-idf/export.sh >/dev/null 2>&1
idf.py build 2>&1 | grep -iE "Project build complete|error:" | grep -viE "rv32|march" | tail -3
```
Expected: `Project build complete`.

- [ ] **Step 6: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add main/ota_api.h main/ota_api.c main/main.c main/CMakeLists.txt
git commit -m "feat: POST /ota endpoint (esp_ota) + rollback mark-valid"
```

---

## Task 4: Mock `/ota`

**Files:** Modify `tools/mock_car/mock_car.py`.

- [ ] **Step 1: Добавить хендлер и роут**
Add this handler (next to `calib_save`):
```python
async def ota(request):
    data = await request.read()
    print(f"ota: received {len(data)} bytes")
    return web.Response(text="ok")
```
Add to `app.add_routes([...])`: `web.post("/ota", ota),`.

- [ ] **Step 2: Smoke-test**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/tools/mock_car
pkill -f mock_car.py 2>/dev/null; sleep 1
nohup .venv/bin/python -u mock_car.py > /tmp/mock_car.log 2>&1 & disown; sleep 2
head -c 5000 /dev/zero | curl -s -X POST --data-binary @- http://127.0.0.1:8080/ota; echo
grep "ota:" /tmp/mock_car.log
```
Expected: `ok` and a log line `ota: received 5000 bytes`.

- [ ] **Step 3: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add tools/mock_car/mock_car.py && git commit -m "feat(tools): mock /ota endpoint"
```

---

## Task 5: iOS `UpdateClient`

**Files:** Create `ios/ESP32Car/UpdateClient.swift`.

- [ ] **Step 1: Создать `ios/ESP32Car/UpdateClient.swift`**
```swift
import Foundation

/// Fetches the latest firmware from GitHub Releases and uploads it to the car's /ota.
@MainActor
final class UpdateClient: NSObject, ObservableObject {
    struct Release { let tag: String; let assetURL: URL }
    @Published var uploadProgress: Double = 0

    private let repo = "ajohnson-smarthome/AJPicoCar"

    /// Normalize a version like "v1.2" / "v1.2-3-gabc" → "1.2" for comparison.
    static func normalize(_ v: String?) -> String {
        guard let v else { return "" }
        var s = v
        if s.hasPrefix("v") { s.removeFirst() }
        if let dash = s.firstIndex(of: "-") { s = String(s[s.startIndex..<dash]) }
        return s
    }

    func latestRelease() async -> Release? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = j["tag_name"] as? String,
                  let assets = j["assets"] as? [[String: Any]] else { return nil }
            let bin = assets.first { ($0["name"] as? String)?.hasSuffix(".bin") == true }
            guard let s = bin?["browser_download_url"] as? String, let u = URL(string: s) else { return nil }
            return Release(tag: tag, assetURL: u)
        } catch { return nil }
    }

    func download(_ url: URL) async -> URL? {
        do {
            let (tmp, _) = try await URLSession.shared.download(from: url)
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("firmware.bin")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            return dest
        } catch { return nil }
    }

    func upload(_ binURL: URL) async -> Bool {
        guard let url = URL(string: CarHost.httpBase + "/ota") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (_, resp) = try await session.upload(for: req, fromFile: binURL)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }
}

extension UpdateClient: URLSessionTaskDelegate {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                                totalBytesExpectedToSend: Int64) {
        let p = totalBytesExpectedToSend > 0 ? Double(totalBytesSent) / Double(totalBytesExpectedToSend) : 0
        Task { @MainActor in self.uploadProgress = p }
    }
}
```

- [ ] **Step 2: Regenerate + compile-check**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -6
```
Expected: `** BUILD SUCCEEDED **`. Report any Swift 6 concurrency diagnostics (the delegate is `nonisolated` and hops to `@MainActor` — should be clean).

- [ ] **Step 3: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/UpdateClient.swift && git commit -m "feat(ios): UpdateClient — GitHub latest release + download + upload(progress)"
```

---

## Task 6: iOS `FirmwareView` + вход + строки

**Files:** Create `ios/ESP32Car/FirmwareView.swift`; Modify `ios/ESP32Car/SettingsView.swift`, `ios/ESP32Car/L.swift`, `ios/ESP32Car/Resources/ru.lproj/Localizable.strings`.

- [ ] **Step 1: Строки в `ru.lproj/Localizable.strings`** (добавить)
```
"settings.firmware"  = "Прошивка";
"fw.current"         = "Текущая: %@";
"fw.latest"          = "Доступно: %@";
"fw.upToDate"        = "Прошивка актуальна";
"fw.download"        = "1. Скачать (нужен интернет)";
"fw.connectCar"      = "2. Подключись к Wi-Fi ESP32-Car";
"fw.flash"           = "3. Залить";
"fw.downloading"     = "Скачиваю…";
"fw.uploading"       = "Заливаю…";
"fw.rebooting"       = "Перезагрузка машинки…";
"fw.failed"          = "Не удалось — повтори.";
"fw.done"            = "Готово ✓";
```

- [ ] **Step 2: Аксессоры в `L.swift`** (добавить рядом с остальными)
```swift
    static var settingsFirmware: String { s("settings.firmware") }
    static var fwUpToDate: String { s("fw.upToDate") }
    static var fwDownload: String { s("fw.download") }
    static var fwConnectCar: String { s("fw.connectCar") }
    static var fwFlash: String { s("fw.flash") }
    static var fwDownloading: String { s("fw.downloading") }
    static var fwUploading: String { s("fw.uploading") }
    static var fwRebooting: String { s("fw.rebooting") }
    static var fwFailed: String { s("fw.failed") }
    static var fwDone: String { s("fw.done") }
    static func fwCurrent(_ v: String) -> String { s("fw.current", v) }
    static func fwLatest(_ v: String) -> String { s("fw.latest", v) }
```

- [ ] **Step 3: Создать `ios/ESP32Car/FirmwareView.swift`**
```swift
import SwiftUI

struct FirmwareView: View {
    let palette: Palette
    @ObservedObject var status: CarStatus
    @StateObject private var client = UpdateClient()

    @State private var release: UpdateClient.Release?
    @State private var binURL: URL?
    @State private var phase: Phase = .idle
    enum Phase { case idle, downloading, downloaded, uploading, rebooting, done, failed }

    private var current: String { status.fw ?? "—" }
    private var updateAvailable: Bool {
        guard let r = release else { return false }
        return UpdateClient.normalize(r.tag) != UpdateClient.normalize(status.fw)
    }

    var body: some View {
        ZStack {
            palette.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text(L.fwCurrent(current)).foregroundStyle(palette.text)
                Text(L.fwLatest(release?.tag ?? "—")).foregroundStyle(palette.muted)

                if !updateAvailable, release != nil {
                    Label(L.fwUpToDate, systemImage: "checkmark.seal").foregroundStyle(palette.accent)
                } else if updateAvailable {
                    Button { Task { await downloadStep() } } label: { Label(L.fwDownload, systemImage: "arrow.down.circle") }
                        .buttonStyle(.bordered).tint(palette.accent).disabled(phase == .downloading)
                    if phase == .downloaded || phase == .uploading || phase == .rebooting {
                        Text(L.fwConnectCar).font(.footnote).foregroundStyle(palette.muted)
                        Button { Task { await flashStep() } } label: { Label(L.fwFlash, systemImage: "bolt.fill") }
                            .buttonStyle(.borderedProminent).tint(palette.accent)
                            .disabled(binURL == nil || !status.online || phase == .uploading || phase == .rebooting)
                    }
                }

                switch phase {
                case .downloading: ProgressView(L.fwDownloading)
                case .uploading: ProgressView(value: client.uploadProgress) { Text(L.fwUploading) }
                case .rebooting: ProgressView(L.fwRebooting)
                case .done: Label(L.fwDone, systemImage: "checkmark.circle.fill").foregroundStyle(palette.accent)
                case .failed: Text(L.fwFailed).foregroundStyle(palette.warn)
                default: EmptyView()
                }
                Spacer()
            }
            .padding()
        }
        .navigationTitle(L.settingsFirmware)
        .navigationBarTitleDisplayMode(.inline)
        .tint(palette.accent)
        .task { release = await client.latestRelease() }
    }

    private func downloadStep() async {
        guard let r = release else { return }
        phase = .downloading
        if let url = await client.download(r.assetURL) { binURL = url; phase = .downloaded }
        else { phase = .failed }
    }
    private func flashStep() async {
        guard let url = binURL else { return }
        phase = .uploading
        let ok = await client.upload(url)
        if ok { phase = .rebooting; try? await Task.sleep(nanoseconds: 6_000_000_000); phase = .done }
        else { phase = .failed }
    }
}
```

- [ ] **Step 4: `SettingsView.swift` — строка «Прошивка»**
The settings `List` currently has one `NavigationLink` (Калибровка). Add a second row after it, inside the same `List`:
```swift
                    NavigationLink {
                        FirmwareView(palette: palette, status: status)
                    } label: {
                        Label(L.settingsFirmware, systemImage: "arrow.down.circle")
                            .foregroundStyle(palette.text)
                    }
                    .listRowBackground(palette.panel)
```
`SettingsView` must receive `status`. Change `struct SettingsView: View { let palette: Palette` to also take `@ObservedObject var status: CarStatus`, and update its call site in `DriveView` (`.sheet(isPresented: $showSettings) { SettingsView(palette: p) }` → `SettingsView(palette: p, status: status)`).

- [ ] **Step 5: Regenerate + compile-check**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -8
```
Expected: `** BUILD SUCCEEDED **`. Fix any Swift errors and rebuild.

- [ ] **Step 6: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/FirmwareView.swift ios/ESP32Car/SettingsView.swift ios/ESP32Car/DriveView.swift ios/ESP32Car/L.swift ios/ESP32Car/Resources
git commit -m "feat(ios): firmware update screen (GitHub → download → flash) in settings"
```

---

## Task 7: Проверка

**Files:** (проверка — без изменений кода)

- [ ] **Step 1: Симулятор против мока (поток UI)**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/tools/mock_car
pgrep -f mock_car.py >/dev/null || { nohup .venv/bin/python -u mock_car.py > /tmp/mock_car.log 2>&1 & disown; }
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios
xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | grep -iE "BUILD SUCCEEDED|FAILED" | head -1
xcrun simctl install booted "$(find /tmp/ddata/Build/Products -name ESP32Car.app | head -1)"
xcrun simctl terminate booted com.adamjohnson.esp32car 2>/dev/null
xcrun simctl launch booted com.adamjohnson.esp32car
```
Проверить: ⚙ → «Прошивка» → видна текущая (из `/status`) и «Доступно vX» (реальный GitHub, если есть релиз); «Скачать» (нужен интернет на маке/симуляторе) → «Залить» (мок принимает, `ota: received N bytes` в `/tmp/mock_car.log`) → прогресс → «Готово». Обе темы.

- [ ] **Step 2: На устройстве (с пользователем)**
1) Выложить первый релиз: на машинке-репо `git tag v1.0 && git push --tags`, затем GitHub Release `v1.0` с asset `build/esp32-p4-car.bin`.
2) Разовый wired-flash dual-OTA: `idf.py -p /dev/cu.usbmodem* flash` (после — переснять калибровку).
3) Сделать тег `v1.1`, собрать, выложить Release `v1.1` с новым `.bin`.
4) В аппе: ⚙ → Прошивка → видно `v1.0 → v1.1` → Скачать (интернет) → подключиться к `ESP32-Car` → Залить → перезагрузка → `/status` показывает `v1.1`.
5) Откат: залить заведомо битый/несовместимый образ → машинка должна откатиться на предыдущий слот.

---

## Self-Review заметки

- **Покрытие спеки:** dual-OTA разметка+rollback (Task 1); версия из app-desc (Task 2); `/ota` esp_ota + rollback mark-valid (Task 3); mock `/ota` (Task 4); `UpdateClient` GitHub+download+upload (Task 5); `FirmwareView` + вход + строки (Task 6); проверка sim+устройство (Task 7). Пререкизит «первый Release» — в Task 7 Step 2.
- **Тип-консистентность:** `ota_api_start`; `esp_ota_*`/`esp_app_get_description`; `UpdateClient.Release(tag,assetURL)`/`normalize`/`latestRelease`/`download`/`upload`/`uploadProgress`; `FirmwareView(palette:status:)`; `SettingsView(palette:status:)` (call site в DriveView обновлён); `L.fw*`/`settingsFirmware`; `CarHost.httpBase`, `status.fw`/`status.online`.
- **Тесты:** чистой логики мало (`normalize` тривиальна); основная проверка — сборка + поток в симуляторе (мок) + реальный OTA на устройстве.
- **Замечания:** смена partition table стирает NVS → переснять калибровку (разово). Версия для релиза — собирать на git-теге. httpd стримит тело чанками (≈1 МБ ок). app_update в REQUIRES для esp_ota_ops.
