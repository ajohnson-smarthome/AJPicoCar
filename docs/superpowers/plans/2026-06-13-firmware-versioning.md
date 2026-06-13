# Версионирование прошивок — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Версия прошивки = `v<semver>+<git-commit-count>` (`v1.0+247`), встраивается при сборке; OTA сравнивает **численно** по номеру билда; релизы режутся скриптом `tools/release.sh`.

**Architecture:** `version.txt` (семантика) + `git rev-list --count` (номер) → `PROJECT_VER` в корневом CMake → `esp_app_desc`/`/status`. iOS: чистые `buildNumber()`+`isUpdateAvailable()` (host-тест) заменяют строковое равенство. `release.sh` собирает + `gh release create`.

**Tech Stack:** ESP-IDF 5.4 CMake, bash + gh CLI, Swift 6, swiftc host-тест. Ветка `versioning`.

---

## File Structure

| Файл | Изменение |
|---|---|
| `version.txt` *(new)* | семантика `1.0` |
| `CMakeLists.txt` (корень) | читает version.txt + git count → `set(PROJECT_VER ...)` |
| `tools/release.sh` *(new)* | сборка + GitHub-релиз с номером билда (+`--dry-run`) |
| `ios/ESP32Car/UpdateClient.swift` | `buildNumber()` + `isUpdateAvailable()` |
| `ios/ESP32Car/FirmwareView.swift` | сравнение через `isUpdateAvailable` |
| `ios/ESP32CarTests/...` | host-тест логики |
| `tools/mock_car/mock_car.py` | `/status` `fw` с версией-номером |

---

## Task 1: `version.txt` + CMake `PROJECT_VER`

**Files:** Create `version.txt`; Modify `CMakeLists.txt`.

- [ ] **Step 1: `version.txt`** (корень репо) — одна строка:
```
1.0
```

- [ ] **Step 2: `CMakeLists.txt`** — заменить целиком на:
```cmake
cmake_minimum_required(VERSION 3.16)

# Firmware version = v<semver from version.txt>+<git commit count>.
# Set PROJECT_VER BEFORE project() so esp_app_desc / esp_app_get_description()->version uses it
# (takes precedence over IDF's version.txt auto-detection and git-describe fallback).
file(STRINGS "${CMAKE_CURRENT_LIST_DIR}/version.txt" SEMVER LIMIT_COUNT 1)
string(STRIP "${SEMVER}" SEMVER)
execute_process(
    COMMAND git rev-list --count HEAD
    WORKING_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
    OUTPUT_VARIABLE BUILD_NUM
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET)
if(NOT BUILD_NUM)
    set(BUILD_NUM "0")
endif()
set(PROJECT_VER "v${SEMVER}+${BUILD_NUM}")

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(esp32-p4-car)
```

- [ ] **Step 3: Build + проверить версию**
```bash
mkdir -p /tmp/py313bin && ln -sf /opt/homebrew/bin/python3.13 /tmp/py313bin/python3
cd /Users/adamjohnson/VSCode/esp32-p4-car && export PATH=/tmp/py313bin:$PATH && source ~/esp/esp-idf/export.sh >/dev/null 2>&1
idf.py fullclean >/dev/null 2>&1; idf.py build 2>&1 | grep -iE "Project build complete|error:" | grep -viE "rv32|march|reent" | tail -1
# извлечь встроенную версию из app image
ESPTOOL=$(command -v esptool.py); strings build/esp32-p4-car.bin | grep -E "^v[0-9]+\.[0-9]+\+[0-9]+" | head -1
```
Expected: `Project build complete` и строка вида `v1.0+247` (номер = `git rev-list --count HEAD`).

- [ ] **Step 4: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add version.txt CMakeLists.txt
git commit -m "feat: PROJECT_VER = v<semver>+<git build count> embedded at build time"
```

---

## Task 2: `tools/release.sh`

**Files:** Create `tools/release.sh`.

- [ ] **Step 1: `tools/release.sh`** (с правами на исполнение):
```bash
#!/usr/bin/env bash
# Cut a GitHub release whose tag carries the firmware build number (v<semver>+<count>).
# Usage: tools/release.sh [--dry-run] ["release notes"]
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then DRY_RUN=1; shift; fi

SEMVER=$(tr -d '[:space:]' < version.txt)
BUILD_NUM=$(git rev-list --count HEAD)
VER="v${SEMVER}+${BUILD_NUM}"
TITLE="v${SEMVER} (build ${BUILD_NUM})"
BIN="build/esp32-p4-car.bin"
NOTES="${1:-Release ${VER}}"

if [ -n "$(git status --porcelain)" ]; then
    echo "ERROR: working tree not clean — build number would not match the release commit"; exit 1
