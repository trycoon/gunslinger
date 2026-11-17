#!/usr/bin/env python3
"""Deep analysis of detection thresholds to find the actual laser dot."""
import cv2
import numpy as np
from pathlib import Path

def pixel_analysis(image_path):
    """Analyze the actual pixel values at key locations."""
    frame = cv2.imread(str(image_path))
    if frame is None:
        raise FileNotFoundError(f"Cannot read image: {image_path}")
    
    h, w = frame.shape[:2]
    
    # Locations to analyze
    points = {
        "Actual laser (manual)": (468, 462),  # center-left red dot position in original
        "Light blue circle": (2047, 196),      # top circle that's being detected
        "Background tan": (1000, 400),         # neutral background
    }
    
    print("Pixel Analysis (BGR format)")
    print("=" * 70)
    
    for name, (px, py) in points.items():
        if px >= w or py >= h:
            print(f"{name}: OUTSIDE IMAGE")
            continue
        
        b, g, r = frame[py, px]
        hsv = cv2.cvtColor(frame[py:py+1, px:px+1], cv2.COLOR_BGR2HSV)[0, 0]
        h_hsv, s, v = hsv
        
        excess = int(r) - max(int(b), int(g))
        
        print(f"\n{name} at pixel ({px}, {py}):")
        print(f"  BGR: B={b:3d} G={g:3d} R={r:3d}")
        print(f"  HSV: H={h_hsv:3d} S={s:3d} V={v:3d}")
        print(f"  Red excess (R - max(B,G)): {excess:3d}")
        print(f"  Red channel meets min_red (210)? {r >= 210}")
        print(f"  Excess meets min_excess (55)? {excess >= 55}")
        print(f"  Is red in HSV range? {(h_hsv <= 12 or h_hsv >= 168) and s >= 90}")


def threshold_sweep(image_path, output_dir):
    """Create visualizations for different threshold combinations."""
    frame = cv2.imread(str(image_path))
    if frame is None:
        raise FileNotFoundError(f"Cannot read image: {image_path}")
    
    h, w = frame.shape[:2]
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
    blue, green, red = [channel.astype(np.int16) for channel in cv2.split(frame)]
    excess = red - np.maximum(blue, green)
    
    # Test different threshold combinations
    configs = [
        {"min_red": 210, "min_excess": 55, "name": "Current (210, 55)"},
        {"min_red": 180, "min_excess": 40, "name": "Lower (180, 40)"},
        {"min_red": 200, "min_excess": 30, "name": "Moderate (200, 30)"},
        {"min_red": 220, "min_excess": 70, "name": "Stricter (220, 70)"},
    ]
    
    for config in configs:
        min_r = config["min_red"]
        min_e = config["min_excess"]
        
        red_mask = cv2.inRange(hsv, (0, 90, 0), (12, 255, 255)) | cv2.inRange(hsv, (168, 90, 0), (179, 255, 255))
        mask = (red_mask > 0) & (red >= min_r) & (excess >= min_e)
        
        # Find connected components
        count, labels, stats, centroids = cv2.connectedComponentsWithStats(mask.astype(np.uint8), 8)
        
        # Visualize
        result = frame.copy()
        
        # Draw all detections in this threshold
        for label in range(1, count):
            x, y, w_comp, h_comp, area = stats[label]
            if 3 <= area <= 450 and max(w_comp, h_comp) / max(1, min(w_comp, h_comp)) <= 3.5:
                cx, cy = int(centroids[label][0]), int(centroids[label][1])
                cv2.circle(result, (cx, cy), 15, (0, 255, 0), 2)
                cv2.rectangle(result, (x, y), (x+w_comp, y+h_comp), (0, 200, 0), 1)
        
        output_file = output_dir / f"threshold_{config['name'].replace(' ', '_').replace('(', '').replace(')', '')}.png"
        cv2.imwrite(str(output_file), result)
        
        # Count actual matches
        valid_count = sum(1 for label in range(1, count)
                         if 3 <= stats[label][4] <= 450 
                         and max(stats[label][2], stats[label][3]) / max(1, min(stats[label][2], stats[label][3])) <= 3.5)
        
        print(f"{config['name']:25s} -> {valid_count:2d} valid detections (total blobs: {count-1})")
        print(f"  Output: {output_file.name}")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Deep analysis of laser detection")
    parser.add_argument("image", help="Image file to analyze")
    parser.add_argument("--sweep", action="store_true", help="Run threshold sweep")
    
    args = parser.parse_args()
    
    pixel_analysis(args.image)
    
    if args.sweep:
        output = Path(args.image).parent / "threshold_analysis"
        print(f"\n\nThreshold Sweep (output to {output}):")
        print("=" * 70)
        threshold_sweep(args.image, output)
