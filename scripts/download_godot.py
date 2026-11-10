#!/usr/bin/env python3
"""Download an official stable Godot runner into this checkout's .tools."""
import argparse, hashlib, io, json, platform, urllib.request, zipfile
from pathlib import Path

def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "Gunslinger-prototype"})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default="latest", help="Release tag or latest")
    args = parser.parse_args()
    endpoint = "latest" if args.version == "latest" else "tags/" + args.version
    release = json.loads(fetch("https://api.github.com/repos/godotengine/godot-builds/releases/" + endpoint))
    system, machine = platform.system(), platform.machine()
    if system == "Darwin":
        suffix = "_macos.universal.zip"
    elif system == "Linux":
        arch = {"x86_64":"x86_64", "amd64":"x86_64", "aarch64":"arm64", "arm64":"arm64"}.get(machine)
        if not arch: raise SystemExit("Only Linux x86_64 and ARM64 supported")
        suffix = "_linux." + arch + ".zip"
    else: raise SystemExit("Only Linux and macOS supported")
    asset = next(value for value in release["assets"] if value["name"].endswith(suffix) and "_mono_" not in value["name"])
    print("Downloading", asset["name"], flush=True)
    payload = fetch(asset["browser_download_url"])
    digest = asset.get("digest", "") or ""
    if digest.startswith("sha256:") and hashlib.sha256(payload).hexdigest() != digest.split(":", 1)[1]:
        raise SystemExit("Download checksum mismatch")
    tools = Path(__file__).resolve().parents[1] / ".tools"
    tools.mkdir(exist_ok=True)
    zipfile.ZipFile(io.BytesIO(payload)).extractall(tools)
    binary = tools / "Godot.app/Contents/MacOS/Godot" if system == "Darwin" else tools / asset["name"].removesuffix(".zip")
    binary.chmod(0o755)
    link = tools / "godot"
    if link.is_symlink(): link.unlink()
    link.symlink_to(binary.relative_to(tools))
    (tools / "godot-version.txt").write_text(release["tag_name"] + "\n")
    print("Ready:", link)

if __name__ == "__main__": main()
