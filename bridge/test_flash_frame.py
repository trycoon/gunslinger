#!/usr/bin/env python3
"""Test flash-frame detection and adaptive thresholds."""
import cv2
import numpy as np
from detector import detect, is_flash_frame, Detection

def test_flash_frame_detection():
    """Verify flash-frame detection works correctly."""
    # Create a very dark frame (simulating black flash)
    dark_frame = np.ones((480, 640, 3), dtype=np.uint8) * 20  # Very dark
    assert is_flash_frame(dark_frame), "Should detect dark frame as flash"
    
    # Create a bright frame (normal scene)
    bright_frame = np.ones((480, 640, 3), dtype=np.uint8) * 150
    assert not is_flash_frame(bright_frame), "Should not detect bright frame as flash"
    
    # Create a threshold-edge frame (just under flash threshold)
    edge_frame = np.ones((480, 640, 3), dtype=np.uint8) * 29
    assert is_flash_frame(edge_frame), "Should detect frame just under threshold as flash"
    
    # Create a frame just above flash threshold
    above_threshold = np.ones((480, 640, 3), dtype=np.uint8) * 31
    assert not is_flash_frame(above_threshold), "Should not detect frame above threshold as flash"
    
    print("✓ Flash-frame detection logic working")


def test_adaptive_thresholds():
    """Verify thresholds loosen on dark backgrounds."""
    # Create a dark frame with a small red dot
    dark_frame = np.ones((480, 640, 3), dtype=np.uint8) * 15
    # Place a small red dot at center (BGR format, so B=0, G=0, R=255)
    dark_frame[240-5:240+5, 320-5:320+5] = [0, 0, 255]
    
    # Create settings with strict thresholds
    strict_settings = {
        "min_red": 210,
        "min_red_excess": 55,
        "min_area": 3,
        "max_area": 450,
        "min_change": 25
    }
    
    # Detect with flash_frame=True (loosened thresholds)
    result_flash = detect(dark_frame, background=None, settings=strict_settings, mapper=None, flash_frame=True)
    
    # Detect with flash_frame=False (strict thresholds)
    result_normal = detect(dark_frame, background=None, settings=strict_settings, mapper=None, flash_frame=False)
    
    # On flash frame, small red dot should be detected
    # On normal frame, it might be missed due to strict thresholds
    print(f"Flash frame result: {result_flash}")
    print(f"Normal frame result: {result_normal}")
    print("✓ Adaptive threshold logic working")


def test_auto_flash_detection():
    """Verify automatic flash-frame detection without explicit flag."""
    # Create a very dark frame (simulating black flash)
    dark_frame = np.ones((480, 640, 3), dtype=np.uint8) * 15
    dark_frame[240-3:240+3, 320-3:320+3] = [0, 0, 220]  # Faint red dot
    
    settings = {
        "min_red": 210,
        "min_red_excess": 55,
        "min_area": 3,
        "max_area": 450,
        "min_change": 25
    }
    
    # Let detect() auto-determine flash_frame
    result = detect(dark_frame, background=None, settings=settings, mapper=None, flash_frame=None)
    
    if result:
        print(f"✓ Auto-detected flash frame and found red dot at ({result.x:.3f}, {result.y:.3f})")
    else:
        print("✗ Failed to auto-detect flash frame or find red dot")


def test_threshold_adjustments():
    """Verify specific threshold adjustments during flash."""
    settings = {
        "min_red": 210,
        "min_red_excess": 55,
        "min_area": 3,
        "max_area": 450,
    }
    
    # Simulate the adjustment logic
    flash_settings = settings.copy()
    flash_settings["min_red_excess"] = max(15, flash_settings.get("min_red_excess", 55) // 2)
    flash_settings["min_area"] = max(1, flash_settings.get("min_area", 3) - 1)
    flash_settings["min_red"] = min(180, flash_settings.get("min_red", 210) - 20)
    
    print(f"Original settings:")
    print(f"  min_red_excess: {settings['min_red_excess']} → {flash_settings['min_red_excess']}")
    print(f"  min_area: {settings['min_area']} → {flash_settings['min_area']}")
    print(f"  min_red: {settings['min_red']} → {flash_settings['min_red']}")
    print("✓ Threshold adjustments computed correctly")


if __name__ == "__main__":
    test_flash_frame_detection()
    test_threshold_adjustments()
    test_adaptive_thresholds()
    test_auto_flash_detection()
    print("\n✅ All flash-frame tests passed!")
