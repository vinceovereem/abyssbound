#!/usr/bin/env bash
# Parse-check every GDScript file.
#
# Why this exists: a script that fails to parse does not fail the game, it
# hangs it. The scene loads with no script attached, _ready never runs, and a
# headless run sits there forever looking exactly like a slow test. That cost
# an afternoon once. Catch it in a second instead.
#
# CLAUDE.md notes that autoloads do not exist in --script mode, so every
# reference to one reports as missing here and none of them are real failures.
# The names are read out of project.godot rather than hardcoded, so adding an
# autoload does not silently start breaking the lint.
set -u
GODOT="${GODOT:-$HOME/godot/godot}"
AUTOLOADS=$(sed -n '/^\[autoload\]/,/^\[/p' project.godot \
  | grep -E "^[A-Za-z_][A-Za-z0-9_]*=" | cut -d= -f1)
IGNORE="Failed to compile depended scripts"
for name in $AUTOLOADS; do
  IGNORE="$IGNORE|Identifier not found: $name"
done
fail=0
while IFS= read -r f; do
  out=$("$GODOT" --headless --path . --check-only --script "$f" 2>&1)
  real=$(echo "$out" | grep -E "Parse Error|Compile Error" | grep -Ev "$IGNORE")
  if [ -n "$real" ]; then
    echo "FAIL $f"
    echo "$real" | sed "s|^|    |"
    fail=1
  fi
done < <(find scripts tests tools -name "*.gd" | sort)
[ "$fail" -eq 0 ] && echo "all GDScript parses"
exit $fail
