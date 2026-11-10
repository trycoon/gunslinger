"""Generate original, reproducible PCM sound effects; no music."""
import math
import random
import struct
import shutil
import subprocess
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "assets" / "audio"

def generate():
    ROOT.mkdir(parents=True, exist_ok=True)
    rng = random.Random(19)
    rate = 22050
    for name, duration in [("shot", .22), ("enemy", .25), ("reload", .32), ("civilian", .36)]:
        samples = []
        for index in range(int(rate * duration)):
            t = index / rate
            if name in ("shot", "enemy"):
                envelope = math.exp(-t * (28 if name == "shot" else 21))
                signal = (.8 * rng.uniform(-1, 1) + .2 * math.sin(2 * math.pi * 85 * t)) * envelope
            elif name == "reload":
                signal = rng.uniform(-1, 1) * sum(math.exp(-max(0, t - start) * 160) if t >= start else 0 for start in (0, .1, .22)) * .5
            else:
                signal = .3 * math.sin(2 * math.pi * (310 * t - 220 * t * t)) * math.sin(math.pi * t / duration)
            samples.append(struct.pack("<h", int(max(-1, min(1, signal)) * 22000)))
        with wave.open(str(ROOT / (name + ".wav")), "wb") as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(rate)
            output.writeframes(b"".join(samples))

    speech = shutil.which("espeak-ng")
    if speech:
        for name, line in [("draw", "Draw!"), ("dont_shoot", "Don't shoot!"), ("got_me", "You got me!")]:
            subprocess.run([speech, "-v", "en-us", "-s", "145", "-p", "28", "-w", str(ROOT / (name + ".wav")), line], check=True)
    else:
        print("Optional speech: install espeak-ng and rerun this script.")

if __name__ == "__main__":
    generate()
