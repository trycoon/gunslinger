"""Actual subprocess -> mock camera -> OpenCV -> calibration -> UDP integration."""
import json
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.error
import urllib.request

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "bridge"))
from camera import MOCK_CORNERS

ROOT = Path(__file__).resolve().parents[1]

class PipelineTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.config = Path(self.folder.name) / "config.json"
        self.receiver = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.receiver.bind(("127.0.0.1", 4242))
        self.receiver.settimeout(.5)
        self.sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.process = subprocess.Popen([sys.executable, str(ROOT / "bridge/bridge.py"), "--mock", "--config", str(self.config)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            try:
                with urllib.request.urlopen("http://127.0.0.1:4244/frame.jpg", timeout=.2) as response:
                    if response.status == 200: break
            except (urllib.error.URLError, OSError): pass
            if self.process.poll() is not None:
                self.fail(self.process.stderr.read().decode())
            time.sleep(.05)
        else: self.fail("Mock camera did not start")
        time.sleep(.3)  # Fill pre-trigger background buffer.

    def tearDown(self):
        self.process.terminate()
        try: self.process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
        self.process.stderr.close()
        self.receiver.close()
        self.sender.close()
        self.folder.cleanup()

    def calibrate(self, points=MOCK_CORNERS):
        request = urllib.request.Request("http://127.0.0.1:4244/calibration", json.dumps({"corners":points}).encode(), {"Content-Type":"application/json"}, method="POST")
        with urllib.request.urlopen(request, timeout=2) as response: return json.load(response)

    def trigger(self, x, y):
        self.sender.sendto(json.dumps({"type":"simulate", "x":x, "y":y}).encode(), ("127.0.0.1", 4243))
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            try: event = json.loads(self.receiver.recv(4096))
            except socket.timeout: continue
            if event.get("type") == "shot": return event
        self.fail("No shot event received")

    def test_uncalibrated_trigger_is_a_miss(self):
        event = self.trigger(.5, .5)
        self.assertFalse(event["found"])
        self.assertEqual(event["reason"], "not calibrated")

    def test_calibration_persists_and_full_pipeline_maps_shot(self):
        self.calibrate()
        self.assertTrue(self.config.exists())
        with urllib.request.urlopen("http://127.0.0.1:4244/calibration") as response:
            self.assertEqual(len(json.load(response)["corners"]), 4)
        event = self.trigger(.36, .61)
        self.assertTrue(event["found"], event)
        self.assertAlmostEqual(event["x"], .36, delta=.01)
        self.assertAlmostEqual(event["y"], .61, delta=.01)
        self.assertLess(event["latency_ms"], 250)

    def test_invalid_calibration_does_not_replace_saved_map(self):
        self.calibrate()
        before = self.config.read_text()
        with self.assertRaises(urllib.error.HTTPError) as error:
            self.calibrate([[0,0]] * 4)
        self.assertEqual(error.exception.code, 400)
        self.assertEqual(before, self.config.read_text())

    def test_red_point_outside_calibrated_image_is_a_miss(self):
        self.calibrate([[.3,.3],[.7,.3],[.7,.7],[.3,.7]])
        event = self.trigger(.05, .05)
        self.assertFalse(event["found"])

if __name__ == "__main__": unittest.main()
