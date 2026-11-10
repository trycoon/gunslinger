import os
from pathlib import Path
import subprocess
import sys
import unittest
import test_pipeline
ROOT = test_pipeline.ROOT

@unittest.skipUnless((ROOT / ".tools/godot").exists() or os.environ.get("GODOT_BIN"), "Requires Godot runner")
class GameIntegrationTests(unittest.TestCase):
    setUp = test_pipeline.PipelineTests.setUp
    tearDown = test_pipeline.PipelineTests.tearDown

    def test_camera_calibration_lightgun_menus_and_target_in_godot(self):
        self.receiver.close()  # Godot owns UDP 4242 for this test.
        godot = os.environ.get("GODOT_BIN", str(ROOT / ".tools/godot"))
        result = subprocess.run([godot, "--headless", "--path", str(ROOT), "--script", "tests/bridge_game.gd"], capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("SCRIPT ERROR", result.stderr)
        self.assertNotIn("ERROR:", result.stderr)
        self.assertIn("Godot target hit", result.stdout)

if __name__ == "__main__": unittest.main()
