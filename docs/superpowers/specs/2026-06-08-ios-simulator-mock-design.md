# Запуск iOS-приложения на Mac без машинки и телефона — Design

**Дата:** 2026-06-08
**Статус:** дизайн утверждён, готов к плану

## Цель

Гонять iOS-приложение пульта **на Mac в симуляторе** — без прошитой машинки и без iPhone.
Нужно для быстрой итерации UI/поведения. Тот же код без правок едет на реальный iPhone к
настоящей машинке.

## Два блокера и решения

1. **Нет рантайма iOS-симулятора** → скачать разово (`xcodebuild -downloadPlatform iOS`, ~7 ГБ).
2. **Апп стучится в `192.168.4.1`, которого на Mac нет** → поднять «фейковую машинку» на
   `127.0.0.1:8080` (mock-сервер) и переключать адрес автоматически на симуляторе.

## Часть 1 — Рантайм симулятора (разовая настройка)

```bash
xcodebuild -downloadPlatform iOS
```
После установки `xcrun simctl list devices available` покажет iPhone-устройства, и апп можно
запускать в симуляторе из Xcode (Run) или скриптом `simctl`.

## Часть 2 — Mock-сервер `tools/mock_car/mock_car.py`

Минимальный Python-сервер (**aiohttp**, один порт `127.0.0.1:8080`), повторяющий API прошивки
ровно настолько, чтобы апп ожил:

- `GET /status` → `{"device":"esp32-car","fw":"mock","uptime_s":<секунды с запуска>,"calibrated":true,"heap":200000}`
  (подпись `device:"esp32-car"` — апп считает, что «на машинке»; `uptime_s` растёт от старта сервера).
- `WS /ws` → апгрейд WebSocket; принимает текстовые кадры `t,y` и **молча игнорирует** (телеметрия и
  анимация колёс считаются в аппе из команды — серверу отвечать нечем, обороты он не знает).

Зависимость `aiohttp` — в локальном venv: `tools/mock_car/requirements.txt` (`aiohttp`), плюс
короткая инструкция в `tools/mock_car/README.md`:
```bash
cd tools/mock_car
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python mock_car.py        # слушает http://127.0.0.1:8080
```
Сервер печатает в консоль принятые `t,y` (для глаз — видно, что апп шлёт), но это не влияет на апп.

YAGNI: без `/calib*` (в текущем аппе калибровки нет — Фаза 2), без имитации обрывов, без «физики».

## Часть 3 — Адрес машинки в аппе: `CarHost` (автопереключение)

Новый файл `ios/ESP32Car/CarHost.swift` — единственное место с адресом, через компайл-флаг
окружения:
```swift
enum CarHost {
    #if targetEnvironment(simulator)
    static let httpBase = "http://127.0.0.1:8080"
    static let wsURL    = "ws://127.0.0.1:8080/ws"
    #else
    static let httpBase = "http://192.168.4.1"
    static let wsURL    = "ws://192.168.4.1/ws"
    #endif
    static let statusURL = httpBase + "/status"
}
```
- `CarConnection` берёт `URL(string: CarHost.wsURL)!` вместо хардкода.
- `CarStatus` берёт `URL(string: CarHost.statusURL)!`.

**Симулятор → localhost-мок; реальный iPhone → `192.168.4.1`.** Ноль ручных переключений.
ATS уже разрешает локальную сеть (`NSAllowsLocalNetworking` в Info.plist), `ws://`/`http://` к
`127.0.0.1` проходят.

## Поток запуска (что делает разработчик)

1. (Разово) `xcodebuild -downloadPlatform iOS`.
2. Старт мока: `tools/mock_car/.venv/bin/python tools/mock_car/mock_car.py`.
3. Xcode → выбрать iPhone-симулятор → **Run**. Апп: `connected · <ping> ms`, живая телеметрия от
   стиков (мышью), обе темы. (Альтернатива из CLI: `xcrun simctl boot`, `xcodebuild build`,
   `simctl install` + `simctl launch` — опишем в плане.)

## Архитектура (файлы)

| Файл | Изменение |
|---|---|
| `tools/mock_car/mock_car.py` *(new)* | aiohttp: `GET /status` + `WS /ws` на `127.0.0.1:8080` |
| `tools/mock_car/requirements.txt` *(new)* | `aiohttp` |
| `tools/mock_car/README.md` *(new)* | как поднять venv и запустить |
| `ios/ESP32Car/CarHost.swift` *(new)* | адреса по `#if targetEnvironment(simulator)` |
| `ios/ESP32Car/CarConnection.swift` | использовать `CarHost.wsURL` |
| `ios/ESP32Car/CarStatus.swift` | использовать `CarHost.statusURL` |

## Тестирование

- **Mock-сервер:** `curl http://127.0.0.1:8080/status` → JSON с `device:"esp32-car"`; `uptime_s` растёт.
- **Апп в симуляторе:** собрать под симулятор-SDK (рантайм уже стоит), запустить → плашка
  `connected`, пинг, двигать стик мышью → L/R % и колёса реагируют; переключить тему симулятора
  (Settings → Developer / Appearance) → палитра меняется.
- **Регрессия на устройство:** `#else`-ветка `CarHost` = прежние `192.168.4.1` адреса; на iPhone
  поведение не меняется.

## Вне объёма

- Полная симуляция машинки (физика, обороты) — обороты не меряются даже на железе.
- `/calib*` в моке — калибровки в текущем аппе нет (Фаза 2).
- Имитация обрывов связи в моке (можно добавить позже, если понадобится тест reconnect/дебаунса).
- Гейтинг порта/секретов — мок только для localhost-разработки.
