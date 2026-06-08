# Mock car (for running the iOS app in the Simulator without hardware)

Mimics the firmware's `GET /status` and `WS /ws` on `http://127.0.0.1:8080`.

## Run
```bash
cd tools/mock_car
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python mock_car.py
```

The iOS app, when built for the **Simulator**, talks to `127.0.0.1:8080` automatically
(see `ios/ESP32Car/CarHost.swift`). On a real device it talks to `192.168.4.1`. The server
logs each `t,y` frame the app sends.
