#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-$project_dir/.tools/godot}"
if [[ ! -x "$godot_bin" ]]; then
  if command -v godot >/dev/null 2>&1; then godot_bin="$(command -v godot)";
  elif command -v godot4 >/dev/null 2>&1; then godot_bin="$(command -v godot4)";
  else echo 'Godot missing. Run python3 scripts/download_godot.py first.' >&2; exit 1; fi
fi
exec "$godot_bin" --path "$project_dir" "$@"
