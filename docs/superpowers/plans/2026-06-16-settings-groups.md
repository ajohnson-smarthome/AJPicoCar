# Settings Menu Grouping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Group the 7 flat rows in `SettingsView` into 3 labeled sections (Настройка машины / Движение / Система) and swap the «Колесо и моторы» icon from `ruler` to `steeringwheel`.

**Architecture:** Pure presentational change to one SwiftUI screen. Wrap the existing `NavigationLink` rows in three `Section`s with localized headers (the screen's default inset-grouped `List` renders each `Section` as its own rounded group with a header — no list-style change needed). Headers are styled via a small DRY helper. Footer, custom header, and child-screen behavior are untouched.

**Tech Stack:** SwiftUI (Swift 6), XcodeGen, `enum L` localization over `Localizable.strings`.

**Spec:** `docs/superpowers/specs/2026-06-16-settings-groups-design.md`

**Branch:** `feat/settings-groups` (already created, spec committed there).

---

## File Structure

- `ios/ESP32Car/Resources/ru.lproj/Localizable.strings` — add 3 section-header strings.
- `ios/ESP32Car/L.swift` — add 3 typed accessors.
- `ios/ESP32Car/SettingsView.swift` — wrap the 7 rows in 3 `Section`s + a `sectionHeader` helper; change the first row's `systemImage`.

No new files. No firmware/test changes.

---

### Task 1: Group the Settings list into 3 sections + steeringwheel icon

**Files:**
- Modify: `ios/ESP32Car/Resources/ru.lproj/Localizable.strings`
- Modify: `ios/ESP32Car/L.swift`
- Modify: `ios/ESP32Car/SettingsView.swift`

- [ ] **Step 1: Add the 3 section-header strings to `Localizable.strings`**

Append near the other `settings.*` entries:
```
"settings.groupSetup"   = "Настройка машины";
"settings.groupDriving" = "Движение";
"settings.groupSystem"  = "Система";
```

- [ ] **Step 2: Add the 3 typed accessors to `L.swift`**

Inside `enum L` (near the other `settings*` accessors, e.g. after `settingsFirmware` if present, otherwise after `settingsCalibration`):
```swift
    static var settingsGroupSetup: String { s("settings.groupSetup") }
    static var settingsGroupDriving: String { s("settings.groupDriving") }
    static var settingsGroupSystem: String { s("settings.groupSystem") }
```

- [ ] **Step 3: Replace the `List { ... }` block in `SettingsView.swift` with a 3-section version**

In `ios/ESP32Car/SettingsView.swift`, replace the entire current `List { ... }` ... `.scrollContentBackground(.hidden)` block (currently lines 14–65 — the 7 flat `NavigationLink`s) with this sectioned version. Note the **icon change** on the first row (`"ruler"` → `"steeringwheel"`); all other rows keep their existing destinations, labels, icons, and `.listRowBackground(palette.panel)`:

```swift
                List {
                    Section {
                        NavigationLink {
                            WheelParamsView(palette: palette)
                        } label: {
                            Label(L.wheelTitle, systemImage: "steeringwheel")
                                .foregroundStyle(palette.text)
                        }
                        .listRowBackground(palette.panel)
                        NavigationLink {
                            CalibrationView(palette: palette)
                        } label: {
                            Label(L.settingsCalibration, systemImage: "gearshape.2")
                                .foregroundStyle(palette.text)
                        }
                        .listRowBackground(palette.panel)
                    } header: {
                        sectionHeader(L.settingsGroupSetup)
                    }
                    Section {
                        NavigationLink {
                            RampView(palette: palette)
                        } label: {
                            Label(L.rampTitle, systemImage: "gauge.with.needle")
                                .foregroundStyle(palette.text)
                        }
                        .listRowBackground(palette.panel)
                        NavigationLink {
                            TrimView(palette: palette)
                        } label: {
                            Label(L.trimTitle, systemImage: "arrow.up.to.line")
                                .foregroundStyle(palette.text)
                        }
                        .listRowBackground(palette.panel)
                        NavigationLink {
                            RecoverView(palette: palette)
                        } label: {
                            Label(L.recoverTitle, systemImage: "arrow.uturn.backward")
                                .foregroundStyle(palette.text)
                        }
                        .listRowBackground(palette.panel)
                        NavigationLink {
                            TricksSettingsView(palette: palette)
                        } label: {
                            Label(L.tricksTitle, systemImage: "sparkles")
                                .foregroundStyle(palette.text)
                        }
                        .listRowBackground(palette.panel)
                    } header: {
                        sectionHeader(L.settingsGroupDriving)
                    }
                    Section {
                        NavigationLink {
                            FirmwareView(palette: palette, status: status)
                        } label: {
                            Label(L.settingsFirmware, systemImage: "arrow.down.circle")
                                .foregroundStyle(palette.text)
                        }
                        .listRowBackground(palette.panel)
                    } header: {
                        sectionHeader(L.settingsGroupSystem)
                    }
                }
                .scrollContentBackground(.hidden)
```

- [ ] **Step 4: Add the `sectionHeader` helper to `SettingsView`**

Add this private helper inside `struct SettingsView` (e.g. directly above the existing `private var header: some View`):
```swift
    // Section header styled to the dark palette (the default gray header reads too light here).
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(palette.muted)
    }
```

- [ ] **Step 5: Commit**

```bash
git add ios/ESP32Car/SettingsView.swift ios/ESP32Car/L.swift ios/ESP32Car/Resources/ru.lproj/Localizable.strings
git commit -m "feat(ios): group Settings into 3 sections + steeringwheel icon"
```

---

### Task 2: Build + simulator verification

**Files:** none (verification only).

- [ ] **Step 1: Regenerate project + build the iOS target**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate
xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | tail -6
```
Expected: `** BUILD SUCCEEDED **`. (No new Swift files; the edits must compile — in particular `sectionHeader` and the three `L.settingsGroup*` accessors must resolve.)

If the iPhone 17 destination is unavailable, list options with `xcodebuild -scheme ESP32Car -showdestinations 2>&1 | grep -i iPhone | head` and use an available iPhone simulator; report which.

- [ ] **Step 2: Install + launch in the simulator (mock car running)**

Run:
```bash
APP=$(find /tmp/ddata/Build/Products -name ESP32Car.app | head -1)
xcrun simctl boot "iPhone 17" 2>/dev/null; open -a Simulator
xcrun simctl bootstatus "iPhone 17" -b 2>/dev/null | tail -1
xcrun simctl install booted "$APP"
xcrun simctl launch booted com.adamjohnson.esp32car
```
(If the mock car isn't running: `cd /Users/adamjohnson/VSCode/esp32-p4-car/tools/mock_car && nohup .venv/bin/python -u mock_car.py >/tmp/mock_car.log 2>&1 &`.)

- [ ] **Step 3: Capture a screenshot of the Settings screen**

The launch gate lands on Drive; opening Settings needs a tap (CLI can't tap reliably). Capture whatever is shown after a short wait, rotate, and eyeball:
```bash
sleep 8
xcrun simctl io booted screenshot /tmp/settings_groups.png >/dev/null 2>&1
sips --rotate 270 /tmp/settings_groups.png --out /tmp/settings_groups_r.png >/dev/null 2>&1
sips --resampleWidth 1100 /tmp/settings_groups_r.png >/dev/null 2>&1
echo "screenshot at /tmp/settings_groups_r.png"
```
Expected when the Settings sheet is visible: three labeled sections («Настройка машины» / «Движение» / «Система») as separate rounded groups, a steering-wheel icon on the «Колесо и моторы» row, and the uptime·version footer still below the list. (If the screenshot shows Drive rather than Settings — because Settings needs a tap — that's acceptable for an automated run; the build-succeeded gate plus the code review are the binding checks, and the controller/user can eyeball Settings live.)

- [ ] **Step 4: No commit** (verification only — Task 1 already committed the change).

---

## Self-Review

**Spec coverage:**
- 3 sections with the exact contents/order (Настройка машины: Колесо+Калибровка; Движение: Разгон+Прямолинейность+Авто-возврат+Трюки; Система: Прошивка) → Task 1 Step 3. ✅
- `ruler` → `steeringwheel` → Task 1 Step 3 (first row). ✅
- Section headers styled muted/small, not system-gray → Task 1 Step 4 (`sectionHeader` helper, `palette.muted`, 12pt). ✅
- 3 localized keys, no Cyrillic in Swift → Task 1 Steps 1–2. ✅
- Per-row `.listRowBackground(palette.panel)` + `.foregroundStyle(palette.text)` retained → Task 1 Step 3 (every row keeps both). ✅
- Footer, custom header, `.toolbar(.hidden)`, child screens untouched → only the `List` block + one helper change; everything else in the file is left as-is. ✅
- Verify via xcodebuild + screenshot → Task 2. ✅
- Out of scope (child screens, reordering, collapsible sections) → not touched. ✅

**Placeholder scan:** none — full replacement code given for every step. ✅

**Type/name consistency:** `sectionHeader(_:)` defined in Task 1 Step 4 and called 3× in Step 3; `L.settingsGroupSetup`/`settingsGroupDriving`/`settingsGroupSystem` defined in Step 2 and used in Step 3; string keys `settings.groupSetup`/`groupDriving`/`groupSystem` match between Steps 1 and 2; existing accessors (`L.wheelTitle`, `L.settingsCalibration`, `L.rampTitle`, `L.trimTitle`, `L.recoverTitle`, `L.tricksTitle`, `L.settingsFirmware`) reused verbatim from the current file. ✅
