# Art spec — the first hour

For whoever is drawing. `target.png` in this folder is what we are aiming at;
everything below is that image written down as a list.

**Order matters.** It is sorted by how much screen time each thing gets, most
first. If only the top third ever gets drawn, the game still looks right.

## House rules

These apply to everything on the list.

| Rule | Why |
| --- | --- |
| **16x16 tile grid**, 640x360 viewport | Already built; everything is sized against it |
| **4 to 5 step colour ramp** per material | Flat fills are the single biggest reason the current build looks wrong |
| **Darker outline**, not black — a dark tint of the material | Pure black outlines read as cheap |
| **Light from the top left** | Consistent across every sprite and tile, or nothing sits together |
| No sprite is ever perfectly still | Even idle breathes |

Deliver as PNG with transparency, one file per sheet, frames laid left to right
in a single row. Put the file in `assets/art/` and add a line to `data/art.json`
and `CREDITS.md`. **No code changes are needed to swap a placeholder for real
art** — that is the whole point of the manifest.

---

## 1. The player

**20x40**, about two and a half tiles. The child from the top left of the
target: practical clothes, a pack, dark hair, nothing heroic.

| Animation | Frames | Notes |
| --- | --- | --- |
| idle | 4 | Breathing. Shoulders and the pack, not the whole body |
| run | 8 | The most-seen animation in the game. Worth the most effort |
| jump | 2 | Rising |
| fall | 2 | Arms up slightly |
| land | 3 | Squash, then recover. Sells weight |
| swing | 4 | Wind-up, strike, follow through. Must read at 3 frames of hit stop |
| dig | 4 | Shorter arc than the swing, aimed down |
| hurt | 2 | Recoil, white flash is done in code |
| ride | 4 | Sitting on the wolf, leaning with it |

Palette: warm skin, olive and brown clothes, leather pack. Nothing saturated —
the player should sit *inside* the golden light, not on top of it.

## 2. The wolf

The emotional core. Two sizes, because it grows.

- **Pup, 24x16.** Skinny, too-big ears, wary. Animations: idle 4, walk 6,
  sit 2, snap 3 (the reaction when you come too close), sleep 2, whine 2.
- **Grown, 40x28.** The wolf from the target's title art. Animations: idle 4,
  walk 6, run 8, bite 4, howl 3, sleep 2.

Grey through to near-white on the chest, amber eyes. The pup's palette is the
grown wolf's, one step lighter and softer.

## 3. Surface tiles

The ground the first twenty minutes happens on.

- **Grass-over-dirt terrain set**: full 47-piece blob, or 16-piece cardinal if
  that is too much. Corners and edges must actually join
- **2 to 3 variants** of each fill tile so the ground is not visibly stamped
- **Edge dressing**: grass tufts on top edges, roots hanging from overhangs
- Stone, sand, snow, wood as the same treatment

Surface palette from the target: warm gold, sap green, soft blue sky.

## 4. Parallax, surface

Four layers, 640x360 each, tiling horizontally:

1. Sky gradient with cloud band
2. Far mountains, hazed toward the sky colour
3. Mid hills with treeline
4. Near trees, darkest, moving fastest

Golden hour. The target's top-left panel is the reference.

## 5. UI

Dark navy panels, **thin warm beige borders**, exactly as the target's
inventory and bestiary panels.

- Panel frame, 9-slice
- Inventory slot, empty and selected
- Hearts: full, half, empty
- Coin icon
- Trust bar: frame and fill
- Buttons: normal, hover, pressed

Headings in a serif pixel font, body in a clean pixel font. Both must be
OFL-licensed and logged in `CREDITS.md`.

## 6. The glow frog

**12x10.** Sapo Luminoso. Translucent blue-green with a light inside it, so it
reads at a glance as a lamp that hops. Animations: idle 4 (with a blink), hop 4,
croak 3, glow pulse 4 (used when it is on your shoulder).

## 7. Cavern tiles and parallax

Cold blue rock, cyan crystal veins that catch the light. Four parallax layers:
far wall, mid pillars, near stalactites, a drifting fog sheet.

## 8. Abyss layer 1

Deep purple and magenta. Giant fungi that light their surroundings, which the
lighting system will treat as coloured light sources. Tiles, plus three or four
large mushroom props at 32x48 and up.

## 9. The Abyssling

The thing that killed the pup's mother, and the shape of the first boss. It
should be **wrong** rather than monstrous: too many joints, moves like it is
underwater, dark with a light inside.

- Small, 28x24: idle 4, stalk 6, lunge 4, hurt 2
- Boss, 96x80: idle 6, wind-up 4, slam 5, hide 4, hurt 2, die 8

## 10. Beiral

Buildings as structure stamps rather than sprites: an outfitter's workshop, a
kitchen with a chimney, a lookout post on the rim. Warm windows at night.

Three NPC sprites at 20x38, matching the player's build: **Bento** (broad,
grey, leather apron), **Lia** (apron, always carrying something), **Tomas**
(thin, young, a coat too big for him).

## 11. Everything else

The remaining seven creatures from the target's roster: rabbit, stone lizard,
night owl, rock turtle, abyss bat, crystal serpent, elder fungus. Same
treatment, roughly 16x16 to 40x28 depending on the animal. They can wait until
the first hour holds together.

---

## What exists now

Placeholders generated by `tools/gen_art.py`: flat fills, no ramps, no terrain
blending, player at 20x30. They are deliberately crude and **every one of them
is meant to be replaced**. Nothing in the code knows any of their filenames —
it all goes through `data/art.json`.
