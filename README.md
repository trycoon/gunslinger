# Gunslinger

Offline western arcade prototype for Godot 4, Ubuntu x86_64 and Raspberry Pi 5
ARM64. Original procedural pixel art and synthesized effects. Short original synthesized English lines; no blood or music.

## Start with a mouse

Open `project.godot` in standard Godot 4 and press F5, or use an official runner:

```sh
python3 scripts/download_godot.py
.tools/godot --headless --path . --editor --import
bash scripts/run.sh
```

Mouse gameplay needs no Python packages, camera or Bluetooth.

* Left mouse: shoot. Right mouse: reload a six-shot magazine (0.85 seconds).
* Escape: pause/resume or menu. F11: fullscreen/windowed.
* Menu buttons cycle input, mode, difficulty and ammunition.
* Lightgun: infinite game ammunition, no game crosshair; mouse still works in menus.
* Civilians have four designs: two men (rancher and merchant) and two women
  (bonnet/apron and straw hat/braid). They wear light blue/mint clothing, remain
  unarmed and have a `SAFE` label. Hitting one costs a life.
* Bandits carry revolvers and have a countdown. They repeatedly fire until defeated.
  Their appearance varies: six hat/headband styles, four outfits,
  masks, moustaches, beards, eye patches and accessories. Each keeps its look
  while on screen; appearance does not change its hitbox or combat behavior.
  All bandits and civilians use the same skin tone.
* Three received hits end the game. Timed mode also ends after 90 seconds.
* Each stage contains **8–12 bandits**, chosen randomly. Civilians are additional
  characters and do not count toward that total. The HUD shows defeated bandits.
* Once all stage bandits have been defeated, the camera scrolls right into the
  next city block: a brief 0.8-second stage-clear display, then a 1.8-second pan.
  Shooting is disabled during the transition; Escape can pause/resume the pan.
* Every block is generated procedurally with 3–4 buildings, varying facades,
  heights, signs, windows and doorways, plus 2–4 crates, barrels or wagons. Targets
  appear in positions derived from the generated cover, rather than fixed slots.
* Lives, score, ammunition and difficulty progression carry between stages.
  Timed mode pauses its 90-second active-play clock during stage transitions.
* Easy/Medium/Hard change spawn rate, reaction time and simultaneous targets;
  difficulty also gradually increases during a run.
* Appearances use random waits, with a 20% chance of a longer wait for suspense.
  The first appearance is randomized too. When two slots are free, encounters
  have an 18% chance of introducing two bandits 0.15–0.35 seconds apart.
  Pairs are only scheduled when at least two bandits remain in the stage quota.
* Defeating a bandit delays the next target appearance by at least 1.5 seconds.
  This also postpones a pending second bandit in a pair. Bandits already visible
  can still fire during this pause. Pairs never exceed the active target limit.
* Bandit: 100 points + up to 100 speed bonus + 75 for headshots.
* Highscore: top ten per mode/difficulty/input/ammo. Type up to eight initials,
  or use the on-screen alphabet with mouse/lightgun, then Save Score.
* Persistent scores/settings: Godot `user://`, normally on Linux
  `~/.local/share/godot/app_userdata/Gunslinger/`.

Starting difficulty settings:

| Difficulty | Time before a bandit fires | Maximum simultaneous targets | Normal wait | Occasional long wait |
| --- | --- | --- | --- | --- |
| Easy | 5.2 seconds | 2 | 2.0–4.0 seconds | 4.5–7.5 seconds |
| Medium (previously Easy) | 3.2 seconds | 2 | 1.5–3.2 seconds | 3.5–6.5 seconds |
| Hard (previously Normal) | 2.3 seconds | 3 | 1.0–2.5 seconds | 3.0–5.0 seconds |

Reaction times and normal waits shorten as the run progresses (normal waits have
a 0.8-second minimum), and the target limit increases. Long waits retain the
ranges above throughout the run. A fresh random wait follows the second bandit
in a pair. Single appearances still have a 23% chance of being a civilian; pairs
always contain two bandits. The 1.5-second post-kill pause stays in effect.

