"""Download the sound clips listed in Sounds/sounds.json into Sounds/.

The clips are user uploads on myinstants.com and the audio belongs to its owners, so they are
not committed to the repo; run this once to get them locally:  python3 tools/sounds/fetch_sounds.py"""

import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOUNDS = ROOT / "Sounds"
spec = json.loads((SOUNDS / "sounds.json").read_text())
ok = fail = 0
for name in spec["files"]:
    dest = SOUNDS / name
    if dest.exists() and dest.stat().st_size > 1000:
        ok += 1
        continue
    # myinstants blocks Python's default user agent, so use curl.
    r = subprocess.run(["curl", "-sfL", "-A", "Mozilla/5.0", "--max-time", "60", "-o", str(dest), spec["base_url"] + name])
    if r.returncode == 0 and dest.exists() and dest.stat().st_size > 1000:
        ok += 1
    else:
        fail += 1
        dest.unlink(missing_ok=True)
        print("failed:", name)
print(f"{ok} clips ready, {fail} failed, in {SOUNDS}")
