#!/usr/bin/env python3
"""Initialize bridge settings or explicitly switch the camera backend."""
import argparse
import json
from pathlib import Path


def configure(path, example, backend=None):
    if path.exists():
        if backend is None:
            return
        config = json.loads(path.read_text())
        config.setdefault("camera", {})["backend"] = backend
    else:
        config = json.loads(example.read_text())
        config["camera"]["backend"] = backend or "opencv"
        config["ble"]["enabled"] = backend != "mock"
    path.write_text(json.dumps(config, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path)
    parser.add_argument("example", type=Path)
    parser.add_argument("--backend", choices=("opencv", "picamera2", "mock"))
    args = parser.parse_args()
    configure(args.path, args.example, args.backend)


if __name__ == "__main__":
    main()
