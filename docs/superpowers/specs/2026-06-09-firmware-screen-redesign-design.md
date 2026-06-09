# Экран обновления — редизайн в формат калибровки — Design

**Дата:** 2026-06-09
**Статус:** дизайн утверждён (визуальный компаньон), готов к плану

## Цель

Привести `FirmwareView` к формату экрана калибровки (split-layout, центрирование «вариант C»): **слева —
картинка машинки** (вид сверху + чип + волны OTA), **справа — блок состояния** (версии / прогресс / кнопки).
Покрыть все состояния потока обновления, добавить кнопку «Проверить» и состояние «Актуальна».

## Раскладка (как калибровка, вариант C)

```
[ Прошивка ]  (nav title, inline)
┌─────────────┬──────────────────┐
│   машинка   │  блок состояния  │
│ (центр лев. │ (верт. центр,    │
│  половины)  │  текст слева)    │
└─────────────┴──────────────────┘
```
HStack на всю высоту: левая половина — `FirmwareCarView` (`maxWidth/maxHeight:.infinity`, центр);
правая — VStack состояния (`maxWidth/maxHeight:.infinity, alignment:.leading`).

## Левая картинка — `FirmwareCarView` *(new)*

Вид сверху (как в калибровке: скруглённый корпус + лобовое + 4 колеса нейтральным цветом), **в центре чип**
(`▣`, accent, лёгкое свечение), вокруг — **3 концентрические волны OTA**. Управляется `phase`:
- покой/инфо/скачивание (`checking/upToDate/available/downloading/downloaded`): волны **бледные** (faint).
- **`uploading`**: волны **яркие + анимированы** (расходятся, repeatForever) — «данные по воздуху в машинку».
- `rebooting`: чуть притушить (dim).
- `done`: чип → `✓` с усиленным свечением (accent).
- `failed`: чип → `!` в `warn`-цвете.
Без интерактива (в отличие от калибровки — там кнопки-колёса). Чистая презентация.

## Правая часть — состояния (`phase`)

Машина состояний (расширяет текущую `idle/downloading/downloaded/uploading/rebooting/done/failed`):
`checking → upToDate | available → downloading → downloaded → uploading → rebooting → done` (+ `failed` на любом шаге).

| Состояние | Контент справа |
|---|---|
| **checking** | `Текущая: <fw>` · `◌ Проверяю обновления…` |
| **upToDate** | `Текущая: <fw>` · `✓ Прошивка актуальна` (accent) · кнопка `↻ Проверить снова` (ghost) |
| **available** | `Текущая: <fw>` · `Доступно: <tag>` (accent) · кнопка `⬇ Обновить` (prominent) |
| **downloading** | `<fw> → <tag>` · `Скачиваю с GitHub…` · прогресс-бар |
| **downloaded** | `✓ Скачано <tag>` · `Подключись к Wi-Fi ESP32-Car` (warn) · кнопка `⚡ Залить` (неактивна, пока `!status.online`) |
| **uploading** | `Заливаю <tag>…` · прогресс-бар (`client.uploadProgress`) · `NN%` |
| **rebooting** | `◌ Перезагрузка машинки…` · `жду возврата на связь` (muted) |
| **done** | `✓ Готово` (accent) · `Версия: <fw>` · кнопка `Закрыть` (ghost, dismiss) |
| **failed** | `✗ Не удалось` (warn) · `проверь связь и повтори` · кнопка `↻ Повторить` (prominent) |

## Логика переходов

- **Вход:** `.task` → `phase=.checking` → `latestRelease()`; затем сравнение `normalize(tag)` vs `normalize(status.fw)`
  → `.available` или `.upToDate`. (Сейчас проверка уже на `.task` — добавляем явные `.checking/.upToDate`.)
- **`↻ Проверить снова`** (в `upToDate`/`failed`): снова `phase=.checking` → `latestRelease()` → пересравнение.
- **`⬇ Обновить`** (в `available`): `phase=.downloading` → `download()` → `.downloaded` (или `.failed`).
- **`⚡ Залить`** (в `downloaded`, активна при `status.online`): `phase=.uploading` → `upload()` →
  `.rebooting` → опрос `status.online` (видели offline → online) → `.done` (или `.failed` по таймауту).
- **`↻ Повторить`** (в `failed`): вернуться к разумному шагу — заново `latestRelease()` (`.checking`).
- **`Закрыть`** (в `done`): `dismiss()`.

`UpdateClient` (GitHub latest / download / upload+progress / normalize) — **без изменений**.

## Строки (`L` + `ru.lproj`)

Существуют: `fw.current %@`, `fw.latest %@`, `fw.upToDate`, `fw.connectCar`, `fw.flash`, `fw.uploading`,
`fw.rebooting`, `fw.failed`, `fw.done`, `settings.firmware`. Добавить:
```
"fw.checking"      = "Проверяю обновления…";
"fw.recheck"       = "Проверить снова";
"fw.update"        = "Обновить";
"fw.downloadingGh" = "Скачиваю с GitHub…";
"fw.downloaded"    = "Скачано %@";
"fw.rebootWait"    = "жду возврата на связь";
"fw.version"       = "Версия: %@";
"fw.retry"         = "Повторить";
```
(Старые `fw.download`/`fw.connectCar` оставить/переиспользовать; «Закрыть» = `common.close`.) Никаких
кириллических литералов во вью.

## Компоненты

| Файл | Изменение |
|---|---|
| `ios/ESP32Car/FirmwareCarView.swift` *(new)* | левая картинка (car+chip+waves), phase-driven |
| `ios/ESP32Car/FirmwareView.swift` | split-layout + расширенная машина состояний + переходы |
| `ios/ESP32Car/L.swift` + `ru.lproj/Localizable.strings` | +8 ключей `fw.*` |

## Тестирование

- Компиляция для `iphonesimulator26.2`.
- Симулятор: пройти состояния — `upToDate` (мок `calibrated`/версия совпадает), `available` (есть релиз новее),
  скачивание/заливка на мок (`/ota`), `done`; скриншоты обеих тем; центрирование как в калибровке.

## Вне объёма

- Изменения `UpdateClient`/протокола/прошивки.
- Реальный OTA на устройстве (отдельно, уже в OTA-плане).
