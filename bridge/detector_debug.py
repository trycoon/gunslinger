#!/usr/bin/env python3
"""Debug tool for laser pointer detection analysis and calibration mode."""
import argparse
import cv2
import json
import numpy as np
from pathlib import Path
from detector import detect, Mapper, validate_corners, Detection

def analyze_detection(image_path, output_path=None, detector_settings=None):
    """Analyze laser pointer detection on a single image, showing all steps."""
    frame = cv2.imread(str(image_path))
    if frame is None:
        raise FileNotFoundError(f"Cannot read image: {image_path}")
    
    print(f"Analyzing image: {image_path}")
    print(f"Image size: {frame.shape[1]}x{frame.shape[0]} (WxH)")
    
    # Run detection
    result = detect(frame, background=None, settings=detector_settings or {})
    
    if result:
        print(f"\n✓ Detection found:")
        print(f"  Position (normalized): ({result.x:.4f}, {result.y:.4f})")
        print(f"  Position (pixels): ({result.x * (frame.shape[1]-1):.1f}, {result.y * (frame.shape[0]-1):.1f})")
        print(f"  Strength: {result.strength:.1f}")
    else:
        print("\n✗ No detection found")
    
    # Create debug visualization
    if output_path:
        debug_frame = frame.copy()
        
        # Create HSV mask visualization
        hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
        red_mask = cv2.inRange(hsv, (0, 90, 0), (12, 255, 255)) | cv2.inRange(hsv, (168, 90, 0), (179, 255, 255))
        
        # Create red excess visualization
        blue, green, red = [channel.astype(np.int16) for channel in cv2.split(frame)]
        excess = red - np.maximum(blue, green)
        
        # Mark detection if found
        if result:
            px = int(result.x * (frame.shape[1] - 1))
            py = int(result.y * (frame.shape[0] - 1))
            cv2.circle(debug_frame, (px, py), 15, (0, 255, 0), 2)  # Green circle
            cv2.circle(debug_frame, (px, py), 1, (0, 255, 255), -1)  # Yellow center
            cv2.putText(debug_frame, f"Detection ({result.x:.3f}, {result.y:.3f})", 
                       (px + 20, py - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 1)
        
        # Add grid
        height, width = frame.shape[:2]
        for x in range(0, width, width // 4):
            cv2.line(debug_frame, (x, 0), (x, height), (100, 100, 100), 1)
        for y in range(0, height, height // 4):
            cv2.line(debug_frame, (0, y), (width, y), (100, 100, 100), 1)
        
        # Save output
        cv2.imwrite(str(output_path), debug_frame)
        print(f"\nDebug image saved to: {output_path}")
        
        # Also save mask visualizations
        mask_path = Path(output_path).with_name(Path(output_path).stem + "_mask.png")
        excess_path = Path(output_path).with_name(Path(output_path).stem + "_excess.png")
        cv2.imwrite(str(mask_path), red_mask * 255)
        cv2.imwrite(str(excess_path), np.clip(excess * 2, 0, 255).astype(np.uint8))
        print(f"Red mask saved to: {mask_path}")
        print(f"Red excess saved to: {excess_path}")
    
    return result


def calibration_mode(config_path):
    """Interactive calibration mode: collect points by clicking on laser hits."""
    config_path = Path(config_path)
    
    # Load existing calibration if available
    if config_path.exists():
        config = json.loads(config_path.read_text())
        existing_corners = config.get("corners", [])
        if existing_corners:
            print(f"Loaded existing calibration: {existing_corners}")
    else:
        existing_corners = []
        config = {"corners": [], "camera": {}, "ble": {}, "detector": {}}
    
    print("\n=== Calibration Mode ===")
    print("Click on the crosshairs in the camera view to set calibration corners")
    print("Need 4 points: Top-Left, Top-Right, Bottom-Right, Bottom-Left")
    print("Press 'r' to reset, 's' to save and exit, 'q' to quit without saving\n")
    
    corners = []
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("Error: Cannot open camera")
        return
    
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    
    def mouse_callback(event, x, y, flags, userdata):
        if event == cv2.EVENT_LBUTTONDOWN:
            norm_x = x / (640 - 1)
            norm_y = y / (480 - 1)
            corners.append([norm_x, norm_y])
            print(f"Point {len(corners)}: ({norm_x:.4f}, {norm_y:.4f}) at pixel ({x}, {y})")
            if len(corners) == 4:
                print("4 points collected! Press 's' to save")
    
    cv2.namedWindow('Calibration')
    cv2.setMouseCallback('Calibration', mouse_callback)
    
    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            
            display = frame.copy()
            
            # Draw existing points
            for i, corner in enumerate(corners):
                px = int(corner[0] * 639)
                py = int(corner[1] * 479)
                cv2.circle(display, (px, py), 10, (0, 255, 0), 2)
                cv2.putText(display, str(i + 1), (px + 15, py + 15), 
                           cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 0), 2)
            
            # Draw instructions
            cv2.putText(display, f"Points: {len(corners)}/4", (20, 30),
                       cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)
            cv2.putText(display, "Click to add points (R)eset (S)ave (Q)uit", (20, 70),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.6, (200, 200, 200), 1)
            
            cv2.imshow('Calibration', display)
            
            key = cv2.waitKey(1) & 0xFF
            if key == ord('q'):
                print("Cancelled without saving")
                break
            elif key == ord('r'):
                corners = []
                print("Reset - starting over")
            elif key == ord('s') and len(corners) == 4:
                try:
                    validate_corners(corners)
                    config["corners"] = corners
                    config_path.parent.mkdir(parents=True, exist_ok=True)
                    with open(config_path, 'w') as f:
                        json.dump(config, f, indent=2)
                    print(f"\n✓ Calibration saved to {config_path}")
                    print(f"Corners: {corners}")
                    break
                except ValueError as e:
                    print(f"Validation error: {e}")
    finally:
        cap.release()
        cv2.destroyAllWindows()


def test_detection_with_mapper(image_path, config_path):
    """Test detection with an active calibration mapper."""
    frame = cv2.imread(str(image_path))
    if frame is None:
        raise FileNotFoundError(f"Cannot read image: {image_path}")
    
    config_path = Path(config_path)
    if not config_path.exists():
        print(f"Config not found: {config_path}")
        return
    
    config = json.loads(config_path.read_text())
    corners = config.get("corners", [])
    
    if not corners:
        print("No calibration found in config")
        return
    
    print(f"Loaded calibration: {corners}")
    mapper = Mapper(corners)
    
    result = detect(frame, background=None, settings=config.get("detector"), mapper=mapper)
    
    if result:
        projected = mapper.project((result.x, result.y))
        if projected:
            print(f"✓ Detection found and projected:")
            print(f"  Camera position (normalized): ({result.x:.4f}, {result.y:.4f})")
            print(f"  Screen position (normalized): ({projected[0]:.4f}, {projected[1]:.4f})")
            print(f"  Strength: {result.strength:.1f}")
        else:
            print("Detection found but outside screen bounds")
    else:
        print("No detection found")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Laser detector debugging tool")
    subparsers = parser.add_subparsers(dest="command", help="Command to run")
    
    # Analyze command
    analyze_parser = subparsers.add_parser("analyze", help="Analyze detection on an image")
    analyze_parser.add_argument("image", help="Image file to analyze")
    analyze_parser.add_argument("--output", help="Output debug image with marked detection")
    analyze_parser.add_argument("--min-red", type=int, help="Min red channel value")
    analyze_parser.add_argument("--min-excess", type=int, help="Min red excess value")
    
    # Calibrate command
    cal_parser = subparsers.add_parser("calibrate", help="Interactive calibration mode")
    cal_parser.add_argument("--config", default=str(Path.home() / ".config/gunslinger/bridge.json"),
                           help="Config file to save calibration")
    
    # Test with mapper
    test_parser = subparsers.add_parser("test", help="Test detection with calibration")
    test_parser.add_argument("image", help="Image file to test")
    test_parser.add_argument("--config", default=str(Path.home() / ".config/gunslinger/bridge.json"),
                            help="Config file with calibration")
    
    args = parser.parse_args()
    
    if args.command == "analyze":
        settings = {}
        if args.min_red:
            settings["min_red"] = args.min_red
        if args.min_excess:
            settings["min_red_excess"] = args.min_excess
        analyze_detection(args.image, args.output, settings)
    elif args.command == "calibrate":
        calibration_mode(args.config)
    elif args.command == "test":
        test_detection_with_mapper(args.image, args.config)
    else:
        parser.print_help()
