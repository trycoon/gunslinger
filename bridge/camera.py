"""Continuously acquire frames; image analysis happens only after a trigger."""
from collections import deque
from dataclasses import dataclass
import threading
import time
import cv2
import numpy as np

MOCK_CORNERS = [[.08, .12], [.91, .08], [.94, .88], [.06, .93]]

@dataclass(frozen=True)
class Frame:
    timestamp: float
    image: np.ndarray


class Camera:
    def __init__(self, settings):
        self.settings = settings
        self.backend = settings.get("backend", "opencv")
        self.width = int(settings.get("width", 640))
        self.height = int(settings.get("height", 480))
        self.fps = int(settings.get("fps", 30))
        if not (160 <= self.width <= 1920 and 120 <= self.height <= 1080 and 1 <= self.fps <= 120):
            raise ValueError("Camera size or frame rate outside supported prototype range")
        self.frames = deque(maxlen=max(30, self.fps * 2))
        self.lock = threading.Lock()
        self.stop = threading.Event()
        self.error = "Starting camera"
        self.device = None
        self.thread = None
        self.mock_point = (.5, .5)
        self.mock_until = 0.0

    def start(self):
        if self.backend == "picamera2":
            from picamera2 import Picamera2
            self.device = Picamera2()
            config = self.device.create_video_configuration(
                main={"size": (self.width, self.height), "format": "RGB888"},
                controls={"FrameRate": float(self.fps)}, buffer_count=4)
            self.device.configure(config)
            controls = {}
            if self.settings.get("exposure_us", 0) > 0:
                controls.update(AeEnable=False, ExposureTime=int(self.settings["exposure_us"]),
                                AnalogueGain=float(self.settings.get("gain", 1.0)))
            if self.settings.get("lens_position") is not None:
                controls.update(AfMode=0, LensPosition=float(self.settings["lens_position"]))
            if controls:
                self.device.set_controls(controls)
            self.device.start()
        elif self.backend == "opencv":
            self.device = cv2.VideoCapture(self.settings.get("device", 0))
            if not self.device.isOpened():
                self.device.release()
                raise RuntimeError("Cannot open USB camera; check device index and permissions")
            self.device.set(cv2.CAP_PROP_FRAME_WIDTH, self.width)
            self.device.set(cv2.CAP_PROP_FRAME_HEIGHT, self.height)
            self.device.set(cv2.CAP_PROP_FPS, self.fps)
            self.device.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        elif self.backend != "mock":
            raise ValueError("Camera backend must be opencv, picamera2 or mock")
        self.thread = threading.Thread(target=self._capture, daemon=True)
        self.thread.start()

    def trigger_mock(self, x, y):
        with self.lock:
            self.mock_point = (float(np.clip(x, 0, 1)), float(np.clip(y, 0, 1)))
            self.mock_until = time.monotonic() + .3

    def _mock_frame(self):
        frame = np.zeros((self.height, self.width, 3), dtype=np.uint8)
        frame[:] = (20, 22, 25)
        corners = np.asarray(MOCK_CORNERS, dtype=np.float32)
        pixels = corners * np.array([self.width - 1, self.height - 1], dtype=np.float32)
        cv2.fillConvexPoly(frame, pixels.astype(np.int32), (90, 125, 150))
        for index, point in enumerate(pixels.astype(int)):
            cv2.circle(frame, tuple(point), 7, (210, 240, 240), -1)
            cv2.putText(frame, str(index + 1), tuple(point + [10, 10]), cv2.FONT_HERSHEY_SIMPLEX, .5, (255, 255, 255), 1)
        cv2.putText(frame, "SIMULATED PROJECTOR", (115, 120), cv2.FONT_HERSHEY_SIMPLEX, .6, (180, 210, 210), 1)
        with self.lock:
            active, position = time.monotonic() < self.mock_until, self.mock_point
        if active:
            source = np.array([[0, 0], [1, 0], [1, 1], [0, 1]], dtype=np.float32)
            matrix = cv2.getPerspectiveTransform(source, pixels)
            point = cv2.perspectiveTransform(np.array([[position]], dtype=np.float32), matrix)[0, 0]
            cv2.circle(frame, tuple(np.rint(point).astype(int)), 4, (0, 0, 255), -1)
            cv2.circle(frame, tuple(np.rint(point).astype(int)), 1, (255, 255, 255), -1)
        return frame

    def _capture(self):
        try:
            while not self.stop.is_set():
                started = time.monotonic()
                if self.backend == "mock":
                    image = self._mock_frame()
                elif self.backend == "picamera2":
                    # Picamera2's RGB888 buffers have BGR byte order for OpenCV.
                    image = self.device.capture_array("main")
                else:
                    ok, image = self.device.read()
                    if not ok:
                        self.error = "Camera capture failed"
                        self.stop.wait(.1)
                        continue
                with self.lock:
                    self.frames.append(Frame(time.monotonic(), image))
                    self.error = ""
                if self.backend == "mock":
                    self.stop.wait(max(0, 1 / self.fps - (time.monotonic() - started)))
        except Exception as exc:
            self.error = f"Camera error: {exc}"

    def snapshots(self):
        with self.lock:
            return list(self.frames)

    def latest(self):
        with self.lock:
            return self.frames[-1] if self.frames else None

    def close(self):
        self.stop.set()
        if self.thread:
            self.thread.join(timeout=2)
        if self.device is not None:
            if self.backend == "picamera2":
                self.device.stop()
                self.device.close()
            else:
                self.device.release()
