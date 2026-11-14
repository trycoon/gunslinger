import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from configure_bridge import configure


class ConfigureBridgeTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.path = Path(self.folder.name) / "bridge.json"
        self.example = ROOT / "bridge/config.example.json"

    def test_new_config_uses_requested_backend(self):
        configure(self.path, self.example, "picamera2")
        self.assertEqual(json.loads(self.path.read_text())["camera"]["backend"], "picamera2")

    def test_new_mock_config_disables_ble(self):
        configure(self.path, self.example, "mock")
        self.assertFalse(json.loads(self.path.read_text())["ble"]["enabled"])

    def test_default_does_not_change_existing_config(self):
        original = '{"camera": {"backend": "picamera2"}, "corners": [1]}\n'
        self.path.write_text(original)
        configure(self.path, self.example)
        self.assertEqual(self.path.read_text(), original)

    def test_explicit_backend_preserves_other_settings(self):
        original = {"camera": {"backend": "picamera2", "device": 0, "fps": 30},
                    "ble": {"enabled": True}, "corners": [[0.1, 0.2]]}
        self.path.write_text(json.dumps(original))
        configure(self.path, self.example, "opencv")
        updated = json.loads(self.path.read_text())
        original["camera"]["backend"] = "opencv"
        self.assertEqual(updated, original)

    def test_explicit_backend_adds_missing_camera_settings(self):
        self.path.write_text('{"corners": []}\n')
        configure(self.path, self.example, "opencv")
        self.assertEqual(json.loads(self.path.read_text()),
                         {"camera": {"backend": "opencv"}, "corners": []})


if __name__ == "__main__":
    unittest.main()