fi
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "main" ]; then echo "ERROR: not on main (on $BRANCH)"; exit 1; fi

if [ "$DRY_RUN" = 1 ]; then
    echo "[dry-run] version : $VER"
    echo "[dry-run] tag     : $VER"
    echo "[dry-run] title   : $TITLE"
    echo "[dry-run] asset   : $BIN"
    echo "[dry-run] notes   : $NOTES"
    echo "[dry-run] would run: idf.py fullclean && idf.py build && gh release create '$VER' '$BIN' --title '$TITLE' --notes '...'"
    exit 0
fi

mkdir -p /tmp/py313bin && ln -sf /opt/homebrew/bin/python3.13 /tmp/py313bin/python3
export PATH=/tmp/py313bin:$PATH
source ~/esp/esp-idf/export.sh >/dev/null 2>&1
idf.py fullclean >/dev/null
idf.py build
[ -f "$BIN" ] || { echo "ERROR: $BIN not built"; exit 1; }

gh release create "$VER" "$BIN" --title "$TITLE" --notes "$NOTES"
echo "Released $VER"
```

- [ ] **Step 2: chmod + dry-run**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
chmod +x tools/release.sh
git add . >/dev/null 2>&1  # need clean tree for the dry-run's git check; stage nothing else
# dry-run requires clean tree; commit the script first in Step 3, OR test dry-run logic ignoring the clean check temporarily:
tools/release.sh --dry-run "test notes" || echo "(dry-run blocked by clean-tree check — expected until committed)"
```
Expected: либо печать `[dry-run] version : v1.0+247 ...`, либо сообщение про чистое дерево (если есть незакоммиченное). Прогнать ещё раз ПОСЛЕ коммита (Step 3) для чистого дерева — там должна быть полная dry-run печать с правильной версией.

- [ ] **Step 3: Commit, затем финальный dry-run на чистом дереве**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add tools/release.sh
git commit -m "feat(tools): release.sh — build + GitHub release tagged v<semver>+<buildnum>"
tools/release.sh --dry-run
```
Expected (после коммита, дерево чистое): полная печать `[dry-run] version : v1.0+<count>`, tag/title/asset корректны, **без** сборки/публикации.

---

## Task 3: iOS — численное сравнение версий (TDD)

**Files:** Modify `ios/ESP32Car/UpdateClient.swift`, `ios/ESP32Car/FirmwareView.swift`, `ios/ESP32CarTests/ControlModelTests.swift`.

- [ ] **Step 1 (TDD): добавить в `UpdateClient`** (после `normalize`):
```swift
    /// Build number after the first "+" (e.g. "v1.2+246" -> 246); nil if absent/non-numeric.
    static func buildNumber(_ version: String?) -> Int? {
        guard let version, let plus = version.firstIndex(of: "+") else { return nil }
        let digits = version[version.index(after: plus)...].prefix { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }

    /// Update available iff both versions carry a build number and latest > running.
    /// Falls back to normalized string inequality when a build number is missing (legacy firmware/releases).
    static func isUpdateAvailable(running: String?, latest: String?) -> Bool {
        if let r = buildNumber(running), let l = buildNumber(latest) { return l > r }
        return normalize(latest) != normalize(running)
    }
```

- [ ] **Step 2 (native red→green):** `/tmp/ver_check.swift` — но `UpdateClient` тащит SwiftUI/URLSession,
  поэтому тестируем чистые статики, вынеся их в standalone-проверку через mirror. Проще: проверить логику
  напрямую в swiftc, скомпилировав мини-копию недоступна (UpdateClient не pure). Поэтому host-тест делаем
  ТОЛЬКО как XCTest (Step 3) + быстрый inline-расчёт. Пропустить native-swiftc для UpdateClient.

  Вместо этого — мини-проверка логики чистой функции в отрыве: создать `/tmp/bn.swift`:
```swift
import Foundation
func buildNumber(_ version: String?) -> Int? {
    guard let version, let plus = version.firstIndex(of: "+") else { return nil }
    let digits = version[version.index(after: plus)...].prefix { $0.isNumber }
    return digits.isEmpty ? nil : Int(digits)
}
func isUpdateAvailable(running: String?, latest: String?) -> Bool {
    if let r = buildNumber(running), let l = buildNumber(latest) { return l > r }
    return (latest ?? "") != (running ?? "")
}
precondition(buildNumber("v1.2+246") == 246)
precondition(buildNumber("v1.0") == nil)
precondition(buildNumber("v1.2+246-dirty") == 246)
precondition(isUpdateAvailable(running: "v1.0+246", latest: "v1.0+250") == true)
precondition(isUpdateAvailable(running: "v1.0+250", latest: "v1.0+250") == false)
precondition(isUpdateAvailable(running: "v1.0+250", latest: "v1.0+240") == false)
print("buildNumber logic: all passed")
```
Запуск: `swiftc /tmp/bn.swift -o /tmp/bn && /tmp/bn` → `buildNumber logic: all passed`.
(Это проверяет алгоритм; в UpdateClient — та же логика, `normalize` лишь усиливает fallback.)

- [ ] **Step 3: XCTest-зеркало** — в `ios/ESP32CarTests/ControlModelTests.swift` перед закрывающей `}`:
```swift
    func testBuildNumberAndUpdate() {
        XCTAssertEqual(UpdateClient.buildNumber("v1.2+246"), 246)
        XCTAssertNil(UpdateClient.buildNumber("v1.0"))
        XCTAssertEqual(UpdateClient.buildNumber("v1.2+246-dirty"), 246)
        XCTAssertTrue(UpdateClient.isUpdateAvailable(running: "v1.0+246", latest: "v1.0+250"))
        XCTAssertFalse(UpdateClient.isUpdateAvailable(running: "v1.0+250", latest: "v1.0+250"))
        XCTAssertFalse(UpdateClient.isUpdateAvailable(running: "v1.0+250", latest: "v1.0+240"))
        // fallback when latest has no build number (legacy v1.0 release)
        XCTAssertTrue(UpdateClient.isUpdateAvailable(running: "v0.9", latest: "v1.0"))
    }
