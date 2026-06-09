# iOS: индикатор сигнала Wi-Fi (по пингу) — Design

**Дата:** 2026-06-09
**Статус:** дизайн утверждён (через визуальный компаньон), готов к плану

## Цель

Добавить индикатор «уровня сигнала» в верхний левый угол drive-экрана — 4 палочки, заменяющие
цветную точку в плашке связи.

## Важно (источник данных)

Реальный Wi-Fi RSSI на iOS публично недоступен (нужен платный entitlement «Access WiFi Information»).
Поэтому индикатор показывает **качество связи по пингу** (RTT до `/status`, который `CarStatus` уже меряет) —
честное «насколько хорошо/быстро отвечает машинка». Это не литеральный RSSI, но визуально читается как сигнал.

## Решение (стиль A)

Плашка связи в левом верхнем углу: **`▁▃▅▇ На связи · N мс`** — 4 восходящие палочки **вместо** точки.
Офлайн → пустые красные палочки + «Поиск…».

**Уровень (0–4) по пингу:**
| Условие | Уровень | Цвет |
|---|---|---|
| офлайн (`!online` или ping нет) | 0 | красный, все палки приглушены |
| ping ≥ 250 мс | 1 | янтарный (`warn`) |
| ping < 250 | 2 | зелёный (`accent`) |
| ping < 120 | 3 | зелёный |
| ping < 50 | 4 | зелёный |

Палочки выше уровня — приглушённые (`color.opacity(~0.18)`).

## Компоненты

| Файл | Изменение |
|---|---|
| `ios/ESP32Car/ControlModel.swift` | + чистая `signalLevel(online:pingMs:) -> Int` (0–4) + хост-тест |
| `ios/ESP32Car/SignalBars.swift` *(new)* | presentational `SignalBars(level:color:)` — 4 палочки |
| `ios/ESP32Car/DriveView.swift` | в плашке связи `Circle()`-точку → `SignalBars(level:color:)`; цвет из уровня |

### Чистая логика
```swift
static func signalLevel(online: Bool, pingMs: Int?) -> Int {
    guard online, let p = pingMs else { return 0 }
    if p < 50 { return 4 }
    if p < 120 { return 3 }
    if p < 250 { return 2 }
    return 1
}
```

### `SignalBars`
```swift
struct SignalBars: View {
    let level: Int   // 0...4
    let color: Color
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i <= level ? color : color.opacity(0.18))
                    .frame(width: 3, height: CGFloat(2 + i * 3))
            }
        }
        .frame(height: 14)
    }
}
```

### Плашка в `DriveView`
Заменить `Circle().fill(status.online ? p.accent : Color.orange).frame(8×8)` на:
```swift
let lvl = ControlModel.signalLevel(online: status.online, pingMs: status.pingMs)
let col: Color = lvl == 0 ? .red : (lvl == 1 ? p.warn : p.accent)
SignalBars(level: lvl, color: col)
```
(текст плашки `connected/searching` остаётся как есть).

## Тестирование

- **Хост-тест (нативно/симулятор):** `signalLevel` — офлайн→0; ping 10→4, 100→3, 200→2, 400→1.
- **Симулятор:** палочки в плашке (мок отвечает быстро → 4 зелёные); порог не подёргать без реального лага,
  но визуально палочки видны; обе темы.
- На устройстве пинг реальный → уровень меняется по качеству Wi-Fi.

## Вне объёма

- Реальный RSSI/SSID (платный entitlement).
- Графики/история пинга.
- Прошивка/протокол.
