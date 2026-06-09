# Калибровка — редизайн в конвенциях прошивки — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Переработать `CalibrationView` под стиль экрана обновления: машинка 1:1 как в прошивке + интерактивные цветные колёса, кольца-пульс по процессу, единый шаблон (сегменты · Заголовок · Подзаголовок · пилюли).

**Architecture:** Полный рерайт `CalibrationView` (логика spin/tap/direction/save сохранена) с новым `carDiagram` (опак-корпус + кольца через TimelineView + колёса-кнопки) и правым блоком по вычисляемому состоянию. Новые/обновлённые строки `calib.*`.

**Tech Stack:** Swift 6 / SwiftUI, TimelineView. Ветка `calib-redesign`. SDK `iphonesimulator26.2`, `iPhone 17`, мок `127.0.0.1:8080`.

---

## File Structure

| Файл | Изменение |
|---|---|
| `ios/ESP32Car/Resources/ru.lproj/Localizable.strings` | финальный набор `calib.*` |
| `ios/ESP32Car/L.swift` | аксессоры `calib.*` |
| `ios/ESP32Car/CalibrationView.swift` | полный рерайт (новый дизайн, логика та же) |

---

## Task 1: Строки + `L`

**Files:** Modify `ios/ESP32Car/Resources/ru.lproj/Localizable.strings`, `ios/ESP32Car/L.swift`.

- [ ] **Step 1: `Localizable.strings` — заменить устаревшие `calib.whichDir`/`calib.spinPrompt`/`calib.saveFailed`** на финальный набор. Delete:
```
"calib.whichDir"     = "Колесо %@ — куда крутилось?";
"calib.spinPrompt"   = "Крутится мотор %d — нажми на колесо, которое поехало.";
"calib.saveFailed"   = "Не удалось сохранить — повтори.";
```
Add (рядом с остальными `calib.*`):
```
"calib.spinSub"   = "Нажми «Крутить», затем колесо, которое поехало.";
"calib.wheel"     = "Колесо %@";
"calib.whichDir2" = "Куда оно крутилось?";
"calib.doneTitle" = "Готово";
"calib.saving"    = "Сохранение…";
"calib.savingSub" = "Записываю калибровку в машинку.";
"calib.failTitle" = "Не удалось";
"calib.failSub"   = "Проверь связь и повтори.";
"calib.retry"     = "Повторить";
```
(Оставить как есть: `calib.title`, `calib.step`, `calib.forward`, `calib.back`, `calib.spin`, `calib.allSet`, `calib.save`.)

- [ ] **Step 2: `L.swift` — удалить устаревшие** аксессоры:
```swift
    static var calibSaveFailed: String { s("calib.saveFailed") }
    static func calibWhichDir(_ wheel: String) -> String { s("calib.whichDir", wheel) }
    static func calibSpinPrompt(_ n: Int) -> String { s("calib.spinPrompt", n) }
```

- [ ] **Step 3: `L.swift` — добавить** (рядом с `calib*`):
```swift
    static var calibSpinSub: String { s("calib.spinSub") }
    static var calibWhichDir2: String { s("calib.whichDir2") }
    static var calibDoneTitle: String { s("calib.doneTitle") }
    static var calibSaving: String { s("calib.saving") }
    static var calibSavingSub: String { s("calib.savingSub") }
    static var calibFailTitle: String { s("calib.failTitle") }
    static var calibFailSub: String { s("calib.failSub") }
    static var calibRetry: String { s("calib.retry") }
    static func calibWheel(_ w: String) -> String { s("calib.wheel", w) }
```

- [ ] **Step 4: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/Resources ios/ESP32Car/L.swift
git commit -m "feat(ios): calibration strings (unified template, states)"
```

---

## Task 2: `CalibrationView` рерайт

**Files:** Modify `ios/ESP32Car/CalibrationView.swift` (full rewrite).

- [ ] **Step 1: Заменить весь файл на:**
```swift
import SwiftUI

struct CalibrationView: View {
    let palette: Palette
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var assign: [Corner: (pair: Int, sign: Int)] = [:]
    @State private var pending: Corner?
    @State private var saving = false
    @State private var failed = false
    private let client = CalibClient()

    private let metal = Color(red: 0.227, green: 0.188, blue: 0.141)  // #3a3024

