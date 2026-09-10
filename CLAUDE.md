# Abyssbound: context for AI assistants

Read this before changing anything.

## What this is

A 2D pixel-art platformer in Godot 4.6, GDScript, GL Compatibility renderer. Target is PC first, mobile possibly later. The current state is a working placeholder: real systems, stand-in art and levels.

Two people work on it. One handles code and tooling. One handles design and art. Neither wants to debug a merge conflict in a scene file.

## Rules

**Godot 4.6 only.** Do not use Godot 3 syntax. `CharacterBody2D` not `KinematicBody2D`. `@export` not `export var`. `TileMapLayer` not `TileMap`. Signals connect with `signal_name.connect(callable)`.

**Never hand-edit `.tscn` node structure unless you have to.** It works, but it is easy to produce a file Godot silently drops nodes from. If you do edit one, run the smoke test afterwards. It catches missing nodes.

**Art is generated, not drawn.** Everything in `assets/` comes out of `tools/gen_art.py`. If you want a different sprite, change the ASCII grid in that script and re-run it. Do not write PNG bytes directly and do not commit an asset the generator did not produce, because CI checks that `assets/` matches the generator output.

**Levels are text.** Everything in `levels/` comes out of `tools/gen_levels.py` and is also editable by hand. Same CI check applies. The legend lives in the header of each map file and in `scripts/level.gd`.

**Tune in the inspector, not the code.** Player feel values are `@export` variables on `scenes/actors/player.tscn`. If someone asks to make the jump higher, change the scene, not the default in the script.

**Every change runs the smoke test.**

```
godot --headless --path . res://tests/smoke_test.tscn
```

Exit code 0 or the change is not done.

## Things that have already bitten us

- **Non-resource files are not exported.** `.txt` level maps only reach the packed build because `include_filter` in `export_presets.cfg` lists them. The game worked in the editor and failed in the browser. If you add a data file in a new format, add it to every preset's `include_filter`.
- **Level geometry has to respect the jump.** The jump clears about 59 px, roughly 3.7 tiles, and reaches about 70 px horizontally. `tools/gen_levels.py` enforces a maximum pit of 3 tiles and a maximum climb of 3 tiles. If you change `jump_velocity` or `gravity` on the player, update the constants and the comment in that script.
- **Autoloads are not available in `--script` mode.** The smoke test is a scene, not a script, for that reason. Keep it that way.
- **Pits are open shafts on purpose.** An earlier version had floors at the bottom of pits and the player could not jump out. Falling costs a heart and respawns you. Do not put a floor in a shaft.

## Layout

| Path | What it holds |
| --- | --- |
| `scripts/game.gd` | Autoload `Game`. Health, crystals, current zone, scene changes |
| `scripts/hud.gd` | Autoload `Ui`. HUD, zone title, messages, fade |
| `scripts/player.gd` | Player controller. All feel values are exports |
| `scripts/level.gd` | Reads a text map and builds the zone from it |
| `scripts/crawler.gd` | Enemy. Patrols, hurts on contact, dies when stomped |
| `scripts/critter.gd` | Tameable. Hold interact to build trust, then it follows |
| `tests/smoke_test.gd` | 39 checks. Zones, physics, pickups, combat, zone links |

## Physics layers

| Bit | Value | Used by |
| --- | --- | --- |
| 1 | 1 | World geometry |
| 2 | 2 | Player |
| 3 | 4 | Enemies and critters |
| 4 | 8 | Pickups, hazards, the descent |

Player is layer 2 mask 1. Anything that needs to detect the player masks 2.

## What is deliberately missing

No sound, no save system, no menus beyond the title, no real art. Those are the next jobs, not oversights.
