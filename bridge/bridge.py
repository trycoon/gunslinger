#!/usr/bin/env python3
"""Local camera/BLE bridge. Bind every endpoint to loopback only."""
import argparse
import asyncio
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import logging
import math
from pathlib import Path
import socket
import signal
import struct
import threading
import time
import uuid

import cv2

from camera import Camera, MOCK_CORNERS
from detector import Mapper, detect, validate_corners

SERVICE_UUID = "02f8b7a0-14b9-4e9e-9f6c-7d6054301000"
TRIGGER_UUID = "02f8b7a0-14b9-4e9e-9f6c-7d6054301001"
DEFAULTS = {
    "camera": {"backend": "opencv", "device": 0, "width": 640, "height": 480, "fps": 30},
    "ble": {"name": "Gunslinger-ESP32", "address": "", "enabled": True},
    "detector": {}, "corners": [],
}


def parse_trigger(payload):
    if len(payload) != 6:
        raise ValueError("Expected a six-byte trigger packet")
    version, kind, sequence = struct.unpack("<BBI", payload)
    if version != 1 or kind != 1:
        raise ValueError("Unsupported trigger version or event")
    return sequence


def load_config(path):
    result = json.loads(json.dumps(DEFAULTS))
    if path.exists():
        supplied = json.loads(path.read_text())
        if not isinstance(supplied, dict):
            raise ValueError("Configuration must be a JSON object")
        for key in ("camera", "ble", "detector"):
            if key in supplied:
                if not isinstance(supplied[key], dict):
                    raise ValueError(f"{key} configuration must be an object")
                result[key].update(supplied[key])
        result["corners"] = supplied.get("corners", [])
        if result["corners"]:
            validate_corners(result["corners"])
    return result