    private enum CalState { case spin, direction, done, saving, failed }
    private var state: CalState {
        if saving { return .saving }
        if failed { return .failed }
        if pending != nil { return .direction }
        if step >= 4 { return .done }
        return .spin
    }
    private var ringsActive: Bool { state == .spin || state == .saving }
    private var p: Palette { palette }

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()
            HStack(spacing: 24) {
                carDiagram.frame(maxWidth: .infinity, maxHeight: .infinity)
                rightPanel.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        }
        .navigationTitle(L.calibTitle)
        .navigationBarTitleDisplayMode(.inline)
        .tint(p.accent)
    }

    // MARK: left — car (1:1 reference) + interactive wheels + pulse rings
    private var carDiagram: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let ringS = 1.0 + 0.07 * (0.5 + 0.5 * sin(t * 2 * .pi / 1.4))
            let glow = 0.5 + 0.5 * sin(t * 2 * .pi / 1.0)
            ZStack {
                if ringsActive {
                    ForEach(0..<3, id: \.self) { i in
                        Circle().stroke(p.accent, lineWidth: 1.5)
                            .frame(width: CGFloat(56 + i * 24), height: CGFloat(56 + i * 24))
                            .opacity([0.42, 0.24, 0.11][i])
                            .scaleEffect(ringS)
                    }
                }
                carBody
                ForEach(Corner.allCases, id: \.self) { wheelButton($0, glow: glow) }
            }
        }
        .scaleEffect(1.9)
        .frame(width: 200, height: 240)
    }

    private var carBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(p.bg)
                .overlay(RoundedRectangle(cornerRadius: 10).fill(p.panel))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(metal, lineWidth: 1))
                .frame(width: 34, height: 72)
            RoundedRectangle(cornerRadius: 3).fill(p.bg)
                .frame(width: 20, height: 8).offset(y: -25)
        }
    }

    private func wheelFill(_ c: Corner) -> Color {
        if state == .failed { return p.warn }
        if assign[c] != nil { return p.accent }
        if pending == c { return p.warn }
        return metal
    }
    private func wheelGlyph(_ c: Corner) -> String {
        if state == .failed { return "✕" }
        if assign[c] != nil { return "✓" }
        return ""
    }
    private func wheelButton(_ c: Corner, glow: Double) -> some View {
        Button { tap(c) } label: {
            Text(wheelGlyph(c))
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(p.bg)
                .frame(width: 11, height: 15)
                .background(RoundedRectangle(cornerRadius: 3).fill(wheelFill(c)))
                .shadow(color: pending == c ? p.warn.opacity(0.9) : .clear,
                        radius: pending == c ? 2 + 4 * glow : 0)
        }
        .buttonStyle(.plain)
        .disabled(assign[c] != nil || state == .saving || state == .failed)
        .offset(x: c.dx, y: c.dy)
    }

    // MARK: right — unified template
    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            segments
            switch state {
            case .spin:
                title(L.calibStep(min(step + 1, 4))); sub(L.calibSpinSub)
                pill(L.calibSpin, p.accent) { spin() }
            case .direction:
                if let c = pending {
                    title(L.calibWheel(c.label)); sub(L.calibWhichDir2)
                    HStack(spacing: 8) {
                        pill(L.calibForward, p.accent) { assignDir(1) }
                        pill(L.calibBack, p.warn) { assignDir(-1) }
                    }
                }
            case .done:
                title(L.calibDoneTitle); sub(L.calibAllSet)
                pill(L.calibSave, p.accent) { save() }
            case .saving:
                title(L.calibSaving); sub(L.calibSavingSub)
            case .failed:
                title(L.calibFailTitle); sub(L.calibFailSub)
                pill(L.calibRetry, p.accent) { failed = false; save() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var segments: some View {
        HStack(spacing: 5) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill((i <= step && step < 4) || i < step ? p.accent : p.line)
                    .frame(width: 26, height: 4)
                    .shadow(color: i == step && step < 4 ? p.accent.opacity(0.8) : .clear, radius: 4)
            }
        }
    }

    private func title(_ t: String) -> some View {
        Text(t).font(.system(size: 18, weight: .semibold)).foregroundStyle(p.text)
    }
    private func sub(_ t: String) -> some View {
        Text(t).font(.system(size: 12)).foregroundStyle(p.muted).fixedSize(horizontal: false, vertical: true)
    }
    private func pill(_ text: String, _ tint: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.15)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.55), lineWidth: 1))
        }
        .buttonStyle(.plain).padding(.top, 2)
    }

    // MARK: logic (unchanged behavior)
    private func spin() { Task { await client.spin(pair: step, dir: 1) } }
    private func tap(_ c: Corner) { guard assign[c] == nil else { return }; pending = c }
    private func assignDir(_ sign: Int) {
        guard let c = pending else { return }
        assign[c] = (pair: step, sign: sign)
        pending = nil
        step += 1
    }
    private func save() {
        saving = true; failed = false
        Task {
            let ok = await client.save(body: ControlModel.calibSaveBody(assign))
            saving = false
            if ok { dismiss() } else { failed = true }
        }
    }
}

