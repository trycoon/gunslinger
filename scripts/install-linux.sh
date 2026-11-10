#!/usr/bin/env bash
# Per-user installation on Ubuntu 26.04 LTS. No root application process.
set -euo pipefail
if [[ "$(uname -s)" != Linux ]]; then echo 'Run this installer on Linux.' >&2; exit 1; fi
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
install_dir="$HOME/.local/share/gunslinger"
config_dir="$HOME/.config/gunslinger"
camera_backend="${1:-opencv}"
case "$camera_backend" in opencv|picamera2|mock) ;; *) echo 'Use opencv, picamera2 or mock.' >&2; exit 1;; esac
/usr/bin/python3 -c 'import cv2, numpy' || { echo 'Install python3-opencv python3-numpy first (see README).' >&2; exit 1; }
if [[ "$camera_backend" == picamera2 ]]; then /usr/bin/python3 -c 'import picamera2'; fi
if [[ ! -x "$project_dir/.tools/godot" ]] || ! "$project_dir/.tools/godot" --headless --version >/dev/null 2>&1; then
  /usr/bin/python3 "$project_dir/scripts/download_godot.py"
fi
mkdir -p "$install_dir" "$config_dir" "$HOME/.local/bin" "$HOME/.config/autostart" "$HOME/.local/share/applications"
for item in project.godot scenes scripts bridge assets; do cp -R "$project_dir/$item" "$install_dir/"; done
mkdir -p "$install_dir/.tools"
cp -L "$project_dir/.tools/godot" "$install_dir/.tools/godot"
chmod +x "$install_dir/.tools/godot" "$install_dir/scripts/run.sh"
/usr/bin/python3 -m venv --system-site-packages "$install_dir/.venv"
"$install_dir/.venv/bin/python" -m pip install 'bleak>=1.0,<4'
"$install_dir/.venv/bin/python" "$install_dir/scripts/generate_audio.py"
"$install_dir/.tools/godot" --headless --path "$install_dir" --editor --import
INSTALL_DIR="$install_dir" CONFIG_DIR="$config_dir" CAMERA_BACKEND="$camera_backend" /usr/bin/python3 - <<'SETUP'
import json, os
from pathlib import Path
installation = Path(os.environ['INSTALL_DIR'])
configuration = Path(os.environ['CONFIG_DIR'])
backend = os.environ['CAMERA_BACKEND']
config_path = configuration / 'bridge.json'
if not config_path.exists():
    config = json.loads((installation / 'bridge/config.example.json').read_text())
    config['camera']['backend'] = backend
    config['ble']['enabled'] = backend != 'mock'
    config_path.write_text(json.dumps(config, indent=2) + '\n')
launcher = installation / 'launch.sh'
launcher.write_text("""#!/usr/bin/env bash
set -euo pipefail
install_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$HOME/.local/state/gunslinger"
"$install_dir/.venv/bin/python" "$install_dir/bridge/bridge.py" >"$HOME/.local/state/gunslinger/bridge.log" 2>&1 &
bridge_pid=$!
cleanup() { kill "$bridge_pid" 2>/dev/null || true; }
trap cleanup EXIT INT TERM
"$install_dir/.tools/godot" --path "$install_dir" --fullscreen
""")
launcher.chmod(0o755)
quoted = str(launcher).replace('\\', '\\\\').replace('"', '\\"').replace('$', '\\$').replace('`', '\\`')
entry = '[Desktop Entry]\nType=Application\nName=Gunslinger\nComment=Western arcade shooting game\nExec="' + quoted + '"\nTerminal=false\nCategories=Game;\nX-GNOME-Autostart-enabled=true\n'
for directory in (Path.home()/'.config/autostart', Path.home()/'.local/share/applications'):
    (directory/'gunslinger.desktop').write_text(entry)
command = Path.home()/'.local/bin/gunslinger'
if command.is_symlink(): command.unlink()
command.symlink_to(launcher)
SETUP
echo "Installed in $install_dir. Launch with $HOME/.local/bin/gunslinger."
echo 'Autostart runs at graphical login; enable Ubuntu automatic login for boot-to-game.'
