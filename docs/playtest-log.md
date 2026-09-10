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


---

## Round 7 — 2026-09-10 — the browser number, and a lying harness

**Played.** The CI browser check, once it was fixed to actually reach the
world, and the scripted first run.

**The number that mattered.** The browser check reports a software rendered
frame rate, which says nothing about real hardware. But it also reports the
light pass, and that is CPU work in wasm rather than anything the GPU touches:

| Where | A whole light pass |
| --- | --- |
| Dev Mac, native | 4.5 ms |
| CI Linux, native | 8.6 ms |
| **Browser, wasm** | **26.5 ms** |

So the spike really would drop frames in a browser, on any hardware. That was
worth knowing before the next milestone stacks creatures on top of it.

**Changed.** The pass is now done in four steps across four frames: read and
sunlight, a round of sweeps, another round, then ambient and the image. A
check confirms the split lands on exactly the same light as doing it in one
go, because a faster light that is a different light is just a rendering bug.
Worst single step is 1.26 ms of a 4.44 ms pass, which is about 7 ms in wasm.

**Two false alarms, both mine.**

- The browser check reported the build had failed to boot. Its own screenshot
  showed the title screen rendered perfectly, waiting to be told to descend.
  The check had never pressed anything. Rather than fight a Godot canvas for
  keyboard focus, `--start` and `?start` now skip the title, which is useful
  on its own.
- The scripted run then reported that the player could not walk east at all,
  after previously crossing 24 tiles. Headless, the same code walked fine.
  **Godot releases every held input action when the window loses focus**, and a
  window launched from a shell often never has it, so `Input.action_press` did
  nothing and the test blamed the terrain. macOS throttling the unfocused
  window is also why a run that took 90 seconds started taking minutes.

  Input driven playtests now run headless, where they are fast and do not
  depend on which window is in front. Screenshots come from `postcards.tscn`,
  which teleports rather than walks and needs no input at all.

Both of those are checks lying about the game rather than the game being
wrong, which is the failure mode worth being slowest to believe.


---

## Round 8 — 2026-09-10 — the world is alive and dangerous

**Why this milestone happened at all.** Playing milestone 2 the verdict was that
it was far from Terraria. Two things came out of that: digging was wrong, and
the world was empty. Digging was fixed first (round 8a below). This is the
second half.

### 8a — digging

Digging was a cursor with five tiles of reach, which let you break blocks
across a room you could not touch. It is now aimed with the movement keys and
reaches exactly one tile: the block you face, or the one under your feet or
over your head. Breaking a block gives you the material, which floats off the
tile and lands in a tally on the right, so mining visibly pays instead of just
leaving a hole.

A check confirms nothing further than one tile can be aimed at, whatever
combination of keys is held.

### 8b — the day, and what comes out in it

**Played.** `day_night.tscn`, one world stepped through dawn, noon, dusk and
midnight, and the headless night checks.

**Worked.**

- The sky reads as a time of day: warm at dawn and dusk, blue at noon, nearly
  black at midnight, with the clock on screen in warm or cold ink to match.
- **Night is dark because the sun stops giving light**, not because something is
  drawn over the screen. That one decision is what makes a torch matter after
  dusk and a lit room read as safe, and it fell out of the lighting built in
  milestone 2 rather than needing anything new.
- Wildlife by day, hostiles by night, and morning clears them off the surface.
- A swing kills a crawler in two hits, aimed with the same keys as digging,
  because two aiming schemes in one game is how controls stop being learnable.

**Wrong, and fixed.**

- The nearest creature readout said `@CharacterBody2D@15`. Godot renames an
  instanced scene the moment two of them collide, so the overlay now names
  things by their group rather than their node name.
- The first day and night shots showed an empty world. Spawning happens off
  screen on purpose, and the script did not wait for anything to walk in. The
  rule was right and the screenshot was lying.
- Sampling "dawn" at 0.26 gave full daylight, because sunrise finishes *before*
  dawn. Twilight is 0.20 to 0.25, not 0.25 to 0.30.

**A harness trap worth writing down.** macOS throttles a windowed run that is
not in front. A twenty second screenshot script took several minutes behind
another window and looked exactly like a hang. Anything windowed now calls
`DisplayServer.window_move_to_foreground()` and runs with `--always-on-top`.
That is the second time the harness has lied about the game rather than the
other way round.

### 8c — the screenshot that found two bugs

The last shot of round 8 was meant to be a picture of a crawler arriving. It
came back showing the player dead, with the words **"You fell too deep."**

Two things wrong in one frame.

- **The death message was a lie.** That text is from the placeholder, when
  falling down a shaft was the only way to die. Being killed by something and
  being told you fell is worse than saying nothing.
- **Dying threw the world away.** `R` reloaded the scene, which built a brand
  new world from a fresh seed. Everything dug was gone. In a game about digging
  that is not a death penalty, it is losing the save.

Death now puts you back where you started, in the same world, with your health
and everything you dug. Checks cover all of it: same seed, same hole, back at
the spawn column, message cleared.

Neither of these would have shown up in a headless check, because both were
about what the player is told and what the player keeps. It took a picture of a
corpse to notice.

**Still not right.**

- Dawn and dusk look identical. Sunrise should be cooler than sunset.
- Hostiles are one crawler with a new flag. Milestone 4 gives them species,
  habits and hours.
- Death costs nothing yet. Terraria drops some of your coins; there is nothing
  here to drop until milestone 4 gives you things to carry.
- Standing still through a night takes five hearts to zero. Whether that is
  tense or unfair is a judgement for whoever plays a night properly, with the
  walls and workbench that milestone 4 will provide.
