# «Нет интернета» — редизайн графики (машинка + Wi-Fi-глиф)

**Дата:** 2026-06-14
**Статус:** утверждён, готов к плану

## Проблема

Экран `NoInternetView` (фаза `AppFlow.noInternet`) сейчас показывает слева
одиночный пульсирующий Wi-Fi-значок (`WifiGlyph`, Canvas с янтарными дугами).
Он визуально выбивается из остальных split-экранов приложения
(Connect / Firmware / Ramp / Trim / Calibration), которые все построены вокруг
одной и той же машинки-референса. Нужно привести «Нет интернета» к тому же
визуальному языку.

## Решение

Заменить `WifiGlyph` на машинку-референс с янтарным Wi-Fi-глифом на кузове и
пульсирующими янтарными волнами — ровно как `FirmwareCarView` (3-й экран), но в
янтаре (`palette.warn`) вместо зелёного акцента.

Новый внутренний `struct NoInternetCarView` в `NoInternetView.swift`. Правая
колонка (заголовок / подсказка / пилюля «Повторить») и вся логика экрана —
**без изменений**.

### Композиция `NoInternetCarView`

Слой за слоем (ZStack, снизу вверх):

1. **Волны** — 3 концентрических кольца (диаметры `[56, 80, 104]`), янтарные
   (`palette.warn`), пульсируют: непрерывная анимация через `TimelineView(.animation)`,
   синусоидальное изменение **размера кольца через `frame`** (НЕ `.scaleEffect` —
   иначе каждое кольцо становится отдельным слоем композитинга и рисуется ПОВЕРХ
   машинки; тот же баг, что чинили в калибровке). Кольца — под машинкой.
   Базовые непрозрачности `[0.42, 0.24, 0.11]`, период ~1.4 с.
2. **Машинка-референс** — идентична `FirmwareCarView.car` по геометрии:
   - корпус `RoundedRectangle(cornerRadius:10)` 34×72: `fill(bg)` →
     `overlay(fill(panel))` → `overlay(stroke(metal, lineWidth:1))` (непрозрачный,
     чтобы перекрывать кольца под собой);
   - лобовое `RoundedRectangle(cornerRadius:3).fill(bg)` 20×8, `offset(y:-25)`;
   - 4 тёмных колеса `RoundedRectangle(cornerRadius:3).fill(metal)` 11×15 по углам
     (`offset(x: ±18.5, y: ±20.5)`), поверх корпуса — как в референсе.
3. **Чип-глиф** на кузове (по центру, 20×20), янтарный:
   - `RoundedRectangle(cornerRadius:5).fill(bg)` →
     `overlay/fill(warn.opacity(0.18))` → `stroke(warn, lineWidth:1)`;
   - `Image(systemName: "wifi.exclamationmark").font(.system(size:11, weight:.bold)).foregroundStyle(warn)`;
   - `shadow(color: warn.opacity(0.55), radius: 5)`.

Обёртка: `.scaleEffect(1.6).frame(width:200, height:240)` — тот же размер и
центрирование, что у Firmware / Calibration. Машинка получается ~120 pt, на
одной линии с остальными экранами.

### Что НЕ меняем

- Тексты (`L.gateNoInternetTitle`, `L.gateNoInternetSub`), пилюля `L.fwRetry`,
  янтарный тон пилюли — как сейчас.
- `FirmwareCarView` не трогаем (новый view отдельный, чтобы не усложнять
  phase-driven компонент и не плодить зависимость от `FwPhase`).
- Логику `NoInternetView` / `AppFlow` / сетевые проверки — без изменений.
- Никаких новых строк локализации (используется существующий SF Symbol +
  существующие `L.*`).

## Файлы

- **Изменяем:** `ios/ESP32Car/NoInternetView.swift` — удалить `struct WifiGlyph`,
  добавить `struct NoInternetCarView`, подставить его в левую половину
  `NoInternetView`.

## Тестирование

- Сборка под симулятор: `xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64`.
- Визуально через галерею: `xcrun simctl launch booted com.adamjohnson.esp32car --args -gallery`,
  кадр «No Internet» (1-й) — машинка с янтарным `wifi.exclamationmark` и пульсом;
  размер/центр совпадают с соседними экранами; волны под машинкой, не над.
- Обе темы (`xcrun simctl ui booted appearance light|dark`).
- Это чисто визуальный SwiftUI-компонент без чистой логики — host-тестов нет
  (как у других `*CarView`).

## Вне объёма

- Анимация появления/исчезновения экрана.
- Изменение текстов или поведения «Повторить».
- Рефакторинг общей машинки-референса в один shared-компонент (6 экранов сейчас
  дублируют геометрию; объединение — отдельная задача, здесь не делаем).
