# iOS: переосмысление нижней строки статуса — Design

**Дата:** 2026-06-09
**Статус:** дизайн утверждён (через визуальный компаньон), готов к плану

## Цель

Сделать нижнюю строку статуса на drive-экране понятнее: вместо `вкл 1283 с · калибр ✓ · ПО mock` —
три элемента «иконка + значение» с человеко-читаемым аптаймом.

## Решение (стиль B)

Три инлайн-элемента (SF Symbol + текст), мелким приглушённым, через равные отступы:
- **⏱ `clock`** — аптайм человеческий: `45 с` / `21 мин` / `3 ч 5 мин` / `2 дн` (или `—` если нет данных);
- **✓ `checkmark.circle.fill` (accent)** `откалибрована` / **✗ `xmark.circle` (warn)** `не откалибрована`;
- **▣ `cpu`** — версия ПО (`1.0` / `mock`; `—` если нет).

## Изменения

### `L.swift` + `ru.lproj/Localizable.strings`
- **Добавить** ключи:
  ```
  "uptime.sec"     = "%d с";
  "uptime.min"     = "%d мин";
  "uptime.hourMin" = "%d ч %d мин";
  "uptime.day"     = "%d дн";
  "drive.calibratedYes" = "откалибрована";
  "drive.calibratedNo"  = "не откалибрована";
  ```
- **Добавить** в `enum L`:
  ```swift
  static var driveCalibratedYes: String { s("drive.calibratedYes") }
  static var driveCalibratedNo: String { s("drive.calibratedNo") }
  static func uptime(_ sec: Int) -> String {
      if sec < 60 { return s("uptime.sec", sec) }
      if sec < 3600 { return s("uptime.min", sec / 60) }
      if sec < 86400 { return s("uptime.hourMin", sec / 3600, (sec % 3600) / 60) }
      return s("uptime.day", sec / 86400)
  }
  ```
- **Удалить** устаревшие (использовались только в старой строке): ключи `drive.uptime`, `drive.uptimeUnknown`,
  `drive.calibYes`, `drive.calibNo`, `drive.fw`, `drive.fwUnknown` и соответствующие аксессоры
  `L.driveUptime`/`driveUptimeUnknown`/`driveCalibYes`/`driveCalibNo`/`driveFw`/`driveFwUnknown`.
  (Ключи `drive.connected`/`drive.searching`/`drive.sideLeft`/`drive.sideRight` — остаются.)

### `DriveView.swift`
- Удалить computed `statusLine` (String) и заменить нижний `Text(statusLine)…` на `statusBar`:
  ```swift
  private var statusBar: some View {
      HStack(spacing: 16) {
          statusItem("clock", status.uptimeS.map { L.uptime($0) } ?? "—", p.muted)
          let ok = status.calibrated ?? false
          statusItem(ok ? "checkmark.circle.fill" : "xmark.circle",
                     ok ? L.driveCalibratedYes : L.driveCalibratedNo,
                     ok ? p.accent : p.warn)
          statusItem("cpu", status.fw ?? "—", p.muted)
      }
      .font(.system(size: 10))
  }
  private func statusItem(_ icon: String, _ text: String, _ color: Color) -> some View {
      HStack(spacing: 4) {
          Image(systemName: icon).foregroundStyle(color.opacity(0.85))
          Text(text).foregroundStyle(color)
      }
  }
  ```
  В нижнем `VStack` использовать `statusBar` вместо `Text(statusLine)…`.

## Тестирование

- **Сборка:** `xcodebuild` под симулятор-SDK.
- **Симулятор (против мока):** нижняя строка — `⏱ 21 мин · ✓ откалибрована · ▣ mock` (иконки SF Symbols);
  при `calibrated=false` — `✗ не откалибрована` янтарным; аптайм человеческий; нет сырых ключей; обе темы.
- Логика порога аптайма простая (3 ветки), проверяется визуально; отдельный юнит-тест не нужен (тривиально).

## Вне объёма

- Свободная память (heap) в строке — отклонена.
- Множественное число (минута/минуты) — используем аббревиатуры (с/мин/ч/дн).
- Прошивка/протокол.
