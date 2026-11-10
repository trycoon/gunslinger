"""Laser detection and calibrated camera-to-projector coordinates."""
from dataclasses import dataclass
import cv2
import numpy as np

@dataclass(frozen=True)
class Detection:
    x: float
    y: float
    strength: float


def validate_corners(values):
    points = np.asarray(values, dtype=np.float32)
    if points.shape != (4, 2) or not np.isfinite(points).all():
        raise ValueError("Select four corners in TL, TR, BR, BL order")
    if np.any(points < 0) or np.any(points > 1):
        raise ValueError("Corners must be inside the camera image")
    contour = points.reshape(-1, 1, 2)
    if not cv2.isContourConvex(contour) or abs(cv2.contourArea(contour)) < .03:
        raise ValueError("Corners must form a convex quadrilateral covering at least 3% of the image")
    return points


class Mapper:
    def __init__(self, corners):
        self.corners = validate_corners(corners)
        destination = np.array([[0, 0], [1, 0], [1, 1], [0, 1]], dtype=np.float32)
        self.matrix = cv2.getPerspectiveTransform(self.corners, destination)

    def project(self, point):
        source = np.array([[point]], dtype=np.float32)
        x, y = cv2.perspectiveTransform(source, self.matrix)[0, 0]
        if not np.isfinite([x, y]).all() or x < -.001 or x > 1.001 or y < -.001 or y > 1.001:
            return None
        return float(np.clip(x, 0, 1)), float(np.clip(y, 0, 1))


def detect(frame, background=None, settings=None, mapper=None):
    """Find the brightest compact red component, including red halos around white cores.

    Frames are BGR. A pre-trigger background suppresses static red scene content.
    No inference or training dataset is required. Thresholds need hardware tuning.
    """
    options = {"min_red": 210, "min_red_excess": 55, "min_area": 3,
               "max_area": 450, "min_change": 25}
    options.update(settings or {})
    hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
    red_mask = cv2.inRange(hsv, (0, 90, 0), (12, 255, 255)) | cv2.inRange(hsv, (168, 90, 0), (179, 255, 255))
    blue, green, red = [channel.astype(np.int16) for channel in cv2.split(frame)]
    excess = red - np.maximum(blue, green)
    mask = (red_mask > 0) & (red >= options["min_red"]) & (excess >= options["min_red_excess"])
    if background is not None and background.shape == frame.shape:
        old_red = background[:, :, 2].astype(np.int16)
        mask &= red - old_red >= options["min_change"]
    count, labels, stats, centroids = cv2.connectedComponentsWithStats(mask.astype(np.uint8), 8)
    height, width = frame.shape[:2]
    best = None
    for label in range(1, count):
        x, y, w, h, area = stats[label]
        if not options["min_area"] <= area <= options["max_area"]:
            continue
        if max(w, h) / max(1, min(w, h)) > 3.5:
            continue
        component = labels[y:y + h, x:x + w] == label
        weights = np.where(component, excess[y:y + h, x:x + w], 0).astype(np.float64)
        total = weights.sum()
        yy, xx = np.indices(weights.shape)
        center_x = float(x + (xx * weights).sum() / total)
        center_y = float(y + (yy * weights).sum() / total)
        # Pixel coordinates use image endpoints, matching the calibration preview.
        camera_point = (center_x / max(1, width - 1), center_y / max(1, height - 1))
        if mapper is not None and mapper.project(camera_point) is None:
            continue
        strength = float(red[y:y + h, x:x + w][component].mean() + weights[component].mean())
        candidate = Detection(*camera_point, strength)
        if best is None or candidate.strength > best.strength:
            best = candidate
    return best
