#!/bin/bash
# Give a character a cloned (English) voice in Pet Agents.   Usage: tools/voice/install_voice.sh naruto
#
# Installs the cloning engine once (F5-TTS on Apple's MLX: ~0.4 GB engine + ~1.3 GB model, about 2 GB in all), builds the
# character's reference audio from their English clips in Sounds/, and pre-renders their fixed lines.
# Everything goes to ~/Library/Application Support/PetAgents/voice; delete that folder to remove it.
set -euo pipefail
CHAR="${1:-naruto}"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
ROOT="$HOME/Library/Application Support/PetAgents/voice"
mkdir -p "$ROOT/voices/$CHAR" "$ROOT/cache/$CHAR"

command -v uv >/dev/null || { echo "This needs uv: curl -LsSf https://astral.sh/uv/install.sh | sh" >&2; exit 1; }
if [ ! -x "$ROOT/venv/bin/python" ]; then
  echo "Installing the voice-cloning engine (F5-TTS for Apple Silicon)..."
  uv venv -q -p 3.12 "$ROOT/venv"
  VIRTUAL_ENV="$ROOT/venv" uv pip install -q f5-tts-mlx
fi
cp "$HERE/voices.json" "$HERE/voice_server.py" "$ROOT/"

echo "Building ${CHAR}'s reference audio..."
CLIPS=$(python3 -c "import json,sys; print('\n'.join(json.load(open(sys.argv[1]))[sys.argv[2]]['reference']['clips']))" "$HERE/voices.json" "$CHAR")
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
i=0
while read -r clip; do
  [ -f "$REPO/Sounds/$clip" ] || { echo "Missing Sounds/$clip: run python3 tools/sounds/fetch_sounds.py first" >&2; exit 1; }
  afconvert -f WAVE -d LEI16@24000 -c 1 "$REPO/Sounds/$clip" "$TMP/$i.wav"; i=$((i+1))
done <<< "$CLIPS"
"$ROOT/venv/bin/python" - "$TMP" "$ROOT/voices/$CHAR/ref.wav" <<'PY'
import glob, sys, numpy as np, soundfile as sf
parts = []
for f in sorted(glob.glob(sys.argv[1] + "/*.wav")):
    a, sr = sf.read(f)
    parts += [a, np.zeros(int(sr * 0.3))]
sf.write(sys.argv[2], np.concatenate(parts[:-1]), 24000)
print(f"reference: {sum(len(p) for p in parts[:-1]) / 24000:.1f} s")
PY

echo "Rendering ${CHAR}'s lines (the first run downloads the F5-TTS model, ~1.3 GB)..."
"$ROOT/venv/bin/python" "$ROOT/voice_server.py" --root "$ROOT" --voices "$ROOT/voices.json" --prerender "$CHAR"
echo "Done: ${CHAR} now speaks in Pet Agents (Home → Settings → Character voices)."
