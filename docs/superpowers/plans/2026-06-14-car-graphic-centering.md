# Унификация центрирования/размера машинки — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Машинка на всех split-экранах (графика слева, текст справа) — единого размера, строго по центру левой половины; анимации перецентрируются вокруг неё.

**Architecture:** Унификация числами (не извлечение компонента). Canvas-семейство (Connect/Ramp/Trim) приводится к корпусу 34×72 + колёса 11×15 + `center = size/2`; SwiftUI-семейство (Firmware/Calibration) уже центрировано; единый `scaleEffect` на всех 5 машинках (тюнинг по скриншотам, цель ~120pt); WifiGlyph (NoInternet) перецентровка `origin = h/2`.

**Tech Stack:** Swift 6 / SwiftUI Canvas. Ветка `car-centering`. Визуальный тюнинг → **inline-исполнение** (итерации по скриншотам). Симулятор `iPhone 17`, галерея `--args -gallery`.

---

## File Structure

| Файл | Изменение |
|---|---|
| `ios/ESP32Car/ConnectView.swift` | корпус 34×72 / колёса 11×15 (уже центр h/2); scale |
| `ios/ESP32Car/RampView.swift` | корпус 36×74→34×72, колёса 12×20→11×15, center 0.62→0.5; scale |
| `ios/ESP32Car/TrimView.swift` | то же, что Ramp |
| `ios/ESP32Car/NoInternetView.swift` | WifiGlyph origin `h/2+26 → h/2` |
| `ios/ESP32Car/FirmwareCarView.swift` | scaleEffect 1.9 → единый |
| `ios/ESP32Car/CalibrationView.swift` | carDiagram scaleEffect 1.9 → единый |

---

## Task 1: Canvas-семейство к единому корпусу + центр

**Files:** Modify `ios/ESP32Car/RampView.swift`, `ios/ESP32Car/TrimView.swift`, `ios/ESP32Car/ConnectView.swift`, `ios/ESP32Car/NoInternetView.swift`.

- [ ] **Step 1: RampView — константы корпуса/колёс.** В `RampCarView` заменить:
```swift
    private let carW: CGFloat = 34
    private let carLen: CGFloat = 72
    private let wheelW: CGFloat = 11
    private let wheelH: CGFloat = 15
    private let railGap: CGFloat = 12
    private let railMax: CGFloat = 52
```
(было carW 36 / carLen 74 / wheelW 12 / wheelH 20.)

- [ ] **Step 2: RampView — центр.** В `render(...)` заменить:
```swift
        // Car centred in the half; rails grow upward from the roof.
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
```
(было `size.height * 0.62`.)

- [ ] **Step 3: TrimView — константы.** В `TrimCarView` заменить:
```swift
    private let carW: CGFloat = 34
    private let carLen: CGFloat = 72
    private let wheelW: CGFloat = 11
    private let wheelH: CGFloat = 15
    private let railGap: CGFloat = 12
    private let railLen: CGFloat = 52
```

- [ ] **Step 4: TrimView — центр.** В `render(...)` заменить первую строку:
```swift
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
```
(было `size.height * 0.62`.)

- [ ] **Step 5: ConnectView — корпус/колёса.** В `ConnectCarView` привести константы корпуса/колёс к
  34×72 / 11×15 (как Ramp/Trim выше). Найти соответствующие `private let carW/carLen/wheelW/wheelH`
  (значения 36/74/12/20) и заменить на 34/72/11/15. `center` уже `size/2` — не трогать.

- [ ] **Step 6: NoInternetView — центр значка.** В `WifiGlyph.body` Canvas заменить:
```swift
                let origin = CGPoint(x: size.width / 2, y: size.height / 2)
```
(было `size.height / 2 + 26`.)

- [ ] **Step 7: Build + grep**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -4
grep -rn '[А-Яа-яЁё]' --include='*.swift' ESP32Car && echo LEAK || echo "(чисто)"
```
Expected: SUCCEEDED, чисто.

- [ ] **Step 8: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/ConnectView.swift ios/ESP32Car/RampView.swift ios/ESP32Car/TrimView.swift ios/ESP32Car/NoInternetView.swift
git commit -m "feat(ios): unify car body 34x72 + centre car in left half (Canvas screens) + centre wifi glyph"
```

---

## Task 2: Единый размер машинки (scale, тюнинг по скриншотам)

