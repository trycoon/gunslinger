#!/usr/bin/env python3
"""
Create visual calibration markers on camera frames.
Useful for understanding detection accuracy before/after tuning.
"""
import argparse
import cv2
import json
import numpy as np
from pathlib import Path
import threading
import time
from collections import deque

from detector import detect, Mapper, validate_corners


class MarkerRecorder:
    """Records camera frames with detection markers for review."""
    
    def __init__(self, output_dir, duration=10, config_path=None):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.duration = duration
        self.frames_to_capture = []
        self.lock = threading.Lock()
        self.stop_event = threading.Event()
        
        # Load config
        config_path = Path(config_path or Path.home() / ".config/gunslinger/bridge.json")
        self.config = {}
        if config_path.exists():
            self.config = json.loads(config_path.read_text())
        
        self.corners = self.config.get("corners", [])
        self.mapper = Mapper(self.corners) if self.corners else None
        self.detector_settings = self.config.get("detector", {})
    
    def capture_and_mark(self):
        """Capture frames from camera and mark detections."""
        cap = cv2.VideoCapture(0)
        if not cap.isOpened():
            print("Error: Cannot open camera")
            return
        
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
        cap.set(cv2.CAP_PROP_FPS, 30)
        
        print(f"\nCapturing {self.duration}s of marked frames...")
        print("Point your laser at different areas of the screen")
        print("Press 'M' in the preview to mark a frame, 'Q' to stop")
        
        cv2.namedWindow('Live Preview')
        
        start_time = time.time()
        frame_num = 0
        detections = []
        
        try:
            while time.time() - start_time < self.duration:
                ret, frame = cap.read()
                if not ret:
                    continue
                
                frame_num += 1
                
                # Run detection
                result = detect(frame, background=None, 
                              settings=self.detector_settings, 
                              mapper=self.mapper)
                
                # Create marked version
                marked = frame.copy()
                height, width = frame.shape[:2]
                
                # Grid
                for x in range(0, width, width // 4):
                    cv2.line(marked, (x, 0), (x, height), (50, 50, 50), 1)
                for y in range(0, height, height // 4):
                    cv2.line(marked, (0, y), (width, y), (50, 50, 50), 1)
                
                # Draw detection
                if result:
                    px = int(result.x * (width - 1))
                    py = int(result.y * (height - 1))
                    cv2.circle(marked, (px, py), 20, (0, 255, 0), 2)
                    cv2.circle(marked, (px, py), 1, (0, 255, 255), -1)
                    
                    detections.append({
                        'frame': frame_num,
                        'camera_x': result.x,
                        'camera_y': result.y,
                        'strength': result.strength,
                        'screen_x': None,
                        'screen_y': None
                    })
                    
                    if self.mapper:
                        proj = self.mapper.project((result.x, result.y))
                        if proj:
                            detections[-1]['screen_x'] = proj[0]
                            detections[-1]['screen_y'] = proj[1]
                            screen_px = int(proj[0] * (width - 1))
                            screen_py = int(proj[1] * (height - 1))
                            cv2.circle(marked, (screen_px, screen_py), 25, (255, 0, 0), 2)
                
                # Time info
                elapsed = time.time() - start_time
                cv2.putText(marked, f"Frame: {frame_num}  {elapsed:.1f}s", (10, 30),
                           cv2.FONT_HERSHEY_SIMPLEX, 0.6, (200, 200, 200), 1)
                if result:
                    cv2.putText(marked, f"Detection: ({result.x:.3f}, {result.y:.3f})", (10, 60),
                               cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 1)
                cv2.putText(marked, "Press 'M' to mark, 'Q' to quit", (10, height-10),
                           cv2.FONT_HERSHEY_SIMPLEX, 0.5, (150, 150, 150), 1)
                
                cv2.imshow('Live Preview', marked)
                
                key = cv2.waitKey(1) & 0xFF
                if key == ord('q'):
                    break
                elif key == ord('m'):
                    with self.lock:
                        self.frames_to_capture.append({
                            'frame': frame.copy(),
                            'marked': marked.copy(),
                            'num': frame_num,
                            'detection': result,
                            'time': elapsed
                        })
                    print(f"  → Marked frame {frame_num}")
        
        finally:
            cap.release()
            cv2.destroyAllWindows()
        
        return self.frames_to_capture, detections
    
    def save_marked_frames(self, frames):
        """Save all marked frames to disk."""
        if not frames:
            print("No frames marked")
            return
        
        summary_lines = []
        
        for i, data in enumerate(frames):
            # Save original
            orig_path = self.output_dir / f"{i:03d}_frame_{data['num']:05d}.jpg"
            cv2.imwrite(str(orig_path), data['frame'])
            
            # Save marked version
            marked_path = self.output_dir / f"{i:03d}_frame_{data['num']:05d}_marked.jpg"
            cv2.imwrite(str(marked_path), data['marked'])
            
            info_line = f"Frame {data['num']:5d} at {data['time']:.2f}s"
            if data['detection']:
                det = data['detection']
                info_line += f" | Camera: ({det.x:.4f}, {det.y:.4f}) strength={det.strength:.0f}"
            
            summary_lines.append(info_line)
            print(f"  Saved: {marked_path.name}")
        
        # Write summary
        summary_path = self.output_dir / "MARKERS.txt"
        summary_path.write_text("\n".join(summary_lines) + "\n")
        
        print(f"\n✓ Saved {len(frames)} marked frames to {self.output_dir}")
        print(f"  Summary: {summary_path.name}")


def main():
    parser = argparse.ArgumentParser(
        description="Record camera frames with laser detection markers",
        epilog="""
Example:
  python3 marker_recorder.py --output markers --duration 15
  
  Then:
  - Point laser at different screen positions
  - Press 'M' to mark each frame showing detection
  - Press 'Q' when done
  - View saved marked frames in the markers/ directory
        """)
    
    parser.add_argument("--output", default="markers",
                       help="Output directory for marked frames (default: markers/)")
    parser.add_argument("--duration", type=int, default=10,
                       help="Capture duration in seconds (default: 10)")
    parser.add_argument("--config", default=str(Path.home() / ".config/gunslinger/bridge.json"),
                       help="Config file with calibration")
    
    args = parser.parse_args()
    
    recorder = MarkerRecorder(args.output, args.duration, args.config)
    frames, detections = recorder.capture_and_mark()
    
    if frames:
        print(f"\nSaving {len(frames)} marked frames...")
        recorder.save_marked_frames(frames)
        
        # Print detection statistics
        if detections:
            print(f"\nDetection Statistics:")
            print(f"  Total detections: {len(detections)}")
            if any(d['screen_x'] is not None for d in detections):
                valid_projections = [d for d in detections if d['screen_x'] is not None]
                print(f"  Valid projections: {len(valid_projections)}")
                avg_strength = sum(d['strength'] for d in detections) / len(detections)
                print(f"  Average strength: {avg_strength:.1f}")
    else:
        print("No frames marked")


if __name__ == "__main__":
    main()
