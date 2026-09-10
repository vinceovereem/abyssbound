# Working on Abyssbound

Two people and an AI assistant work in this repo. These rules exist so the three of you do not overwrite each other.

## Setup

1. Install [Godot 4.6](https://godotengine.org/download), standard build
2. Install Python 3 and Pillow if you want to regenerate art: `pip install pillow`
3. Clone the repo, open `project.godot` in Godot

## Branches

Never commit to `main`. Branch, push, open a pull request. CI has to be green before it merges.

Branch names: `feat/wall-jump`, `fix/crawler-falls-through-floor`, `art/crystal-sprite`.

## Who owns what

This matters more than it sounds. Godot scene files are text, but two people editing the same `.tscn` still produces a merge conflict that is painful to resolve by hand.

- **Design and art** owns `assets/`, `levels/`, and the visual properties inside scenes
- **Code** owns `scripts/`, `tests/`, `tools/`, and the node structure inside scenes

If you need to change a scene someone else is working on, say so first. It is faster than fixing the conflict.

## Before you push

```
godot --headless --path . res://tests/smoke_test.tscn
```

If it fails, fix it. If your change makes an old check wrong, change the check and say why in the commit message.

## Adding a zone

1. Add a function to `tools/gen_levels.py` and run it, or hand-write a text map in `levels/`
2. Copy `scenes/levels/zone_caverns.tscn` to a new file and point `map_file` at your map
3. Point the previous zone's `next_zone` at your new scene
4. Add the scene path to `ZONES` in `tests/smoke_test.gd`

The generator refuses to write a map with a pit wider than a jump or a platform out of reach. If it complains, the level really is broken.

## Adding a creature

1. Draw it in `tools/gen_art.py` and run the script
2. Copy `scenes/actors/crawler.tscn`, point it at your sprite region
3. Write the script in `scripts/`. Put it in the right group: `enemy`, `critter` or `pickup`
4. Give it a symbol in the legend at the top of `scripts/level.gd` and a case in `_place`

## Commit messages

One line, present tense, says what changed:

```
add wall jump to the player controller
fix crawler turning early on one-way platforms
regenerate crystal sprite with brighter core
```

## Working with Claude

Read `CLAUDE.md`. It carries the context an AI needs so you do not have to explain the project every time.
