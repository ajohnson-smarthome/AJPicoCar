#!/usr/bin/env python3
"""Minimal mock of the ESP32-Car firmware HTTP/WS API for running the iOS app
in the simulator without hardware. Serves GET /status and WS /ws on 127.0.0.1:8080."""
import time
from aiohttp import web, WSMsgType

START = time.monotonic()


async def status(request):
    return web.json_response({
        "device": "esp32-car",
        "fw": "mock",
        "uptime_s": int(time.monotonic() - START),
        "calibrated": True,
        "heap": 200000,
    })


async def ws(request):
    wsr = web.WebSocketResponse()
    await wsr.prepare(request)
    print("ws: client connected")
    async for msg in wsr:
        if msg.type == WSMsgType.TEXT:
            print(f"ws rx: {msg.data}")      # the app's "t,y" frames; we just log them
        elif msg.type == WSMsgType.ERROR:
            print(f"ws error: {wsr.exception()}")
    print("ws: client disconnected")
    return wsr


def main():
    app = web.Application()
    app.add_routes([web.get("/status", status), web.get("/ws", ws)])
    print("mock car on http://127.0.0.1:8080  (GET /status, WS /ws)")
    web.run_app(app, host="127.0.0.1", port=8080)


if __name__ == "__main__":
    main()
