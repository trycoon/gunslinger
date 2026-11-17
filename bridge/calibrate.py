#!/usr/bin/env python3
"""
Enhanced calibration tool with real-time laser detection debugging.

Workflow:
1. Live camera feed with marked laser hits
2. Click to set calibration corners
3. Visual feedback shows detection thresholds
4. Save calibration with detector settings tuned for your hardware
"""
import argparse
import asyncio
import cv2
import json
import numpy as np
from pathlib import Path
import time

from detector import detect, Mapper, validate_corners


def test_detection_live(config_path=None, test_image=None):
    """
    Live detection testing with adjustable thresholds.
    Use mouse wheel or +/- keys to adjust thresholds in real-time.
    """
    config_path = Path(config_path or Path.home() / ".config/gunslinger/bridge.json")
    
    # Load config
    config = {"corners": [], "camera": {}, "ble": {}, "detector": {}}
    if config_path.exists():
        config = json.loads(config_path.read_text())
        print(f"Loaded config: {config_path}")
    
    corners = config.get("corners", [])
    mapper = Mapper(corners) if corners else None
    detector_settings = config.get("detector", {})
    
    # Start with current settings or defaults
    min_red = detector_settings.get("min_red", 210)
    min_excess = detector_settings.get("min_red_excess", 55)
    min_area = detector_settings.get("min_area", 3)
    max_area = detector_settings.get("max_area", 450)
    
    print("\n" + "="*70)
    print("LASER DETECTION LIVE TEST")
    print("="*70)
    print(f"\nInitial Settings:")
    print(f"  min_red: {min_red}  (use 'W'/'S' to adjust)")
    print(f"  min_excess: {min_excess}  (use 'D'/'A' to adjust)")
    print(f"  min_area: {min_area}, max_area: {max_area}")
    if mapper:
        print(f"  Calibration: {len(corners)} corners set")
    else:
        print(f"  Calibration: NOT SET (run --calibrate first)")
    
    print("\nControls:")
    print("  W/S - adjust min_red (brightness)")
    print("  A/D - adjust min_excess (red-ness)")
    print("  +/- - adjust area limits")
    print("  R - reset to defaults")
    print("  SPACE - save current settings")
    print("  Q - quit without saving")
    print("="*70 + "\n")
    
    # Setup camera or test image
    if test_image:
        frame = cv2.imread(str(test_image))
        if frame is None:
            raise FileNotFoundError(f"Cannot read test image: {test_image}")
        capture_once = frame.copy()
        source = "test_image"
    else:
        cap = cv2.VideoCapture(0)
        if not cap.isOpened():
            print("Error: Cannot open camera")
            return
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
        capture_once = None
        source = "camera"
    
    cv2.namedWindow('Detection Test')
    detection_history = []
    
    try:
        frame_count = 0
        while True:
            frame_count += 1
            
            if capture_once is not None:
                frame = capture_once.copy()
            else:
                ret, frame = cap.read()
                if not ret:
                    break
            
            # Run detection
            settings = {
                "min_red": min_red,
                "min_red_excess": min_excess,
                "min_area": min_area,
                "max_area": max_area
            }
            result = detect(frame, background=None, settings=settings, mapper=mapper)
            
            # Visualize
            display = frame.copy()
            height, width = frame.shape[:2]
            
            # Draw grid
            for x in range(0, width, width // 4):
                cv2.line(display, (x, 0), (x, height), (50, 50, 50), 1)
            for y in range(0, height, height // 4):
                cv2.line(display, (0, y), (width, y), (50, 50, 50), 1)
            
            # Draw calibration corners
            if mapper:
                for i, corner in enumerate(corners):
                    px = int(corner[0] * (width - 1))
                    py = int(corner[1] * (height - 1))
                    cv2.circle(display, (px, py), 8, (0, 200, 200), 2)
                    cv2.putText(display, str(i+1), (px+15, py+15), 
                               cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 200, 200), 2)
            
            # Draw detection
            if result:
                px = int(result.x * (width - 1))
                py = int(result.y * (height - 1))
                cv2.circle(display, (px, py), 20, (0, 255, 0), 2)
                cv2.circle(display, (px, py), 1, (0, 255, 255), -1)
                
                # Draw projected point if mapped
                if mapper:
                    proj = mapper.project((result.x, result.y))
                    if proj:
                        screen_x = int(proj[0] * (width - 1))
                        screen_y = int(proj[1] * (height - 1))
                        cv2.circle(display, (screen_x, screen_y), 25, (255, 0, 0), 2)
                        cv2.line(display, (px, py), (screen_x, screen_y), (200, 200, 200), 1)
                
                detection_history.append({
                    'time': time.time(),
                    'x': result.x,
                    'y': result.y,
                    'strength': result.strength
                })
                # Keep last 30 frames
                if len(detection_history) > 30:
                    detection_history.pop(0)
            
            # Draw info overlay
            info = [
                f"min_red: {min_red}  min_excess: {min_excess}",
                f"area: {min_area}-{max_area}",
                f"Detections (30s window): {len(detection_history)}",
            ]
            if result:
                info.append(f"Current: ({result.x:.3f}, {result.y:.3f}) strength={result.strength:.0f}")
                if mapper and mapper.project((result.x, result.y)):
                    proj = mapper.project((result.x, result.y))
                    info.append(f"Projected: ({proj[0]:.3f}, {proj[1]:.3f})")
            
            for i, text in enumerate(info):
                cv2.putText(display, text, (10, 30 + i*25),
                           cv2.FONT_HERSHEY_SIMPLEX, 0.6, (200, 200, 200), 1)
            
            cv2.imshow('Detection Test', display)
            
            key = cv2.waitKey(1) & 0xFF
            if key == ord('q'):
                print("\nCancelled - settings not saved")
                break
            elif key == ord('w'):
                min_red = min(255, min_red + 5)
                print(f"min_red -> {min_red}")
            elif key == ord('s'):
                min_red = max(0, min_red - 5)
                print(f"min_red -> {min_red}")
            elif key == ord('d'):
                min_excess = min(255, min_excess + 5)
                print(f"min_excess -> {min_excess}")
            elif key == ord('a'):
                min_excess = max(0, min_excess - 5)
                print(f"min_excess -> {min_excess}")
            elif key == ord('r'):
                min_red, min_excess = 210, 55
                print(f"Reset to defaults: min_red={min_red}, min_excess={min_excess}")
            elif key == ord(' '):
                config["detector"] = settings
                config_path.parent.mkdir(parents=True, exist_ok=True)
                with open(config_path, 'w') as f:
                    json.dump(config, f, indent=2)
                print(f"\n✓ Detector settings saved to {config_path}")
                print(f"  min_red: {min_red}")
                print(f"  min_excess: {min_excess}")
                print(f"  Detections captured: {len(detection_history)}")
            elif key == ord('+') or key == ord('='):
                max_area = min(500, max_area + 10)
                print(f"max_area -> {max_area}")
            elif key == ord('-') or key == ord('_'):
                min_area = max(1, min_area - 1)
                print(f"min_area -> {min_area}")
            
            # Exit if test image (single frame)
            if test_image:
                break
                
    finally:
        if source == "camera":
            cap.release()
        cv2.destroyAllWindows()


def interactive_calibration(config_path=None):
    """
    Interactive calibration mode: click on the four projector screen corners.
    Then uses live laser detection to verify calibration accuracy.
    """
    config_path = Path(config_path or Path.home() / ".config/gunslinger/bridge.json")
    
    config = {"corners": [], "camera": {}, "ble": {}, "detector": {}}
    if config_path.exists():
        try:
            config = json.loads(config_path.read_text())
            print(f"Loaded existing config: {config_path}")
        except:
            pass
    
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("Error: Cannot open camera")
        return
    
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    
    corners = []
    
    print("\n" + "="*70)
    print("CALIBRATION MODE - Set 4 Corners")
    print("="*70)
    print("Click on each corner in this order:")
    print("  1. Top-Left of projected screen")
    print("  2. Top-Right of projected screen")
    print("  3. Bottom-Right of projected screen")
    print("  4. Bottom-Left of projected screen")
    print("\nThen press SPACE to verify, R to reset, Q to cancel")
    print("="*70 + "\n")
    
    def mouse_callback(event, x, y, flags, userdata):
        if event == cv2.EVENT_LBUTTONDOWN:
            norm_x = x / 639.0
            norm_y = y / 479.0
            corners.append([norm_x, norm_y])
            print(f"Corner {len(corners)}: ({norm_x:.4f}, {norm_y:.4f})")
            if len(corners) == 4:
                print("4 corners set! Press SPACE to verify.")
    
    cv2.namedWindow('Calibration')
    cv2.setMouseCallback('Calibration', mouse_callback)
    
    try:
        step = "setting_corners"  # or "verifying"
        verified = False
        
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            
            display = frame.copy()
            height, width = 480, 640
            
            # Draw grid
            for x in range(0, width, width // 4):
                cv2.line(display, (x, 0), (x, height), (100, 100, 100), 1)
            for y in range(0, height, height // 4):
                cv2.line(display, (0, y), (width, y), (100, 100, 100), 1)
            
            # Draw existing corners
            for i, corner in enumerate(corners):
                px = int(corner[0] * 639)
                py = int(corner[1] * 479)
                cv2.circle(display, (px, py), 12, (0, 255, 0), 2)
                cv2.putText(display, str(i+1), (px+20, py+20),
                           cv2.FONT_HERSHEY_SIMPLEX, 1.2, (0, 255, 0), 2)
            
            # Draw instructions
            status_text = f"Corners: {len(corners)}/4"
            if len(corners) == 4:
                status_text += " - Press SPACE to verify"
            
            cv2.putText(display, status_text, (10, 30),
                       cv2.FONT_HERSHEY_SIMPLEX, 1, (200, 200, 200), 2)
            cv2.putText(display, "(R)eset  (Q)uit", (10, 70),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.7, (150, 150, 150), 1)
            
            cv2.imshow('Calibration', display)
            
            key = cv2.waitKey(1) & 0xFF
            if key == ord('q'):
                print("\nCancelled - calibration not saved")
                break
            elif key == ord('r'):
                corners = []
                print("Reset - starting over")
            elif key == ord(' ') and len(corners) == 4:
                try:
                    validate_corners(corners)
                    mapper = Mapper(corners)
                    config["corners"] = corners
                    config_path.parent.mkdir(parents=True, exist_ok=True)
                    with open(config_path, 'w') as f:
                        json.dump(config, f, indent=2)
                    print(f"\n✓ Calibration saved!")
                    print(f"  Corners: {corners}")
                    print(f"  Config: {config_path}")
                    print("\nNow run with --test to verify laser detection accuracy")
                    break
                except ValueError as e:
                    print(f"\n✗ Validation error: {e}")
                    print("Try again with different corners")
                    corners = []
    
    finally:
        cap.release()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Calibration and laser detection debugging tool",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Interactive calibration with live camera
  %(prog)s --calibrate
  
  # Test/tune detection with live camera (adjust thresholds in real-time)
  %(prog)s --test
  
  # Test/tune detection with a test image
  %(prog)s --test --image gunslinger-laser-test.jpg
  
  # Analyze detection on static image (without live UI)
  python3 detector_debug.py analyze gunslinger-laser-test.jpg --output debug.jpg
        """)
    
    parser.add_argument("--calibrate", action="store_true",
                       help="Start interactive calibration mode")
    parser.add_argument("--test", action="store_true",
                       help="Start detection testing/tuning mode")
    parser.add_argument("--image", help="Test image file (for --test mode)")
    parser.add_argument("--config", default=str(Path.home() / ".config/gunslinger/bridge.json"),
                       help="Config file path (default: ~/.config/gunslinger/bridge.json)")
    
    args = parser.parse_args()
    
    if args.calibrate:
        interactive_calibration(args.config)
    elif args.test:
        test_detection_live(args.config, args.image)
    else:
        parser.print_help()
