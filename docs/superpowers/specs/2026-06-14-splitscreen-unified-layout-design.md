# Единый `SplitScreen` — выравнивание контента на всех сплит-экранах

**Дата:** 2026-06-14
**Статус:** утверждён, готов к плану

## Проблема

Сплит-экраны приложения (машинка слева + текст справа) центрируют контент
по-разному в зависимости от того, обёрнуты ли они в `NavigationStack` с
системным заголовком:

- **Без нав-бара** (контент центрируется по safe-area = почти по всему экрану):
  `NoInternetView`, `ConnectView`, `UpdateCheckView`, `DriveView`.
- **С системным нав-баром** (его top-инсет сдвигает контент вниз):
  `FirmwareView` (forced-гейт обёрнут в `NavigationStack`), `CalibrationView`,
  `RampView`, `TrimView` (пушатся из `SettingsView`).

Из-за инсета нав-бара у второй группы машинка+текст сидят ниже. Вдобавок
`CalibrationView` показывается в двух разных контекстах (push из Settings — с
баром; голый `.sheet` авто-промпт — без бара), т.е. даже сам с собой не
консистентен.

Каждый экран ещё и дублирует один и тот же боллерплейт:
`ZStack { bg.ignoresSafeArea(); HStack(spacing:24) { left.frame(maxWidth:.infinity,maxHeight:.infinity); right.frame(...,alignment:.leading) }.frame(maxWidth:.infinity,maxHeight:.infinity).padding(20) }`.

## Решение

Вынести общий layout в один дженерик-контейнер `SplitScreen`, который:
1. центрирует контент в safe-area одинаково везде;
2. **гасит системный нав-бар** в любом контексте (`.toolbar(.hidden, for: .navigationBar)`),
   поэтому ни у кого нет нав-бар-инсета → центрирование автоматически идентично;
3. опционально рисует **свой** заголовок (и шеврон «назад») в фиксированной
   позиции сверху, поверх контента.

### Компонент `SplitScreen.swift` (новый файл)

```swift
import SwiftUI

/// Shared split layout: car/graphic on the left, text panel on the right, centred
/// identically on every screen. Suppresses the system nav bar so no screen gets a
/// nav-bar inset (the source of the vertical misalignment); draws an optional custom
/// header (back chevron + title) as a top overlay instead.
struct SplitScreen<Left: View, Right: View>: View {
    let palette: Palette
    var title: String? = nil
    var onBack: (() -> Void)? = nil
    @ViewBuilder var left: () -> Left
    @ViewBuilder var right: () -> Right

    private var p: Palette { palette }

    var body: some View {
        ZStack(alignment: .topLeading) {
            p.bg.ignoresSafeArea()
            HStack(spacing: 24) {
                left().frame(maxWidth: .infinity, maxHeight: .infinity)
                right().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
            if title != nil || onBack != nil { header }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(p.accent)
                }.buttonStyle(.plain)
            }
            if let title {
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(p.text)
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.top, 12)
    }
}
```

Заметки:
- `.toolbar(.hidden, for: .navigationBar)` на вью вне `NavigationStack` — no-op,
  поэтому безопасно применять всегда (и для гейт-экранов).
- Header в safe-area (не игнорирует её), top-leading — не уезжает под вырез в
  ландшафте. Контент центрирован, его верхняя зона пуста → header не пересекается
  с машинкой/текстом.
- `Left`/`Right` — `@ViewBuilder`, чтобы передавать любые вью (включая
  интерактивную диаграмму калибровки).

### Рефактор экранов (тело → `SplitScreen`)

Везде убираем дублирующий `ZStack/HStack/bg/padding` боллерплейт.

- **`NoInternetView`** — `SplitScreen(palette: p) { NoInternetCarView(palette: p) } right: { <текущий VStack: title/sub/retry> }`. `title=nil`.
- **`ConnectView`** — `SplitScreen(palette: p) { ConnectCarView(palette: p) } right: { rightPanel }`. `title=nil`.
- **`UpdateCheckView`** — `SplitScreen(palette: p) { FirmwareCarView(phase: fwPhase, palette: p) } right: { <текущий phase-VStack> }`. `title=nil`.
- **`FirmwareView`** — добавить `@Environment(\.dismiss) private var dismiss`. Тело:
  `SplitScreen(palette: p, title: L.settingsFirmware, onBack: forced ? nil : { dismiss() }) { FirmwareCarView(phase: phase, palette: p) } right: { stateBlock }`.
  Снять `.navigationTitle/.navigationBarTitleDisplayMode/.tint` (инлайновые
  `.tint` у `ProgressView` остаются). Остальные модификаторы (`.task`/`.onChange`/
  `.onAppear` и т.п.) переносятся на `SplitScreen`.
