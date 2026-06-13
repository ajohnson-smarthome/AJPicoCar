#!/usr/bin/env python3
"""Minimal mock of the ESP32-Car firmware HTTP/WS API for running the iOS app
in the simulator without hardware. Serves /status, /ws, and /calib* on 127.0.0.1:8080."""
import asyncio
import json
import time
from aiohttp import web, WSMsgType

START = time.monotonic()
STATE = {"calibrated": False, "ramp_ms": 300, "trim_pct": 0, "wdt_trips": 0}


async def status(request):
    return web.json_response({
        "device": "esp32-car",
        "fw": "v1.0+9000",
        "uptime_s": int(time.monotonic() - START),
        "calibrated": STATE["calibrated"],
        "heap": 200000,
        "rssi": -58,
        "ws_fps": 10,
        "wdt_trips": STATE["wdt_trips"],
    })


async def ws(request):
    wsr = web.WebSocketResponse()
    await wsr.prepare(request)
    print("ws: client connected")

    async def pusher():
        while not wsr.closed:
            payload = {
                "rssi": -58,
                "ws_fps": 10,
                "wdt_trips": STATE.get("wdt_trips", 0),
                "uptime_s": int(time.monotonic() - START),
                "heap": 200000,
                "calibrated": STATE.get("calibrated", False),
            }
            try:
                await wsr.send_str(json.dumps(payload))
            except Exception:
                break
            await asyncio.sleep(0.2)  # 5 Hz

    push_task = asyncio.create_task(pusher())
    try:
        async for msg in wsr:
            if msg.type == WSMsgType.TEXT:
                print(f"ws rx: {msg.data}")
            elif msg.type == WSMsgType.ERROR:
                print(f"ws error: {wsr.exception()}")
    finally:
        push_task.cancel()
    print("ws: client disconnected")
    return wsr


async def calib(request):
    return web.json_response({"calibrated": STATE["calibrated"]})


async def calib_spin(request):
    print(f"calib/spin: {await request.text()}")
    return web.Response(text="ok")


async def calib_save(request):
    body = await request.text()
    print(f"calib/save: {body}")
    STATE["calibrated"] = True
    return web.Response(text="ok")


async def ramp_get(request):
    return web.json_response({"ramp_ms": STATE["ramp_ms"]})


async def ramp_post(request):
    body = (await request.text()).strip()
    try:
        v = int(body)
        if not 0 <= v <= 2000:
            raise ValueError
    except ValueError:
        return web.Response(status=400, text="ramp_ms must be 0..2000")
    STATE["ramp_ms"] = v
    print(f"ramp: set {v} ms")
    return web.Response(text="ok")


async def trim_get(request):
    return web.json_response({"trim_pct": STATE["trim_pct"]})


async def trim_post(request):
    body = (await request.text()).strip()
    try:
        v = int(body)
        if not -30 <= v <= 30:
            raise ValueError
    except ValueError:
        return web.Response(status=400, text="trim_pct must be -30..30")
    STATE["trim_pct"] = v
    print(f"trim: set {v} %")
    return web.Response(text="ok")


async def ota(request):
    data = await request.read()
    print(f"ota: received {len(data)} bytes")
    return web.Response(text="ok")


def main():
    app = web.Application()
    app.add_routes([
        web.get("/status", status),
        web.get("/ws", ws),
        web.get("/calib", calib),
        web.post("/calib/spin", calib_spin),
        web.post("/calib/save", calib_save),
        web.post("/ota", ota),
        web.get("/ramp", ramp_get),
        web.post("/ramp", ramp_post),
        web.get("/trim", trim_get),
        web.post("/trim", trim_post),
    ])
    print("mock car on http://127.0.0.1:8080  (/status, /ws, /calib*)")
    web.run_app(app, host="127.0.0.1", port=8080)


if __name__ == "__main__":
    main()