private extension Corner {
    var label: String { rawValue.uppercased() }
    var dx: CGFloat { (self == .fl || self == .rl) ? -18.5 : 18.5 }
    var dy: CGFloat { (self == .fl || self == .fr) ? -20.5 : 20.5 }
}
```

- [ ] **Step 2: Regenerate + compile-check**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -8
echo "=== остатки старых calib-аксессоров? ===" && grep -rnE "calibWhichDir\b|calibSpinPrompt|calibSaveFailed" ESP32Car || echo "(нет)"
```
Expected: `** BUILD SUCCEEDED **`, grep `(нет)`.

- [ ] **Step 3: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/CalibrationView.swift
git commit -m "feat(ios): redesign calibration — 1:1 firmware car, interactive wheels, pulse rings, unified template"
```

---

## Task 3: Проверка в симуляторе

**Files:** (проверка — без изменений кода; форс-харнесс для saving/failed)

- [ ] **Step 1: Мок (calibrated=false → авто-открытие) + запуск**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/tools/mock_car
pkill -f mock_car.py 2>/dev/null; sleep 1; nohup .venv/bin/python -u mock_car.py > /tmp/mock_car.log 2>&1 & disown; sleep 2
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios
xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | grep -iE "BUILD SUCCEEDED|FAILED" | head -1
xcrun simctl install booted "$(find /tmp/ddata/Build/Products -name ESP32Car.app | head -1)"
xcrun simctl terminate booted com.adamjohnson.esp32car 2>/dev/null
xcrun simctl launch booted com.adamjohnson.esp32car
xcrun simctl io booted screenshot /tmp/calib_spin.png
```
Проверить spin-экран: машинка 1:1 как в прошивке (тот же размер), кольца пульсируют, колёса idle тёмные; правый блок «Шаг 1 из 4 / подсказка / Крутить».

- [ ] **Step 2: Форс-харнесс для остальных состояний** — временно в `ESP32CarApp.swift` корень → `NavigationStack { CalibrationView(palette: Theme.dark) }`; в `CalibrationView` форсить `@State private var step = 1` + `pending`/`saving`/`failed` поочерёдно, билдить + скриншот: direction (янтарное колесо), done (все ✓), saving (кольца пульс), failed (✕ на колёсах). Затем **откатить харнесс** (`grep -rn "TEMP" ios/ESP32Car` → нет; build SUCCEEDED).

- [ ] **Step 3: Полный прогон в симуляторе** — пройти spin→tap колесо→Вперёд/Назад ×4 → done → Сохранить (мок принимает → закрытие). Обе темы.

---

## Self-Review заметки

- **Покрытие спеки:** машинка 1:1 (`carBody` 34×72 опак + offsets ±18.5/±20.5, scaleEffect 1.9) (Task 2); интерактивные колёса idle/pending/assigned/failed-✕ (`wheelFill`/`wheelGlyph`); кольца-пульс при spin/saving (`ringsActive` + TimelineView); единый шаблон сегменты/Title/Subtitle/пилюли (rightPanel); состояния spin/direction/done/saving/failed (`state`); строки (Task 1).
- **Тип-консистентность:** `CalState`; `Corner.dx/dy/label`; `L.calib*` (новый набор, `calibWheel`/`calibStep` функции); `CalibClient.spin/save`, `ControlModel.calibSaveBody`; `p.accent/warn/panel/bg/line/text/muted`.
- **Тесты:** чистой логики нет; проверка — сборка + скриншоты (Task 3).
- **Замечания:** `failed` заменил `errMsg` (булев флаг состояния). Тап-зона колёс = 11×15 ×1.9 ≈ 21×29 (ок). Пульс pending-колеса и колец — через TimelineView (работают всегда). `pending!` исключён (через `if let`).
```