class Bridge:
    def __init__(self, config, config_path):
        self.config = config
        self.config_path = config_path
        self.config_lock = threading.Lock()
        self.mapper = Mapper(config["corners"]) if config["corners"] else None
        self.camera = Camera(config["camera"])
        self.output = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.triggers = asyncio.Queue(maxsize=16)
        self.ble_state = "BLE disabled" if not config["ble"]["enabled"] else "BLE searching"
        self.session = uuid.uuid4().hex
        self.trigger_sequence = 0
        self.stopping = asyncio.Event()
        self.http = None
        self.transport = None

    def send(self, data):
        data["sent_at"] = time.time()
        self.output.sendto(json.dumps(data).encode(), ("127.0.0.1", 4242))

    def status_message(self):
        latest = self.camera.latest()
        if self.camera.error:
            return self.camera.error
        if latest is None or time.monotonic() - latest.timestamp > .5:
            return "Camera frames stale"
        return f"{self.camera.backend} camera | {self.ble_state} | " + ("calibrated" if self.mapper else "calibrate first")

    def enqueue(self, identifier):
        self.trigger_sequence += 1
        event = {"id": f"{self.session}:{identifier}:{self.trigger_sequence}",
                 "received": time.monotonic(), "fired_at": time.time()}
        try:
            self.triggers.put_nowait(event)
        except asyncio.QueueFull:
            # Never silently swallow a shot: resolve overflow as a miss.
            self.send({"type": "shot", "id": event["id"], "found": False,
                       "fired_at": event["fired_at"], "reason": "trigger queue full"})

    async def resolve(self, event):
        mapper = self.mapper
        if mapper is None:
            self.send({"type": "shot", "id": event["id"], "found": False,
                       "fired_at": event["fired_at"], "reason": "not calibrated"})
            return
        frames = self.camera.snapshots()
        baseline_frames = [frame for frame in frames if frame.timestamp <= event["received"] - .20]
        baseline = baseline_frames[-1].image if baseline_frames else None
        processed = set()
        previous = None
        chosen = None
        deadline = event["received"] + .25
        # Process buffered frames from just before BLE receipt, then newly acquired ones.
        while time.monotonic() <= deadline:
            for frame in self.camera.snapshots():
                if frame.timestamp in processed or frame.timestamp < event["received"] - .08 or frame.timestamp > deadline:
                    continue
                processed.add(frame.timestamp)
                candidate = await asyncio.to_thread(detect, frame.image, baseline, self.config["detector"], mapper)
                if candidate is None:
                    previous = None
                    continue
                if previous and math.hypot(candidate.x - previous.x, candidate.y - previous.y) < .025:
                    chosen = previous  # Earliest of two agreeing frames, minimizing aim drift.
                    break
                previous = candidate
            if chosen:
                break
            await asyncio.sleep(.005)
        point = mapper.project((chosen.x, chosen.y)) if chosen else None
        result = {"type": "shot", "id": event["id"], "found": point is not None,
                  "fired_at": event["fired_at"], "latency_ms": round((time.monotonic() - event["received"]) * 1000)}
        if point:
            result.update(x=point[0], y=point[1])
        else:
            result["reason"] = "no stable red point"
        self.send(result)
        logging.info("Shot %s", result)

    async def consume(self):
        while not self.stopping.is_set():
            event = await self.triggers.get()
            try:
                await self.resolve(event)
            finally:
                self.triggers.task_done()

    async def status_loop(self):
        while not self.stopping.is_set():
            self.send({"type": "status", "message": self.status_message()})
            await asyncio.sleep(1)

    async def bluetooth(self):
        from bleak import BleakClient, BleakScanner
        settings = self.config["ble"]
        while not self.stopping.is_set():
            try:
                self.ble_state = "BLE searching"
                address = settings.get("address", "")
                if address:
                    device = await BleakScanner.find_device_by_address(address, timeout=5)
                else:
                    name = settings["name"]
                    device = await BleakScanner.find_device_by_filter(
                        lambda device, advertisement: advertisement.local_name == name or device.name == name,
                        timeout=5)
                if device is None:
                    await asyncio.sleep(2)
                    continue
                seen = deque(maxlen=64)
                def notification(_characteristic, data):
                    try:
                        sequence = parse_trigger(bytes(data))
                    except ValueError as exc:
                        logging.warning("Ignoring BLE packet: %s", exc)
                        return
                    if sequence not in seen:
                        seen.append(sequence)
                        self.enqueue(str(sequence))
                async with BleakClient(device) as client:
                    await client.start_notify(TRIGGER_UUID, notification)
                    self.ble_state = "BLE connected"
                    while client.is_connected and not self.stopping.is_set():
                        await asyncio.sleep(.2)
            except Exception as exc:
                self.ble_state = "BLE disconnected"
                logging.warning("Bluetooth: %s", exc)
                await asyncio.sleep(3)

    def save_calibration(self, corners):
        points = validate_corners(corners).tolist()
        mapper = Mapper(points)
        with self.config_lock:
            updated = json.loads(json.dumps(self.config))
            updated["corners"] = points
            self.config_path.parent.mkdir(parents=True, exist_ok=True)
            temporary = self.config_path.with_suffix(".tmp")
            temporary.write_text(json.dumps(updated, indent=2) + "\n")
            temporary.replace(self.config_path)
            self.config = updated
            self.mapper = mapper
        return {"corners": points}

    def start_http(self):
        bridge = self
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass
            def reply(self, code, payload, content_type="application/json"):
                if isinstance(payload, dict):
                    payload = json.dumps(payload).encode()
                self.send_response(code)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(payload)))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                try:
                    self.wfile.write(payload)
                except (BrokenPipeError, ConnectionResetError):
                    pass
            def do_GET(self):
                if self.path == "/frame.jpg":
                    frame = bridge.camera.latest()
                    if frame is None or time.monotonic() - frame.timestamp > .5:
                        self.reply(503, {"error": "No fresh camera frame"})
                        return
                    ok, image = cv2.imencode(".jpg", frame.image, [cv2.IMWRITE_JPEG_QUALITY, 80])
                    self.reply(200, image.tobytes(), "image/jpeg") if ok else self.reply(503, {"error": "JPEG encoding failed"})
                elif self.path == "/calibration":
                    self.reply(200, {"corners": bridge.config["corners"]})
                elif self.path == "/status":
                    self.reply(200, {"message": bridge.status_message(), "calibrated": bridge.mapper is not None})
                else:
                    self.reply(404, {"error": "Unknown endpoint"})
            def do_POST(self):
                if self.path != "/calibration":
                    self.reply(404, {"error": "Unknown endpoint"})
                    return
                try:
                    size = int(self.headers.get("Content-Length", "0"))
                    if not 0 < size < 4096:
                        raise ValueError("Invalid calibration payload size")
                    body = json.loads(self.rfile.read(size))
                    self.reply(200, bridge.save_calibration(body["corners"]))
                except (ValueError, KeyError, TypeError) as exc:
                    self.reply(400, {"error": str(exc)})
                except OSError as exc:
                    self.reply(500, {"error": f"Could not save calibration: {exc}"})
        self.http = ThreadingHTTPServer(("127.0.0.1", 4244), Handler)
        self.http.daemon_threads = True
        threading.Thread(target=self.http.serve_forever, daemon=True).start()

    async def run(self):
        self.camera.start()
        self.start_http()
        bridge = self
        class Commands(asyncio.DatagramProtocol):
            def datagram_received(self, data, _address):
                if bridge.camera.backend != "mock":
                    return
                try:
                    command = json.loads(data)
                    if command.get("type") == "simulate":
                        x, y = float(command["x"]), float(command["y"])
                        if not math.isfinite(x) or not math.isfinite(y):
                            return
                        bridge.camera.trigger_mock(x, y)
                        bridge.enqueue("mock")
                except (ValueError, KeyError, TypeError, AttributeError):
                    logging.warning("Ignoring malformed simulation command")
        loop = asyncio.get_running_loop()
        loop.add_signal_handler(signal.SIGTERM, self.stopping.set)
        self.transport, _protocol = await loop.create_datagram_endpoint(Commands, local_addr=("127.0.0.1", 4243))
        tasks = [asyncio.create_task(self.consume()), asyncio.create_task(self.status_loop())]
        if self.config["ble"]["enabled"]:
            tasks.append(asyncio.create_task(self.bluetooth()))
        try:
            await self.stopping.wait()
        finally:
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)

    def close(self):
        if self.transport:
            self.transport.close()
        if self.http:
            self.http.shutdown()
            self.http.server_close()
        self.camera.close()
        self.output.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path)
    parser.add_argument("--camera", choices=["opencv", "picamera2", "mock"])
    parser.add_argument("--mock", action="store_true", help="Simulated camera, disabled BLE; F8 triggers shots")
    parser.add_argument("--no-ble", action="store_true")
    options = parser.parse_args()
    mock = options.mock or options.camera == "mock"
    path = options.config or Path.home() / ".config/gunslinger" / ("mock.json" if mock else "bridge.json")
    config = load_config(path)
    if options.camera:
        config["camera"]["backend"] = options.camera
    if mock:
        config["camera"]["backend"] = "mock"
        config["ble"]["enabled"] = False
    if options.no_ble:
        config["ble"]["enabled"] = False
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
    bridge = Bridge(config, path)
    try:
        asyncio.run(bridge.run())
    except KeyboardInterrupt:
        pass
    finally:
        bridge.close()

if __name__ == "__main__":
    main()
