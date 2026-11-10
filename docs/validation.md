# Prototype validation — 2026-10-12

Validation ran on the available **macOS ARM64 / Apple M1 Max** development host,
not on an Ubuntu computer or a physical Raspberry Pi. Godot 4.7.2 stable,
Python 3.12.7, NumPy 2.5.4, OpenCV 4.14.0 and Bleak 3.0.2 were used.

| Check | Result | Evidence |
| --- | --- | --- |
| Godot project import and main-scene startup | PASS | Successful import and headless scene run |
| Game rules | PASS | 17 checks, zero failures, clean shutdown |
| Detector/protocol/config/integration suite | PASS | 14 unittest tests, zero failures |
| Camera preview inside Godot calibration menu | PASS | Actual HTTP JPEG request -> Godot ImageTexture |
| Four-corner UI calibration and saving | PASS | Simulated preview clicks -> HTTP -> persisted JSON |
| Lightgun menu selection | PASS | Mock laser -> OpenCV -> mapped UDP -> Start Game |
| Lightgun target hit | PASS | Mock laser -> OpenCV -> UDP -> Godot headshot/score/removal |
| Duplicate and expired shots | PASS | UDP events rejected in the running Godot scene |
| Score and settings persistence | PASS | Actual disk write and reload using isolated test paths |
| Menu/game/game-over rendering | PASS | Rendered using real OpenGL Compatibility, visually inspected |
| Original effects and speech | PASS | Seven WAV files generated and imported into Godot |
| Shell and Python syntax | PASS | bash -n and compileall |
| Ubuntu installation/autostart | NOT RUN | Script provided and syntax checked; no Ubuntu host attached |
| Linux x86_64/ARM64 exports | NOT RUN | Presets provided; target export templates not downloaded |
| ESP32 firmware compilation/real BLE | NOT RUN | Example supplied; board/toolchain not attached |
| USB/CSI camera and real projector/laser | NOT RUN | Physical hardware not attached |
| 60 FPS and shot latency on Pi 5 | NOT RUN | Performance targets only |

Test commands:

```sh
.venv/bin/python -m unittest discover -s tests -p 'test_*.py' -v
.tools/godot --headless --path . --script tests/game_rules.gd
bash -n scripts/run.sh scripts/install-linux.sh
.venv/bin/python -m compileall -q bridge scripts tests
.tools/godot --path . --script tests/capture.gd
```

The Python suite includes a Godot subprocess for the full camera/menu/target
integration when `.tools/godot` is available (or `GODOT_BIN` is set). It skips that
one test otherwise. Headless tests intentionally omit audio playback; the visual
capture uses the real renderer and imports/loads audio. Test persistence paths
are isolated under `.tools/test-state`; normal user scores are untouched.

Screenshots: [menu](screenshots/menu.png), [game](screenshots/game.png),
[game over](screenshots/gameover.png).

Before hardware acceptance, check laser visibility at all projected corners and
center, tune exposure/red thresholds, measure BLE-to-shot latency and FPS, and
verify boot-to-game after enabling Ubuntu automatic graphical login. Four-corner
calibration does not correct lens distortion. The camera currently timestamps
frame receipt, not hardware exposure. One gun/one laser is supported. No film
assets or music are included.

## Random encounter pacing — 2026-11-10

The updated gameplay passed **65 Godot checks** with zero failures. Coverage now
includes randomized starting waits, normal/long wait ranges on each difficulty,
long pauses remaining available late in a run, staggered bandit pairs in distinct
positions, capacity limits, post-kill delays applying to a pending partner, and
pending pairs freezing during pause and clearing when a new run starts.

```sh
.tools/godot --headless --path . \
  --log-file "$PWD/.tools/random-pacing-tests.log" --script tests/game_rules.gd
```

The **14 Python/mock integration tests also passed** in an isolated temporary
project copy. A running Godot game occupied UDP 4242, so the copy used three
unused loopback ports. Python HTTPServer's reverse-DNS metadata lookup also
stalled during local server startup; the temporary copy bypassed that lookup
without changing HTTP request handling. These two test accommodations were not
applied to the production camera bridge. The running game was left untouched.
Results are saved locally in `.tools/random-pacing-integration.log`.

Physical camera/BLE and Raspberry Pi performance remain unverified; this change
only adjusts Godot's encounter scheduling and its documentation/tests.

## Stages and procedural city — 2026-11-10

Stage progression and generated city blocks passed **98 Godot checks**: the
existing 65 gameplay checks plus 33 stage/generation checks. The generator was
exercised across 200 seeds for valid building bounds, unique/non-overlapping
target positions, reproducibility and variation. Stage checks cover all quotas
from 8 through 12, civilians not counting toward the quota, the last live bandit,
pending final pairs, state carried into the next block, and pause/timed-mode
behavior during the rightward scroll.

```sh
.tools/godot --headless --path . --script tests/game_rules.gd
.tools/godot --headless --path . --script tests/stages.gd
```

The **14 Python/mock integration tests passed** with the same isolated-port and
test-only HTTP metadata accommodations described above. The Godot camera test
now defeats the last bandit through OpenCV/UDP, enters a different generated
street, rejects a delayed shot from before arrival, and hits a target at its new
procedural position. Evidence is in `.tools/stage-integration.log`.

The generated streets and midpoint of the scrolling transition were rendered
with the actual OpenGL Compatibility renderer and visually inspected. See
[stage two](screenshots/stage-2.png), [stage three](screenshots/stage-3.png) and
[mid-scroll](screenshots/stage-scroll.png). Pixel scenery is generated once per
block; only the current and incoming blocks are held during a transition.

The new stage/renderer behavior has been checked on macOS ARM64. Raspberry Pi
performance and real projector/camera/BLE behavior remain unverified.

## Diverse bandit appearances — 2026-11-10

The first cosmetic iteration added persistent bandit appearances: six skin
tones, six hat/headband styles, four outfits, five face styles, and accessories.
Skin-tone variation was subsequently removed in the civilian update below.
A separate seeded cosmetic generator leaves the gameplay random sequence alone.
The original civilian design, target hitboxes, shooting deadlines and stage
rules are retained.

All **98 gameplay/stage checks passed** (65 gameplay, 33 stage/generation). A
12-character lineup and an in-game scene were rendered with the actual OpenGL
Compatibility renderer and visually reviewed for variety and civilian contrast.
See [the lineup](screenshots/bandit-lineup.png) and [gameplay](screenshots/game.png).
The visual capture is reproducible with `tests/capture.gd`; the gallery covers
every hat/outfit/face style. No new physical camera/BLE or Pi performance tests
were performed for this cosmetic change.

## Four civilian variants and one skin tone — 2026-11-10

All characters now share the original skin tone (`e0b780`). Bandit clothing,
hats, facial hair and accessories still vary. Civilians have exactly four
persistent designs: two men (rancher, merchant) and two women (bonnet/apron,
straw hat/braid). All remain unarmed, wear light blue/mint clothes, and retain
the SAFE label and original hitboxes. Cosmetic selection does not consume the
gameplay random sequence.

All **98 existing gameplay/stage checks passed**. The four-civilian gallery,
updated bandit lineup and gameplay scene were rendered with OpenGL Compatibility
and visually inspected. Preview: [civilian lineup](screenshots/civilian-lineup.png).
Reproduce the previews with `tests/capture.gd`.
