#!/usr/bin/env python3
"""Minimal mock of the ESP32-Car firmware HTTP/WS API for running the iOS app
in the simulator without hardware. Serves /status, /ws, and /calib* on 127.0.0.1:8080."""
import time
from aiohttp import web, WSMsgType

START = time.monotonic()
STATE = {"calibrated": False}


async def status(request):
    return web.json_response({
        "device": "esp32-car",
        "fw": "mock",
        "uptime_s": int(time.monotonic() - START),
        "calibrated": STATE["calibrated"],
        "heap": 200000,
    })


async def ws(request):
    wsr = web.WebSocketResponse()
    await wsr.prepare(request)
    print("ws: client connected")
    async for msg in wsr:
        if msg.type == WSMsgType.TEXT:
            print(f"ws rx: {msg.data}")
        elif msg.type == WSMsgType.ERROR:
            print(f"ws error: {wsr.exception()}")
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


def main():
    app = web.Application()
    app.add_routes([
        web.get("/status", status),
        web.get("/ws", ws),
        web.get("/calib", calib),
        web.post("/calib/spin", calib_spin),
        web.post("/calib/save", calib_save),
    ])
    print("mock car on http://127.0.0.1:8080  (/status, /ws, /calib*)")
    web.run_app(app, host="127.0.0.1", port=8080)


if __name__ == "__main__":
    main()
