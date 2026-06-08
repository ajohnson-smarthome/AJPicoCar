# Редизайн экрана калибровки — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Переписать вид `CalibrationView` в сплит-раскладку (машинка слева, шаги/действия справа) с сегмент-прогрессом, пульсом «крутится» и пилюлями направления — логика и протокол без изменений.

**Architecture:** Один файл `ios/ESP32Car/CalibrationView.swift`: `body` → `HStack` [машинка | правая панель]. Состояние/`CalibClient`/`calibSaveBody` те же. Тёплая `Palette`, SF Symbols.

**Tech Stack:** Swift 6 / SwiftUI. Ветка `ios-calib-redesign`. Симулятор-SDK `iphonesimulator26.2`, устройство `iPhone 17`, мок на `127.0.0.1:8080`.

---

## File Structure

| Файл | Ответственность |
|---|---|
| `ios/ESP32Car/CalibrationView.swift` | сплит-раскладка мастера калибровки (вид); логика без изменений |

---

## Task 1: Переписать `CalibrationView.swift`

**Files:** Modify `ios/ESP32Car/CalibrationView.swift` (полная замена содержимого).

- [ ] **Step 1: Заменить `ios/ESP32Car/CalibrationView.swift` целиком**
```swift
import SwiftUI

struct CalibrationView: View {
    let palette: Palette
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var assign: [Corner: (pair: Int, sign: Int)] = [:]
    @State private var pending: Corner?
    @State private var saving = false
    @State private var errMsg: String?
    @State private var pulse = false
    private let client = CalibClient()

    private var identifying: Bool { pending == nil && step < 4 }

    var body: some View {
        ZStack {
            palette.bg.ignoresSafeArea()
            HStack(spacing: 20) {
                carPanel
                rightPanel
            }
            .padding(20)
        }
        .navigationTitle("Калибровка")
        .navigationBarTitleDisplayMode(.inline)
        .tint(palette.accent)
        .onAppear {
            withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) { pulse = true }
        }
    }

    // MARK: left — car + pulse
    private var carPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .stroke(palette.warn, lineWidth: 3)
                .frame(width: 130, height: 170)
                .scaleEffect(pulse ? 1.18 : 0.9)
                .opacity(identifying ? (pulse ? 0 : 0.5) : 0)
                .animation(.easeOut(duration: 1.1).repeatForever(autoreverses: false), value: pulse)
            carDiagram
        }
        .frame(maxWidth: .infinity)
    }

    private var carDiagram: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13).fill(palette.panel)
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(palette.line))
                .frame(width: 64, height: 98)
            RoundedRectangle(cornerRadius: 4).fill(palette.bg.opacity(0.7))
                .frame(width: 34, height: 12).offset(y: -31)
            ForEach(Corner.allCases, id: \.self) { wheelButton($0) }
        }
        .scaleEffect(1.4)
        .frame(width: 130, height: 170)
    }

    private func wheelButton(_ c: Corner) -> some View {
        let assigned = assign[c] != nil
        let isPending = pending == c
        let fill = assigned ? palette.accent : (isPending ? palette.warn : palette.idleWheel)
        return Button { tap(c) } label: {
            Text(assigned ? "✓" : c.label)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 22, height: 32)
                .background(fill)
                .foregroundStyle(palette.bg)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .shadow(color: isPending ? palette.warn.opacity(0.9) : .clear, radius: 6)
        }
        .disabled(assigned)
        .offset(x: c.dx, y: c.dy)
    }

    // MARK: right — steps / actions
    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            segments
            Text("Шаг \(min(step + 1, 4)) из 4").font(.headline).foregroundStyle(palette.text)

            if let c = pending {
                Text("Колесо \(c.label) — куда крутилось?")
                    .font(.subheadline).foregroundStyle(palette.muted)
                HStack(spacing: 10) {
                    Button { assignDir(1) } label: { Label("вперёд", systemImage: "arrow.up") }
                        .buttonStyle(.bordered).tint(palette.accent)
                    Button { assignDir(-1) } label: { Label("назад", systemImage: "arrow.down") }
                        .buttonStyle(.bordered).tint(palette.warn)
                }
            } else if step < 4 {
                Text("Крутится мотор \(step + 1) — тапни колесо, которое поехало.")
                    .font(.subheadline).foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button { spin() } label: { Label("Spin", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).tint(palette.accent)
            } else {
                Text("Все колёса размечены.").font(.subheadline).foregroundStyle(palette.muted)
                Button { save() } label: { Label("Save", systemImage: "checkmark") }
                    .buttonStyle(.borderedProminent).tint(palette.accent).disabled(saving)
            }

            if let e = errMsg {
                Text(e).font(.caption).foregroundStyle(palette.warn)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var segments: some View {
        HStack(spacing: 5) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i <= step && step < 4 || i < step ? palette.accent : palette.line)
                    .frame(width: 28, height: 4)
                    .shadow(color: i == step && step < 4 ? palette.accent.opacity(0.8) : .clear, radius: 4)
            }
        }
    }

    // MARK: logic (unchanged behavior)
    private func spin() {
        errMsg = nil
        Task { await client.spin(pair: step, dir: 1) }
    }
    private func tap(_ c: Corner) {
        guard assign[c] == nil else { return }
        pending = c
    }
    private func assignDir(_ sign: Int) {
        guard let c = pending else { return }
        assign[c] = (pair: step, sign: sign)
        pending = nil
        step += 1
    }
    private func save() {
        saving = true
        errMsg = nil
        Task {
            let ok = await client.save(body: ControlModel.calibSaveBody(assign))
            saving = false
            if ok { dismiss() } else { errMsg = "Сохранение не прошло — повтори." }
        }
    }
}

private extension Corner {
    var label: String { rawValue.uppercased() }
    var dx: CGFloat { (self == .fl || self == .rl) ? -48 : 48 }
    var dy: CGFloat { (self == .fl || self == .fr) ? -40 : 40 }
}
```

