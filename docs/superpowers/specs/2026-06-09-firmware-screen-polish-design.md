# Экран обновления — однородность текстов/иконок + анимации по процессу — Design

**Дата:** 2026-06-09
**Статус:** дизайн утверждён (визуальный компаньон), готов к плану

## Цель

Привести все 9 состояний экрана обновления к **единому лаконичному шаблону** (Заголовок · Подзаголовок · бар/кнопка),
свести иконки состояния в **чип машинки**, и сделать **анимацию строго по процессу** (ожидание → пульс, иначе статика/нет волн).
Раскладка (split-layout калибровки) — без изменений.

## Единый правый блок

У каждого состояния: **Заголовок** (15pt, `text`) · **Подзаголовок** (11pt, `muted`, версия чуть светлее) · затем **бар** или **кнопка** (или ничего). Иконок ✓/✗ в тексте больше нет — их несёт чип. Версии **везде с `v`** — показываем сырые `status.fw` и `release.tag` (на устройстве это `vX.Y` из git-тега; мок отдаёт `mock`), без обрезки/добавления.

| Состояние | Заголовок | Подзаголовок | Действие |
|---|---|---|---|
| checking | Проверка обновлений… | Текущая `<fw>` | — |
| upToDate | Актуальная версия | Версия `<fw>` | кнопка «Проверить снова» (ghost) |
| available | Доступно обновление | `<fw> → <tag>` | кнопка «Обновить» (prominent) |
| downloading | Скачивание | `<fw> → <tag>` · `NN%` | бар (прогресс скачивания) |
| downloaded | Подключись к машинке | Wi-Fi «ESP32-Car» | кнопка «Залить» (disabled при `!online`) |
| uploading | Заливка | `<tag>` · `NN%` | бар (`uploadProgress`) |
| rebooting | Перезагрузка… | Машинка скоро вернётся | — |
| done | Готово | Обновлено до `<fw>` | — (закрытие — системной «назад») |
| failed | Не удалось | Проверь связь и повтори | кнопка «Повторить» (prominent) |

## Левая картинка — анимация по процессу (`FirmwareCarView`)

Иконка состояния = **чип**: `cpu` (▣) для checking/available/downloading/downloaded/uploading/rebooting; `checkmark` (✓) для upToDate/done (done — с усиленным свечением); `exclamationmark` (!) в `warn` для failed.

Кольца/волны вокруг машинки — по правилу «есть ли ожидание»:
- **Пульс (есть ожидание):** `checking`, `downloading`, `downloaded` — волны пульсируют (scale 0.96↔1.10, средняя яркость); `uploading` — пульс **ярче**; `rebooting` — **пинг** (кольцо расходится наружу, 2 шт. со сдвигом).
- **Статичные волны (ничего не ждём):** `upToDate` — кольца есть, но без анимации (бледные).
- **Без волн вообще:** `available`, `done`, `failed` — только чип.

(«Закрыть» удалена; стрелка ↓ на скачивании убрана — активность несут пульс-волны + бар.)

## Прогресс скачивания

`UpdateClient.download` сейчас не отдаёт прогресс. Добавить `@Published var downloadProgress: Double` и
`URLSessionDownloadDelegate.urlSession(_:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:)`,
скачивать через `session.download(for:)` с `self` как делегатом (как у upload). `downloading` показывает реальный `NN%` + бар.

## Компоненты

| Файл | Изменение |
|---|---|
| `ios/ESP32Car/FirmwareCarView.swift` | волны по режиму (`waitw`/`active`/`deco`/`none`/`ping`), чип-иконки; пульс/пинг анимации |
| `ios/ESP32Car/FirmwareView.swift` | единый шаблон Заголовок/Подзаголовок/действие; новые тексты; `downloading` использует `downloadProgress`; «Закрыть» убрать |
| `ios/ESP32Car/UpdateClient.swift` | `downloadProgress` + `URLSessionDownloadDelegate` |
| `ios/ESP32Car/L.swift` + `ru.lproj/Localizable.strings` | новые/обновлённые ключи `fw.*` (лаконичные) |

## Строки (итог `fw.*`)

```
"fw.checking"      = "Проверка обновлений…";
"fw.current"       = "Текущая %@";
"fw.upToDate"      = "Актуальная версия";
"fw.versionLine"   = "Версия %@";
"fw.recheck"       = "Проверить снова";
"fw.available"     = "Доступно обновление";
"fw.transition"    = "%@ → %@";          // <fw> → <tag>
"fw.update"        = "Обновить";
"fw.downloadTitle" = "Скачивание";
"fw.connectTitle"  = "Подключись к машинке";
"fw.connectSub"    = "Wi-Fi «ESP32-Car»";
"fw.flash"         = "Залить";
"fw.uploadTitle"   = "Заливка";
"fw.rebootTitle"   = "Перезагрузка…";
"fw.rebootWait"    = "Машинка скоро вернётся";
"fw.doneTitle"     = "Готово";
"fw.doneSub"       = "Обновлено до %@";
"fw.failTitle"     = "Не удалось";
"fw.failSub"       = "Проверь связь и повтори";
"fw.retry"         = "Повторить";
```
(Удаляются устаревшие: `fw.latest`, `fw.connectCar`, `fw.downloadingGh`, `fw.downloaded`, `fw.uploadingTag`,
`fw.rebooting`, `fw.version`, `fw.done`, `fw.failed`, `fw.upToDate`-старый текст — заменяются вышеуказанными.)

## Тестирование

- Компиляция `iphonesimulator26.2`.
- Симулятор (временный харнесс с форсом фаз): скриншоты ключевых состояний — available, downloading (бар), uploading (яркий пульс), rebooting (пинг), done (без волн, ✓), failed (без волн, !); проверить, что у available/done/failed колец нет, у upToDate — статичны, у waiting — пульсируют.
- Версии с `v` (на моке — `mock`, на устройстве — `vX.Y`).

## Вне объёма

- Прошивка/протокол, реальный OTA на устройстве (в OTA-плане), раскладка/центрирование (уже сделано).
