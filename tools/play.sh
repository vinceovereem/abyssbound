#!/usr/bin/env bash
# Run the game.
#
#   ./tools/play.sh                      a new world every time
#   ./tools/play.sh --seed=20260910      the world the screenshots were taken in
#   ./tools/play.sh --seed=7 --spawn-x=1000   drop in at the mouth of the Abyss
#
# The seed is printed at startup, so a world worth keeping can be got back.
set -eu
GODOT="${GODOT:-$HOME/godot/godot}"
if [ ! -x "$GODOT" ]; then
  echo "Godot not found at $GODOT"
  echo "Set GODOT=/path/to/godot, or install Godot 4.6 from godotengine.org/download"
  exit 1
fi
exec "$GODOT" --path "$(cd "$(dirname "$0")/.." && pwd)" -- "$@"
