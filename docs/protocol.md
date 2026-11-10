# ESP32 BLE protocol v1

The ESP32 is a BLE peripheral named `Gunslinger-ESP32`. Linux uses BlueZ and
Python Bleak as the central. One gun is supported in this prototype.

* Service UUID: `02f8b7a0-14b9-4e9e-9f6c-7d6054301000`
* Notify characteristic: `02f8b7a0-14b9-4e9e-9f6c-7d6054301001`

| Offset | Bytes | Meaning |
| --- | --- | --- |
| 0 | 1 | Version: `1` |
| 1 | 1 | Event: `1` = trigger |
| 2 | 4 | Unsigned shot sequence, little-endian |

Example: `01 01 2a 00 00 00` is shot 42. Increment once per physical press.
Turn the laser on **before** the notification; the firmware example holds it on
for 300 ms. Debounce the trigger. Reload logic stays in the pistol: Lightgun
mode has infinite ammunition. Duplicate sequences are ignored per connection;
reconnecting allows the ESP32's counter to restart.

The camera captures continuously. On a trigger the detector examines buffered
frames from 80 ms before receipt through 250 ms after, with a background from
at least 200 ms before receipt. It requires two consecutive nearby detections
and uses the earlier position to reduce aim drift. Acquisition timestamps are
software receipt timestamps, not exact sensor exposure timestamps.

Calibration stores camera coordinates normalized to `[0,1]`, in projector
TL/TR/BR/BL order. OpenCV's homography maps these to normalized game coordinates.
No calibration, no detected laser or a point outside the projector means a miss.
Thresholds and timing require validation with the actual projector/camera/gun.

## Local endpoints

All endpoints bind only to `127.0.0.1`. No internet is used during gameplay.

* UDP 4242: bridge -> Godot shot/status JSON.
* UDP 4243: simulated trigger commands, accepted only by the mock camera.
* HTTP 4244: `GET /frame.jpg`, `GET /status`, `GET /calibration`, `POST /calibration`.

```json
{"type":"shot","id":"session:42:1","found":true,"x":0.45,"y":0.62,"fired_at":1791759600.0,"latency_ms":67}
```

Misses have `found:false` and a reason. One event per trigger. Godot ignores
duplicates and expired events. Local UDP is a prototype transport without ACKs.
Calibration POST: `{"corners":[[0,0],[1,0],[1,1],[0,1]]}`.

Arduino example: `firmware/esp32_gunslinger/esp32_gunslinger.ino`. Adapt pins to
your existing button/laser-driver circuit and compile with the ESP32 Arduino
board support package. No firmware compilation or hardware BLE test has been
performed without the board/toolchain.