**Files:** Modify `ios/ESP32Car/ConnectView.swift`, `ios/ESP32Car/RampView.swift`, `ios/ESP32Car/TrimView.swift`, `ios/ESP32Car/FirmwareCarView.swift`, `ios/ESP32Car/CalibrationView.swift`.

Цель: `carLen(72) × scale ≈ 120pt` → стартовый `scale = 1.6` на всех пяти. Подтвердить/подправить скриншотами.

- [ ] **Step 1: выставить стартовый единый масштаб 1.6** на всех машинных графиках:
  - ConnectView `ConnectCarView`: `.scaleEffect(1.45)` → `.scaleEffect(1.6)`
  - RampView `RampCarView`: `.scaleEffect(1.45)` → `.scaleEffect(1.6)`
  - TrimView `TrimCarView`: `.scaleEffect(1.45)` → `.scaleEffect(1.6)`
  - FirmwareCarView: `.scaleEffect(1.9)` → `.scaleEffect(1.6)`
  - CalibrationView `carDiagram`: `.scaleEffect(1.9)` → `.scaleEffect(1.6)`

- [ ] **Step 2: build + прогон галереей, скриншоты split-кадров**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | grep -iE "BUILD SUCCEEDED|FAILED" | head -1
APP="$(find /tmp/ddata/Build/Products -name ESP32Car.app | head -1)"; xcrun simctl install booted "$APP"
```
Затем для индексов 0 (Connect), 5 (Firmware checking), 24 (Ramp), 25 (Trim), 22 (Calibration saving), 1 (NoInternet):
временно `@State private var index = N` в GalleryView, build, `xcrun simctl launch booted com.adamjohnson.esp32car --args -gallery`, скриншот. Откатить index=0.

- [ ] **Step 3: оценить и подправить.** Критерии: машинка одного размера и на одной вертикали при
  переключении; анимации (радар-кольца Connect, рельсы Ramp/Trim сверху, волны Firmware, кольца
  Calibration) **не обрезаны** рамкой и не наезжают на текст справа. Если на Ramp/Trim рельсы обрезаются
  сверху — увеличить высоту frame `RampCarView`/`TrimCarView` с 210 до 230. Если радар Connect/волны
  наезжают на текст — снизить общий scale (например 1.55) ОДИНАКОВО на всех пяти (держать единым).
  Внести правки и пересобрать до согласованного вида. Итоговый scale — один и тот же на всех пяти.

- [ ] **Step 4: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/ConnectView.swift ios/ESP32Car/RampView.swift ios/ESP32Car/TrimView.swift ios/ESP32Car/FirmwareCarView.swift ios/ESP32Car/CalibrationView.swift
git commit -m "feat(ios): unified car render size across split screens (single scaleEffect)"
```

---

## Task 3: Финальная проверка

- [ ] **Step 1:** прогон галереей по всем split-кадрам (Connect, Firmware ×неск. фаз, UpdateCheck, Ramp,
  Trim, Calibration ×неск., NoInternet) — машинка одного размера и центрирована; анимации целы. Скриншоты.
- [ ] **Step 2:** светлая тема (`xcrun simctl ui booted appearance light`) — беглый скриншот пары кадров;
  вернуть dark.
- [ ] **Step 3:** дерево чистое (index галереи откачен на 0); продакшн-запуск без `-gallery` — обычный
  флоу не сломан (Connect/Firmware/Drive рендерятся).

---

## Self-Review заметки

- **Покрытие спеки:** единый корпус 34×72 (T1 Ramp/Trim/Connect); центр машинки h/2 (T1 Canvas-виды;
  SwiftUI уже центрированы); значок NoInternet origin h/2 (T1); единый размер машинки через единый
  scaleEffect (T2, тюнинг по скриншотам, цель ~120pt); анимации не обрезаны/не наезжают (T2 Step 3 +
  T3); обе темы (T3). Drive-экран вне объёма (не split-с-текстом) — не трогаем.
- **Тип-консистентность:** константы `carW/carLen/wheelW/wheelH` в каждом Canvas-view; `scaleEffect`
  единое число на всех 5; `origin`/`center = size/2`.
- **Замечания:** scaleEffect меняет рендер, не layout — frame'ы остаются логическим холстом; overflow
  пустого холста безвреден, важно лишь чтобы ДРАЖИМОЕ (машинка+анимация) не наезжало на текст. Точный
  итоговый scale выбирается визуально (старт 1.6); держать одинаковым на всех пяти — это и есть «единый
  размер». Wheel 11×15 на Ramp/Trim перерисует шевроны автоматически (рисуются относительно rect колеса).