## Simulated camera and lightgun

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r bridge/requirements.txt
.venv/bin/python bridge/bridge.py --mock
```

Start Godot in another terminal. Open **Calibration**, click the four marked
projected corners in the camera preview (TL, TR, BR, BL), then **Save Calibration**.
Choose **Lightgun** in the menu. Place the mouse at the desired shot location
and press **F8**. This renders a temporary laser in the simulated camera, detects
it with OpenCV, maps its position and shoots in the game, including menu buttons.
Mock calibration is separate: `~/.config/gunslinger/mock.json`.

## Hardware target

**Ubuntu Desktop 26.04 LTS, 64-bit** on PC and **Raspberry Pi OS** on Raspberry
Pi 5. Targets: Full HD output, 640x360 game canvas, Compatibility/OpenGL
rendering, 60 game FPS and 640x480/30 camera FPS. Pi performance has not been
measured. Other screen ratios letterbox.

Baseline camera: **Raspberry Pi Camera Module 3, standard visible-light version**,
with a Pi 5 compatible camera cable. USB UVC webcams also work. Consider the Wide
version only if needed to cover the entire projection; corner-only calibration
does not correct lens distortion.

Sources checked 2026-10-12:

* [Ubuntu Pi images](https://ubuntu.com/download/raspberry-pi)
* [Ubuntu camera setup](https://documentation.ubuntu.com/hardware-support/boards/how-to/special_hardware/rpi-camera/)
* [Ubuntu 26.04 Picamera2 package](https://packages.ubuntu.com/resolute/python3-picamera2)
* [Camera Module 3](https://www.raspberrypi.com/products/camera-module-3/)
* [Godot Linux export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_linux.html)
* [Bleak Linux](https://bleak.readthedocs.io/en/latest/backends/linux.html)
* [OpenCV color thresholding](https://docs.opencv.org/4.x/da/d97/tutorial_threshold_inRange.html)

Picamera2 is in Ubuntu 26.04's universe archive. Older camera documentation still
mentions a PPA; use the release's apt packages first.

## Install on Linux and autostart

Internet is needed for installation only. These package names are for Ubuntu
26.04 and Raspberry Pi OS based on Debian 13 (Trixie); other releases may use
different names:

```sh
sudo apt update
sudo apt install python3-venv python3-opencv python3-numpy bluez espeak-ng libgl1 libegl1 \
  libx11-6 libxcursor1 libxinerama1 libxrandr2 libxi6 libasound2t64 libpulse0
# Pi CSI camera only:
sudo apt install python3-picamera2 rpicam-apps

bash scripts/install-linux.sh picamera2  # Pi CSI camera
# or: bash scripts/install-linux.sh opencv  # USB webcam
```

The per-user installer bundles the Godot runner, game, bridge and Python venv
under `~/.local/share/gunslinger`, and adds a launcher and desktop autostart.
Existing `~/.config/gunslinger/bridge.json` is preserved. When switching hardware,
pass the new backend explicitly to the installer; other settings are retained.
For example, rerun `bash scripts/install-linux.sh opencv` for a USB webcam, then
restart the game and recalibrate. Run `~/.local/bin/gunslinger` manually.
Enable **automatic graphical login** in the desktop settings for boot-to-game.
The launcher starts fullscreen and runs/stops its bridge alongside the game.
Logs: `~/.local/state/gunslinger/bridge.log`. Run as the logged-in user with camera
and Bluetooth permissions, not as root. See the [camera setup guide](docs/camera.md)
for backend choices, examples, device selection and troubleshooting.

## Real gun and calibration

1. Upload the ESP32 Arduino example, or implement [BLE protocol v1](docs/protocol.md)
   in your firmware. Wire the trigger between GPIO 33 and 3.3 V; GPIO 33 is
   required for its deep-sleep wake feature. Adapt the laser-driver pin to your
   circuit.
2. Camera/BLE configuration is in `~/.config/gunslinger/bridge.json`. For manual
   testing, if that file does not exist, copy `bridge/config.example.json` there,
   or pass `--config FILE`. Avoid overwriting an existing calibration.
3. Use `camera.backend: picamera2` for CSI; `opencv` for USB. Discovery uses name
   `Gunslinger-ESP32`; set `ble.address` to target a specific gun.
4. Manual bridge startup: `.venv/bin/python bridge/bridge.py --camera picamera2`.
   For Pi cameras create the venv with `/usr/bin/python3 -m venv --system-site-packages`
   and install Bleak in it; use apt's NumPy/OpenCV/Picamera2.
5. In Calibration check the whole projection is visible. Mark **the projected
   image's** four corners in the camera view in the specified order, then Save.
   These need not coincide with the camera sensor's corners.
6. Test corners and center, then start. Recalibrate if camera/projector moves.

Tune `detector` thresholds against the actual laser. Optional Pi camera settings:
`exposure_us`, `gain`, `lens_position` (diopters, e.g. 0.5 for about 2 m) lock
exposure/focus. Avoid a completely white, overexposed spot without a red halo.
The prototype expects one laser and two agreeing detections. It does not perform
lens-distortion correction or hardware exposure/BLE clock synchronization.

## Verification

```sh
.venv/bin/python -m unittest discover -s tests -p 'test_*.py' -v
.tools/godot --headless --path . --editor --import
.tools/godot --headless --path . --script tests/game_rules.gd
.tools/godot --headless --path . --script tests/stages.gd
```

Tests cover detector false positives, perspective mapping, protocol parsing,
calibration persistence, the simulated full shot pipeline and core game rules.
Stage tests validate 200 generated streets, exact bandit quotas, final pairs,
state carried between stages, and pause/clock behavior while scrolling. Mock
lightgun integration also covers clearing a stage and aiming in the next block.
Results/limitations: [docs/validation.md](docs/validation.md).

Linux x86_64 and ARM64 export presets are included. Export templates must match
Godot's version. The bundled-runner installer needs no export templates. Future
filmed targets can retain the bridge's normalized shot protocol.
