import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path
import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "bridge"))
from detector import Mapper, detect, validate_corners
from bridge import load_config, parse_trigger
from camera import MOCK_CORNERS

class DetectorTests(unittest.TestCase):
    def setUp(self):
        self.background = np.zeros((240, 320, 3), dtype=np.uint8)

    def test_red_laser_with_white_core(self):
        frame = self.background.copy()
        cv2.circle(frame, (150, 110), 4, (0, 0, 255), -1)
        cv2.circle(frame, (150, 110), 1, (255, 255, 255), -1)
        point = detect(frame, self.background)
        self.assertIsNotNone(point)
        self.assertAlmostEqual(point.x, 150 / 319, places=3)
        self.assertAlmostEqual(point.y, 110 / 239, places=3)

    def test_rejects_white_blue_and_large_red_regions(self):
        for color in [(255, 255, 255), (255, 0, 0), (0, 255, 0)]:
            frame = self.background.copy()
            cv2.circle(frame, (150, 110), 5, color, -1)
            self.assertIsNone(detect(frame, self.background))
        frame = self.background.copy()
        cv2.rectangle(frame, (20, 20), (100, 100), (0, 0, 255), -1)
        self.assertIsNone(detect(frame, self.background))

    def test_static_red_scene_content_is_rejected(self):
        cv2.circle(self.background, (30, 30), 5, (0, 0, 255), -1)
        self.assertIsNone(detect(self.background.copy(), self.background))
        frame = self.background.copy()
        cv2.circle(frame, (200, 100), 4, (0, 0, 250), -1)
        point = detect(frame, self.background)
        self.assertAlmostEqual(point.x, 200 / 319, places=3)

    def test_brightest_valid_candidate_wins(self):
        frame = self.background.copy()
        cv2.circle(frame, (50, 50), 4, (0, 0, 220), -1)
        cv2.circle(frame, (250, 150), 4, (0, 0, 255), -1)
        self.assertAlmostEqual(detect(frame, self.background).x, 250 / 319, places=3)

    def test_perspective_corners_and_center(self):
        mapper = Mapper(MOCK_CORNERS)
        for source, expected in zip(MOCK_CORNERS, [(0,0), (1,0), (1,1), (0,1)]):
            self.assertTrue(np.allclose(mapper.project(source), expected, atol=1e-5))
        inverse = np.linalg.inv(mapper.matrix)
        camera = cv2.perspectiveTransform(np.array([[[.5, .5]]], dtype=np.float32), inverse)[0,0]
        self.assertTrue(np.allclose(mapper.project(camera), (.5, .5), atol=1e-5))
        self.assertIsNone(mapper.project((0, 0)))

    def test_outside_projection_does_not_beat_inside_laser(self):
        frame = self.background.copy()
        cv2.circle(frame, (3, 3), 4, (0, 0, 255), -1)
        cv2.circle(frame, (150, 110), 4, (0, 0, 225), -1)
        point = detect(frame, self.background, mapper=Mapper(MOCK_CORNERS))
        self.assertAlmostEqual(point.x, 150 / 319, places=3)

    def test_invalid_calibration_is_rejected(self):
        for corners in [[], [[0,0]] * 4, [[0,0],[1,1],[1,0],[0,1]], [[0,0],[.01,0],[.01,.01],[0,.01]], [[-1,0],[1,0],[1,1],[0,1]]]:
            with self.assertRaises(ValueError): validate_corners(corners)

    def test_ble_protocol(self):
        self.assertEqual(parse_trigger(struct.pack("<BBI", 1, 1, 42)), 42)
        self.assertEqual(parse_trigger(struct.pack("<BBI", 1, 1, 0xffffffff)), 0xffffffff)
        for payload in [b"1", struct.pack("<BBI", 2, 1, 42), struct.pack("<BBI", 1, 2, 42)]:
            with self.assertRaises(ValueError): parse_trigger(payload)

    def test_config_defaults_and_roundtrip(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "bridge.json"
            self.assertEqual(load_config(path)["camera"]["width"], 640)
            path.write_text(json.dumps({"camera":{"backend":"mock"}, "corners":MOCK_CORNERS}))
            self.assertEqual(load_config(path)["camera"]["backend"], "mock")
            self.assertEqual(load_config(path)["camera"]["fps"], 30)

if __name__ == "__main__": unittest.main()
