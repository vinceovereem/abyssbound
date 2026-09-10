#!/usr/bin/env bash
# Parse-check every GDScript file.
#
# Why this exists: a script that fails to parse does not fail the game, it
# hangs it. The scene loads with no script attached, _ready never runs, and a
# headless run sits there forever looking exactly like a slow test. That cost
# an afternoon once. Catch it in a second instead.
#
# CLAUDE.md notes that autoloads do not exist in --script mode, so references
# to Game and Ui report as missing here and are not real failures.
set -u
GODOT="${GODOT:-$HOME/godot/godot}"
fail=0
while IFS= read -r f; do
  out=$("$GODOT" --headless --path . --check-only --script "$f" 2>&1)
  real=$(echo "$out" \
    | grep -E "Parse Error|Compile Error" \
    | grep -v "Identifier not found: Game" \
    | grep -v "Identifier not found: Ui" \
    | grep -v "Failed to compile depended scripts")
  if [ -n "$real" ]; then
    echo "FAIL $f"
    echo "$real" | sed "s|^|    |"
    fail=1
  fi
done < <(find scripts tests tools -name "*.gd" | sort)
[ "$fail" -eq 0 ] && echo "all GDScript parses"
exit $fail