```

- [ ] **Step 4: `FirmwareView.swift`** — найти строку сравнения (вид
  `phase = (UpdateClient.normalize(r.tag) != UpdateClient.normalize(status.fw)) ? .available : .upToDate`)
  и заменить на:
```swift
        phase = UpdateClient.isUpdateAvailable(running: status.fw, latest: r.tag) ? .available : .upToDate
```

- [ ] **Step 5: Build + checks**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -6
grep -rn '[А-Яа-яЁё]' --include='*.swift' ESP32Car && echo LEAK || echo "(чисто)"
swiftc /tmp/bn.swift -o /tmp/bn && /tmp/bn
```
Expected: `** BUILD SUCCEEDED **`, чисто, `buildNumber logic: all passed`.

- [ ] **Step 6: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/UpdateClient.swift ios/ESP32Car/FirmwareView.swift ios/ESP32CarTests/ControlModelTests.swift
git commit -m "feat(ios): OTA compares firmware by numeric build number (string fallback for legacy)"
```

---

## Task 4: Мок-версия + проверка

**Files:** Modify `tools/mock_car/mock_car.py`.

- [ ] **Step 1:** в `/status`-ответе мока заменить `"fw": "mock"` на версионную строку, чтобы апп показывал
  её как текущую: `"fw": "v1.0+9000"`. (Бутстрап `/status` несёт fw; WS-кадр fw не несёт — без изменений.)

- [ ] **Step 2: Проверка**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/tools/mock_car
pkill -f mock_car.py 2>/dev/null; sleep 1; nohup .venv/bin/python -u mock_car.py >/tmp/mock_car.log 2>&1 & disown; sleep 2
curl -s http://127.0.0.1:8080/status | python3 -c "import sys,json; print('fw=', json.load(sys.stdin)['fw'])"
```
Expected: `fw= v1.0+9000`.

- [ ] **Step 3:** host-тесты прошивки (`cd test && make run | tail -1`) — не затронуты, должны быть зелёные.
- [ ] **Step 4: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add tools/mock_car/mock_car.py && git commit -m "feat(tools): mock /status reports a versioned fw string"
```

---

## Self-Review заметки

- **Покрытие спеки:** version.txt семантика (T1); CMake PROJECT_VER = `v<semver>+<count>` (T1); release.sh
  + dry-run (T2); buildNumber «после +» + isUpdateAvailable численно с fallback (T3); FirmwareView
  использует isUpdateAvailable (T3); мок версия (T4). OTA-механика заливки не тронута.
- **Тип-консистентность:** `UpdateClient.buildNumber(_:) -> Int?`, `UpdateClient.isUpdateAvailable(running:latest:) -> Bool`;
  CMake `PROJECT_VER`/`SEMVER`/`BUILD_NUM`; `release.sh` `VER`/`TITLE`/`BIN`.
- **Замечания:** легаси-релиз `v1.0` (без `+`) → fallback на строковое сравнение, пока не вырежем свежий
  релиз через release.sh (тогда latest несёт номер → чистое численное сравнение). Полный e2e «доступно
  обновление» по-настоящему проверяется при первом реальном релизе (ассистент по запросу). CMake
  execute_process читает git-count на configure — для релиза fullclean гарантирует свежесть.
