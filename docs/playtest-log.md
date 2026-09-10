# Playtest log

One entry per round of the build loop. What was played, what the screenshots
showed, what was wrong, what changed. Findings that became bugs get a headless
check so they cannot come back quietly.

Screenshots are written to `user://postcards/` and `user://playtest/` by the
scripts in `tests/playtest/`. On macOS that is
`~/Library/Application Support/Godot/app_userdata/Abyssbound/`.

---

## Round 1 — 2026-09-10 — does the world look like a world?

**Played.** `postcards.tscn`, a survey that spawns at nine places across the
map and screenshots each: both oceans, plains, forest, desert, the mouth of the
Abyss, the mountains, and three depths underground.

**Worked.** Biomes read as distinct at a glance. Trees, ore and the layer
boundaries all showed up where the generator said they would. The surface
blends across biome boundaries with no cliff. 2 ms to generate a chunk.

**Wrong.**

- **No sky at all.** 45% of the plains screenshot was the near black clear
  colour. Every surface shot read as a cave. This was the single biggest
  readability problem and nothing else could be judged until it was fixed.
- **The ocean was invisible.** Water was rendering, but so dark it looked like
  night sky. The pixel histogram gave it away: the water tile is noisy, so no
  single colour dominated and it was easy to miss that it was there at all.
- **Ore everywhere.** About 11% of underground tiles were copper or iron, which
  reads as confetti and makes finding a vein worthless.
- **Walls too dark to see.** Cave interiors were black rather than showing the
  rock behind them.

**Changed.** Added a depth-driven sky gradient. Brightened water and cut its
per pixel alpha noise. Raised the ore thresholds until ore was roughly 3% of
stone. Lifted the wall tiles and their modulate.

---

## Round 2 — 2026-09-10 — the mouth of the Abyss

**Played.** Re-shot the survey, this time centred on the shaft and on the
waterline rather than near them, because round 1 managed to miss both.

**Worked.** The waterline is now obvious: a hard boundary between light sky and
darker water. Ore density looks like something worth finding.

**Wrong.**

- **The Abyss mouth read as a cliff over open sky.** The shaft had deliberately
  been left with no wall behind it, on the theory that a chasm should read as
  open. With a bright daylight backdrop that meant the sky showed straight
  through the hole, so the biggest landmark in the world looked like the edge
  of the map.

**Changed.** The shaft keeps its rock wall below the first few tiles under the
surface. Its darkness is the lighting's job, not the absence of a wall.
Check added: *the shaft has rock behind it, not sky*.

---

## Round 3 — 2026-09-10 — lighting

**Played.** Survey again, plus a shot that hollows out a room underground and
puts a single torch in it.

**Worked.** The torch room is the best thing in the build: a lit pocket with a
soft falloff into black. Drawing light at one texel per tile and scaling it up
with linear filtering is what buys the smooth gradient for free. The Abyss
mouth now reads as a chasm, daylight fading down it.

**Wrong.**

- **A first pass cost 30 ms.** Nearly two frames at 60 fps.
- **Underground was pure black.** With no torch the screen showed nothing at
  all, which reads as a broken renderer rather than as darkness.

**Changed.** Read every tile once into flat arrays instead of asking the chunk
store on each of eight sweeps, and wrote the image buffer directly instead of
calling `set_pixel` per texel: 30 ms became 8 ms. Added an ambient floor so
light never reaches zero. Checks added for sunlight, falloff, the ambient
floor, torch range and the pass staying inside a frame.

---

## Round 4 — 2026-09-10 — actually playing it

**Played.** `first_run.tscn`. Spawn, walk east toward the Abyss, hold the
button to dig, place a torch, save, reload. Driven through the real input
actions and the real mining code.

**Wrong, and this round is why the loop exists.** Three of these were invisible
to the generation checks, which all passed the whole time.

- **The player walked 0 tiles east.** The spawn was next to a tree, and tree
  trunks were solid, so the tree was a wall. A forest was a fence.
- **Then it needed 6 jumps to cross 10 tiles.** Natural ground is single tile
  steps almost everywhere and the controller stopped dead at every one of them.
  Walking anywhere was work.
- **The torch would not place.** Placement fired only on the one frame the
  button went down, which is easy to miss and, for a player, means building a
  wall is a clicking exercise.

**Changed.**

- Tree trunks became their own tile: same look as wood, walk straight through,
  the way they behave in the game this borrows from. Wood the building block
  stays solid.
- The player steps up a single tile ledge without jumping. It is an exported
  value on the player scene, so it is tuned in the inspector like every other
  feel value, and setting it to 0 restores the old behaviour. After this,
  walking east crossed **24 tiles with 0 jumps**, up from 10 tiles with 6.
- Holding the place button lays a run of tiles on a short interval.

Checks added: trunks are walkable, a forest is walkable, a one tile step needs
no jump, and stepping up lands the player on top of the step.

**Still not right.**

- **Light spikes to 13 to 18 ms while moving.** The average over the run was
  121 fps native, but a recompute lands on one frame and blows the budget. It
  is a stutter, not a slowdown.
- **No browser measurement.** Everything above is native macOS. See the caveat
  in the milestone summary.

---

## Round 5 — 2026-09-10 — verdict

**Played.** Full survey and the scripted first run, after all of the above.

**Result.** 63 world checks, 39 original checks, 15 scripted play checks, all
passing. No console errors. 121 fps average native.

**Judged.**

- *Bugs.* None outstanding that were found.
- *Feel.* Digging is responsive and the target highlight makes the break time
  legible. Walking is much better with step up. Jumping is unchanged and still
  good.
- *Readability.* Surface, underground and Abyss are clearly different places.
  A player with no torch can still make out the shape of a cave.
- *Fun.* There is a visible hole in the ground 60 tiles from spawn that gets
  darker as it goes down. That is a reason to keep going.

Stopping the loop here. The remaining known problem is the light spike, which
is recorded above and carried into the next milestone rather than hidden.


---

## Round 6 — 2026-09-10 — the light spike, on someone else's hardware

**Played.** Nothing new. CI ran the same checks on a Linux runner and failed
one: *a light pass fits in a frame budget*, at **18.8 ms**. The same pass
measures 8.5 ms on the dev Mac.

This is the most useful failure of the milestone. The budget check was written
expecting to catch a regression later; instead it caught the known spike the
moment it ran on ordinary hardware, and put a number on the thing the milestone
summary could otherwise only hedge about.

**Changed.** Not the threshold. Three more passes over the hot path:

- Tiles are read a chunk-run at a time. A row crosses a chunk boundary only
  every 32 tiles, so the chunk is found once per run and its byte array is read
  directly, instead of `ChunkStore.get_fg` doing a bounds check and a
  dictionary lookup 8000 times a pass.
- Per tile id lookup tables for solid, falloff and emission, so the inner loop
  is array indexing with no method calls.
- The sweeps became `while` loops. `for x in range(a, b, step)` with the range
  held in a variable allocates an Array per row per sweep, which was 576
  throwaway arrays every recompute.

**Result.** 8.5 ms to **4.55 ms** on the dev Mac, and 30 ms to 4.55 ms across
the milestone as a whole. On CI's runner, which measured about twice as slow,
that should land near 10 ms and inside a frame.

**Still open.** A browser is still unmeasured, and it is the number that
actually matters for the stated target. If it turns out to be short there, the
next move is to split a pass across two frames rather than to make the light
worse.