- [ ] **Step 2: Regenerate + compile-check**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios && xcodegen generate && xcodebuild build -target ESP32Car -sdk iphonesimulator26.2 ARCHS=arm64 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head -8
```
Expected: `** BUILD SUCCEEDED **`. Fix any Swift errors (candidate: the `segments` fill ternary precedence — wrap in parens if the compiler complains) and rebuild.

- [ ] **Step 3: Commit**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add ios/ESP32Car/CalibrationView.swift
git commit -m "feat(ios): redesign CalibrationView — split layout, segments, pulse, direction pills"
```

---

## Task 2: Проверка в симуляторе

**Files:** (проверка — без изменений кода)

- [ ] **Step 1: Перезапустить мок (calibrated=false) + запустить апп**
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car/tools/mock_car
pkill -f mock_car.py 2>/dev/null; sleep 1
nohup .venv/bin/python -u mock_car.py > /tmp/mock_car.log 2>&1 & disown
cd /Users/adamjohnson/VSCode/esp32-p4-car/ios
xcodebuild build -scheme ESP32Car -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/ddata 2>&1 | grep -iE "BUILD SUCCEEDED|FAILED" | head -1
xcrun simctl install booted "$(find /tmp/ddata/Build/Products -name ESP32Car.app | head -1)"
xcrun simctl terminate booted com.adamjohnson.esp32car 2>/dev/null
xcrun simctl launch booted com.adamjohnson.esp32car
```

- [ ] **Step 2: Визуально**
- авто-лист «Калибровка» в сплит-виде: слева машинка с пульсом, справа сегменты + «Шаг 1 из 4» + инструкция + Spin;
- Spin → лог `calib/spin: 0,1`; тап колеса → янтарь + пилюли «вперёд/назад»; выбор → ✓, сегмент закрашивается, шаг++;
- после 4 → «Все колёса размечены» + Save → `calib/save` → закрытие;
- переключить тему симулятора → обе темы читаемы.
Скриншот: `xcrun simctl io booted screenshot /tmp/calib2.png`.

- [ ] **Step 3: На устройстве (с пользователем, позже)** — реальная калибровка на iPhone.

---

## Self-Review заметки

- **Покрытие спеки:** сплит-раскладка (Step 1: `HStack` car/right); сегмент-прогресс (`segments`); пульс «крутится» (`carPanel`, `identifying`); пилюли направления (`pending`-ветка правой панели); состояния колёс (idle/warn/accent ✓); тёплая тема (`palette`), SF Symbols.
- **Тип-консистентность:** логика/имена те же — `step`/`assign`/`pending`/`saving`/`CalibClient.spin/save`/`ControlModel.calibSaveBody`/`Corner` (`dx`/`dy`/`label` локальное extension). `Palette.warn`/`accent`/`idleWheel`/`panel`/`line`/`bg` — существуют.
- **Тесты:** новой чистой логики нет (`calibSaveBody` уже покрыт); вид — визуально в симуляторе (Task 2).
- **Замечания:** пульс — `pulse` тоглится один раз `onAppear` с `repeatForever`, кольцо всегда в дереве, видимость по `identifying` (надёжный непрерывный пульс). Константы (масштаб машинки, dx/dy, размеры) — подбор на глаз в симуляторе.
