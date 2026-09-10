#!/usr/bin/env bash
# Export the browser build and serve it at http://localhost:8060
#
#   ./tools/serve_web.sh
#   then open http://localhost:8060/index.html?seed=20260910
#
# The web preset is built without threads, so no cross origin isolation
# headers are needed and a plain static server is enough.
set -eu
GODOT="${GODOT:-$HOME/godot/godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-8060}"
mkdir -p "$ROOT/build/web"
echo "exporting..."
"$GODOT" --headless --path "$ROOT" --export-release "Web" "$ROOT/build/web/index.html" >/dev/null
echo "serving $ROOT/build/web on http://localhost:$PORT/index.html"
echo "press ctrl-c to stop"
cd "$ROOT/build/web" && exec python3 -m http.server "$PORT"
