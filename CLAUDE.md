# Abyssbound: context for AI assistants

Read this before changing anything.

## Where the project is going

`docs/design.md` is the spec: Aerenfall, a Terraria-shaped sandbox RPG built on
a procedural tile world, where creatures are the core mechanic and the Abyss is
the long goal. `docs/plan.md` is the build order, milestones 2 to 7, with the
files each one is expected to touch.

Read both before starting work on a milestone. What follows below describes the
placeholder as it stands today, which the pivot keeps most of: the player
controller, the crawler, the critter trust hook, the HUD, the title screen, CI
and the art generator all survive. Zone loading is the part being replaced.

## What this is

A 2D side-view sandbox RPG in Godot 4.6, GDScript, GL Compatibility renderer. Target is PC first, mobile possibly later. The world is procedural, made of 16x16 tiles, and every tile can be dug. See `docs/design.md`.

The three hand-made zones it started as are archived in `levels/legacy/` and still load, but they are not the game any more. `scenes/world.tscn` is.

Two people work on it. One handles code and tooling. One handles design and art. Neither wants to debug a merge conflict in a scene file.

## Rules

**Godot 4.6 only.** Do not use Godot 3 syntax. `CharacterBody2D` not `KinematicBody2D`. `@export` not `export var`. `TileMapLayer` not `TileMap`. Signals connect with `signal_name.connect(callable)`.

**Never hand-edit `.tscn` node structure unless you have to.** It works, but it is easy to produce a file Godot silently drops nodes from. If you do edit one, run the smoke test afterwards. It catches missing nodes.

**Art is generated, not drawn.** Everything in `assets/` comes out of `tools/`: sprites and tiles from `gen_art.py`, the tile set resource from `gen_tileset.py`, level maps from `gen_levels.py`. Change the ASCII grid or the tile data and re-run. Do not write PNG bytes directly and do not commit an asset the generator did not produce.

`tools/verify_generated.py` is what CI runs, and it compares **pixels, not file bytes**. Pillow versions encode the same image differently, so a byte comparison fails on any machine whose Pillow differs from the one that committed the art while telling you nothing about whether the art is right.

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
- **The macOS export needs ETC2 ASTC turned on.** `rendering/textures/vram_compression/import_etc2_astc=true` in `project.godot` is not optional decoration: Godot refuses to export a universal or arm64 macOS build without it, and the export fails with a configuration error rather than a warning. Nothing here actually uses VRAM compression, every texture imports lossless, so the flag costs nothing. Do not "tidy it away".
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

## The world

`scenes/world.tscn` is a bare node with `scripts/world.gd` on it. Everything
else is built in code, because hand-editing a `.tscn` node structure is how
nodes get silently dropped.

| Piece | What it does |
| --- | --- |
| `scripts/world/world_gen.gd` | Seed to tiles. Biomes, caves, ore, trees, the shaft |
| `scripts/world/chunk.gd` | 32x32 tiles as four byte arrays |
| `scripts/world/chunk_store.gd` | Generates on demand, keeps everything, applies saved edits |
| `scripts/world/chunk_renderer.gd` | Streams a window of chunks into shared TileMapLayers |
| `scripts/world/lighting.gd` | Light over a window around the player, drawn as a darkness texture |
| `scripts/world/mining.gd` | Dig and place, reach, break time, support rules |
| `scripts/world/world_save.gd` | Seed plus changed tiles |
| `scripts/world/sky.gd` | Depth driven backdrop |
| `scripts/world/boot_config.gd` | Seed and spawn from the command line or the URL |

**A chunk must stay a pure function of the seed and its own coordinates.** Not
of what was generated before it. Cross-chunk features like trees recompute what
the neighbouring columns hold rather than writing into each other. There is a
check for this and it exists because the alternative is a world that quietly
stops being reproducible, which breaks saves and every seeded test.

