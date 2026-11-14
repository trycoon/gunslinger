# Camera setup and troubleshooting

The camera bridge is a separate Python process, not a physical camera adapter.
It captures frames, detects the laser after a Bluetooth trigger, and sends
status and shot events to Godot. It also provides the calibration preview over
local HTTP. Detecting a camera with `lsusb` or `dmesg` confirms only that
Linux sees the hardware; the bridge must also start and capture frames.

## Choose a backend

| Camera | Backend | Notes |
| --- | --- | --- |
| USB UVC webcam | `opencv` | Uses an OpenCV video device, normally `0` for `/dev/video0`. |
| Raspberry Pi CSI camera | `picamera2` | Uses Picamera2/libcamera; install `python3-picamera2`. |
| No camera, simulated test | `mock` | Generates a simulated image and laser; see [simulated camera](../README.md#simulated-camera-and-lightgun). |

Use `opencv` for a USB webcam even on a Raspberry Pi. Libcamera may list a USB
webcam, but that does not make it a CSI camera; Picamera2's requested controls
may not be available on it.

From the project checkout, install the appropriate backend:

```sh
bash scripts/install-linux.sh opencv    # USB webcam
# or
bash scripts/install-linux.sh picamera2 # Pi CSI camera
```

See the [Linux installation instructions](../README.md#install-on-linux-and-autostart)
for required packages. Raspberry Pi OS based on Debian 13 (Trixie) uses the
listed package names; availability may differ on other releases. The installer
copies the game and bridge to `~/.local/share/gunslinger`. Passing a backend
explicitly updates that setting in an existing configuration without changing
the other settings; omitting it preserves an existing configuration. Restart
the game after changing the configuration. Switching to `mock` in an existing
configuration does not automatically change its BLE setting.

## Configure the camera

The installed launcher reads `~/.config/gunslinger/bridge.json`.
[`bridge/config.example.json`](../bridge/config.example.json) is a complete USB
example. For manual setup, copy it only if the destination does not exist:

```sh
mkdir -p ~/.config/gunslinger
cp -n bridge/config.example.json ~/.config/gunslinger/bridge.json
```

The examples below show only the **`camera` object**, not the entire
configuration. Replace or edit that object in `bridge.json`; keep the existing
`ble`, `detector` and `corners` entries. Recalibrate when changing the camera
or its position.

USB webcam:

```json
{
  "backend": "opencv",
  "device": 0,
  "width": 640,
  "height": 480,
  "fps": 30
}
```

Pi CSI camera, with optional manual exposure and focus:

```json
{
  "backend": "picamera2",
  "width": 640,
  "height": 480,
  "fps": 30,
  "exposure_us": 10000,
  "gain": 1.0,
  "lens_position": 0.5
}
```

Omit the optional controls to use the camera's automatic behavior. A positive
`exposure_us` disables auto exposure and applies that exposure in microseconds
and `gain` (default `1.0`). `lens_position` disables autofocus and sets focus
in diopters; `0.5` is approximately 2 m. These controls are only applied by
the Picamera2 backend and must be supported by the camera. Tune them for the
actual scene and laser.

`width`, `height` and `fps` default to 640, 480 and 30. The bridge accepts
widths from 160 to 1920, heights from 120 to 1080 and frame rates from 1 to 120.
These are software limits, not guarantees of camera support: a device may
reject or adjust a requested mode, and OpenCV properties may not be honored.

### Find a USB video device

If needed, install `v4l-utils`, then list video devices:

```sh
v4l2-ctl --list-devices
ls -l /dev/video*
```

Identify the webcam and try its capture device: for example, `/dev/video2`
corresponds to `"device": 2`. A webcam may expose multiple nodes, including
non-capture nodes; not every listed node will work. Device numbers can change
when devices are connected or removed. Make sure the game user can access the
device. Restart the game after changing the index.

## Check the bridge

The installed launcher starts the bridge alongside the game. With the game
running, run these commands **on the same machine**:

```sh
cat ~/.local/state/gunslinger/bridge.log
curl -fsS http://127.0.0.1:4244/status
curl -fsS -o /tmp/gunslinger-frame.jpg http://127.0.0.1:4244/frame.jpg
```

The status reports the camera backend, BLE state and whether calibration is
saved. A successful frame request saves a JPEG preview; open it to check the
image. `BLE searching` is separate from camera availability. If the HTTP
request cannot connect, the bridge may not be running or may have exited
during startup; inspect the log for the actual error. If `/status` works but
the frame request fails, check the camera status and permissions.

Common problems:

* **`Camera bridge unavailable` or `Camera bridge offline`:** Check the log and
  local status endpoint. The game itself can start even when the bridge fails.
* **`FrameDurationLimits is not advertised by libcamera`:** Check that a USB
  webcam is configured as `opencv`, not `picamera2`. For a CSI camera, inspect
  its available controls and the log; not every device supports every setting.
* **Cannot open USB camera:** Check the selected index, device permissions and
  whether another application is using the camera. Close competing camera
  applications before retrying.
* **No fresh camera frame:** The bridge is reachable but has no recent frame.
  Check its status, camera connection, device index and log.
* **CSI camera not detected:** Check the cable and camera connection. If
  installed, `rpicam-hello --list-cameras` can help inspect libcamera's view.
  A camera listed there is not necessarily usable with the requested controls.

After changing settings, close and restart the game, then open **Calibration**.
Ensure the full projected image is visible, select its corners in TL, TR, BR,
BL order and save. Test corners and center with the real laser and tune the
detector as necessary.
