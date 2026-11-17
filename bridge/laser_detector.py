"""Simple laser detection on pure black background (640x480)."""
from dataclasses import dataclass
import numpy as np

@dataclass(frozen=True)
class LaserDetection:
    x: float  # 0.0 to 1.0
    y: float  # 0.0 to 1.0
    brightness: int  # Red channel value (0-255)


def find_laser_dot(frame):
    """Find red laser dot on pure black background.
    
    Args:
        frame: BGR image (640x480, uint8)
    
    Returns:
        LaserDetection with normalized coordinates (0-1) or None if not found.
    """
    if frame.shape != (480, 640, 3):
        return None
    
    # Extract color channels (BGR format)
    b, g, r = frame[:,:,0], frame[:,:,1], frame[:,:,2]
    
    # Laser dot detection: Red channel high, Green and Blue low
    # Thresholds tuned for pure black background + red laser
    red_mask = (r > 150) & (g < 80) & (b < 80)
    
    if not np.any(red_mask):
        return None
    
    # Find brightest red pixel (most likely laser dot center)
    r_filtered = r.astype(np.int32)
    r_filtered[~red_mask] = 0
    
    brightness = int(np.max(r_filtered))
    y, x = np.unravel_index(np.argmax(r_filtered), r_filtered.shape)
    
    # Normalize to 0-1 range
    norm_x = float(x) / 639.0  # 640 pixels: 0-639
    norm_y = float(y) / 479.0  # 480 pixels: 0-479
    
    return LaserDetection(norm_x, norm_y, brightness)


def find_laser_cluster(frame, min_cluster_size=2):
    """Find laser dot as a cluster of red pixels (more robust).
    
    Returns the centroid of the brightest red cluster.
    
    Args:
        frame: BGR image (640x480, uint8)
        min_cluster_size: Minimum pixels to consider a laser dot
    
    Returns:
        LaserDetection or None if not found.
    """
    if frame.shape != (480, 640, 3):
        return None
    
    b, g, r = frame[:,:,0], frame[:,:,1], frame[:,:,2]
    
    # Red mask
    red_mask = (r > 150) & (g < 80) & (b < 80)
    
    if not np.any(red_mask):
        return None
    
    # Find connected components (clusters of red)
    # Simple approach: find bounding box of red pixels
    red_pixels = np.where(red_mask)
    
    if len(red_pixels[0]) < min_cluster_size:
        return None
    
    # Weighted centroid (brightness-weighted)
    r_values = r[red_mask].astype(np.float32)
    weight_sum = np.sum(r_values)
    
    y_coords = red_pixels[0].astype(np.float32)
    x_coords = red_pixels[1].astype(np.float32)
    
    centroid_y = np.sum(y_coords * r_values) / weight_sum
    centroid_x = np.sum(x_coords * r_values) / weight_sum
    
    brightness = int(np.max(r))
    
    # Normalize to 0-1
    norm_x = centroid_x / 639.0
    norm_y = centroid_y / 479.0
    
    return LaserDetection(norm_x, norm_y, brightness)