**Tile id doubles as the column in the tile sheet.** Ids 0 to 5 are the
archived zones and are frozen: renumbering them silently repaints
`levels/legacy/`. Append, never reorder.

## Things that will bite you in the world code

- **A GDScript parse error hangs a headless run, it does not fail it.** The
  scene loads with no script, `_ready` never runs, and the process sits there
  looking like a slow test. Run `./tools/lint.sh` before running anything.
  CI runs it too, and the jobs carry timeouts.
- **`--check-only --script` reports `Game` and `Ui` as missing.** Autoloads do
  not exist in script mode. `tools/lint.sh` filters exactly those two.
- **New global classes need a project scan.** After adding a `class_name`, run
  `godot --headless --path . --import` or the next script that refers to it
  fails with "Nonexistent function 'new' in base 'GDScript'".
- **`Sky` and `_set` are taken.** `Sky` is a built-in Godot resource and `_set`
  is an `Object` virtual. Both shadow silently and fail confusingly.
- **Type inference stops at an untyped node.** `world` is a plain `Node2D`, so
  anything read off it needs an explicit type: `var t: Vector2i = world.player_tile()`.
- **Godot drops every held input when the window loses focus.** A windowed
  playtest driven with `Input.action_press` therefore does nothing at all if
  the window never got focus, and reports the ground as impassable rather than
  reporting that it never pressed anything. macOS also throttles unfocused
  windows, so the same run takes minutes. Run input-driven playtests
  **headless** and use `postcards.tscn`, which teleports instead of walking,
  for pictures.
- **Lighting is the performance budget.** A pass went 30 ms -> 4.5 ms and every
  step of that is load bearing. Reading tiles a chunk-run at a time instead of
  through `get_fg` per tile; per tile id lookup tables instead of a method call
  in the inner loop; `while` loops in the sweeps because `for x in range(...)`
  stored in a variable allocates an Array per row per sweep; and `set_data`
  instead of `set_pixel`. CI's runner is about twice as slow as a dev Mac, so
  treat 8 ms local as the real ceiling.

## Physics layers

| Bit | Value | Used by |
| --- | --- | --- |
| 1 | 1 | World geometry |
| 2 | 2 | Player |
| 3 | 4 | Enemies and critters |
| 4 | 8 | Pickups, hazards, the descent |

Player is layer 2 mask 1. Anything that needs to detect the player masks 2.

## Deployment

`.github/workflows/ci.yml` runs the smoke test, exports four platforms, then deploys the web build to Vercel with the Vercel CLI. `vercel.json` sets the wasm content type and cache headers, and CI copies it into `build/web` before deploying.

The deploy needs `VERCEL_TOKEN`, `VERCEL_ORG_ID` and `VERCEL_PROJECT_ID` as repository secrets. If they are missing the step prints an explanation and exits 0 rather than failing, so a fork or a new clone still gets green CI.

Do not add a Vercel build command that installs Godot. The export templates are over a gigabyte and would be downloaded on every deploy. The build happens in Actions, where it is cached, and Vercel only serves the finished files.

Pushing a `v*` tag publishes the Windows `.exe` and the macOS `.zip` as a GitHub
Release. That is the only build a playtester can download without a GitHub
account, because Actions artifacts expire and sit behind a login. The desktop
builds are unsigned, so both operating systems warn on first launch and the
release notes tell people how to get past it. Do not tell anyone to
double-click the Mac app the first time: unnotarised apps give a dead-end
dialog, and only right-click then Open offers the button that lets it through.

## What is deliberately missing

No sound, no menus beyond the title, no real art, no inventory, no creatures,
no clock. Those are milestones 3 to 7 in `docs/plan.md`, not oversights.

Flowing water is not built. The ocean is static water placed by the generator.
The simulation belongs with the oxygen kit in milestone 5.

Tiles do not corner-blend. Exposed tiles get a lit top lip, which buys most of
the look for a fraction of the work; a full terrain set is still owed.