- **`CalibrationView`** — добавить свойство `var dismissible: Bool = true`. Тело:
  `SplitScreen(palette: p, title: L.calibTitle, onBack: dismissible ? { dismiss() } : nil) { carDiagram } right: { rightPanel }`.
  Снять `.navigationTitle/.navigationBarTitleDisplayMode/.tint`. Сохранить
  `.onAppear` (seeding debugState). `dismiss` уже есть.
- **`RampView`** — добавить `@Environment(\.dismiss)`. Тело:
  `SplitScreen(palette: p, title: L.rampTitle, onBack: { dismiss() }) { RampCarView(rampMs: demoMs, palette: p) } right: { rightPanel }`.
  Снять `.navigationTitle/.navigationBarTitleDisplayMode/.tint` (инлайновый
  `.tint` слайдера остаётся). Сохранить `.task`.
- **`TrimView`** — аналогично Ramp: `title: L.trimTitle`, `onBack: { dismiss() }`,
  `left: TrimCarView`, `right: rightPanel`. Снять nav-модификаторы, сохранить `.task`.

### Правки точек показа

- **`ESP32CarApp.root` → `case .updateRequired`**: убрать обёртку
  `NavigationStack { ... }`, показывать `FirmwareView(palette: p, forced: true, onDone: { flow.updateFinished() }, status: status)` напрямую (с `.onAppear { conn.start(); status.start() }`).
- **`DriveView` авто-промпт калибровки** (`.sheet(isPresented: $showCalib)`):
  передавать `CalibrationView(palette: p, dismissible: false)` (обязательная
  калибровка — без «назад»).
- **`SettingsView`**: push Calibration/Ramp/Trim/Firmware через `NavigationStack`+
  `List` остаётся (механика навигации). Дочерние экраны теперь сами прячут бар и
  рисуют свой header+«назад» (`dismiss()` корректно делает pop). Сам `SettingsView`
  (корень своего `NavigationStack`) свой бар (`.navigationTitle` + кнопка
  «Закрыть») **сохраняет** — это не `SplitScreen`.
- **`GalleryView`**: обёртки `NavigationStack { FirmwareView }` / `NavigationStack
  { CalibrationView }` можно оставить — `SplitScreen` всё равно гасит бар; но для
  чистоты убрать `NavigationStack` вокруг `fw()`/`calib()` (необязательно для
  корректности).

## Файлы

- **Создать:** `ios/ESP32Car/SplitScreen.swift`.
- **Изменить:** `NoInternetView.swift`, `ConnectView.swift`, `UpdateCheckView.swift`,
  `FirmwareView.swift`, `CalibrationView.swift`, `RampView.swift`, `TrimView.swift`,
  `ESP32CarApp.swift`, `DriveView.swift`. (`GalleryView.swift` — опционально.)

## Тестирование

- Сборка под симулятор: `xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata`.
- Галерея (`--args -gallery`): пролистать сплит-кадры (NoInternet, UpdateCheck,
  Firmware *, Calibration *, Ramp, Trim, Connect). Критерий: машинка+правый текст
  на одной и той же высоте на всех кадрах; у титульных экранов сверху-слева header
  (заголовок, при наличии — шеврон). Обе темы (`xcrun simctl ui booted appearance light|dark`).
- Проверить навигацию в реальном флоу не требуется на этом шаге (визуальная
  верификация через галерею); back/dismiss — это существующий `dismiss()`.
- Чистые host-тестируемые модули не затронуты — host-тесты без изменений.

## Вне объёма

- `DriveView` (своя раскладка, не сплит) — не трогаем.
- Анимации, тексты локализации, цвета, геометрия машинок — без изменений.
- Рефакторинг геометрии машинок в общий компонент (отдельная задача).
