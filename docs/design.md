# Aerenfall: the design

This is the spec for what BocciaBound is becoming. `ARCHITECTURE.md` describes
how the placeholder is built today. This file describes where it is going and
why. When the two disagree, this one is the intention and that one is the
current fact.

## The pitch

A 2D side-view survival sandbox. A world of 16x16 tiles you can dig through,
build in, and fall a very long way down. You start with nothing, you craft your
way up, and the creatures you befriend are what let you go further.

Four games are in the blood of it, and it is worth being precise about what we
take from each, because taking the wrong thing is how a game ends up as a
worse copy of something else:

| From | What we take | What we do not take |
| --- | --- | --- |
| Terraria | Tile world, digging, building, biomes, crafting stations, underground light, town NPCs | Its content, its names, its bosses, its progression curve |
| 2D Mario | The feel. Coyote time, jump buffering, variable jump height, stomping | Levels, lives, a linear world |
| Pokemon | Creatures with distinct habits, and a power per species | Capture. There is no ball. No gyms, no badges, no league |
| Minecraft | Start with nothing, gather, craft, and the gear is the gate | Cubes, a 3D world, the crafting grid |

No asset, name, character or exact mechanic gets copied. The style, not the
content.

## The turns this took

### Third turn: both

The chasm is back, and the caves stay. Taking it out was right about the
symptom and wrong about the cause: the problem was never that a chasm existed,
it was that it was the **only** interesting place to go. Now that the caves
stand on their own, the two work on each other. Cave systems open onto the
chasm wall at every depth, so the Abyss is a hub the underground leads to
rather than a corridor you are funnelled down, and the rim is somewhere to
stand and look.

Beiral sits on that rim. The Rise climbs out of it. The story needs a hole in
the world, and now there is one worth having.

### Second turn: caves, not a chasm (superseded above)

The Abyss was a single vast shaft near the middle of the map. Playing it, the
problem was obvious: one column of a two thousand tile world was the only
interesting place to go, and everywhere else was rock you tunnelled through
because there was nothing else to do with it. That is Minecraft's underground,
not Terraria's.

So the chasm is gone. The underground is now caves: winding tunnels near the
surface opening into chambers deeper down, all connected, with chests and life
crystals waiting in them. **You find things by exploring rather than by
grinding blocks**, which is the actual difference between the two games.

The name stays. "The Abyss" now means the deep caves rather than one hole.

### First turn: survival, not RPG

The first version of this document called Aerenfall a sandbox RPG and put
creature bonding at the centre, with combat as one option among several. Play
testing said otherwise: it read as a tech demo, not a game.

**The spine is now Terraria's.** Survive, dig, craft better gear, fight what
comes for you at night, and eventually take on something big. Bosses are part
of the game. The order of work changed to match: a world that is alive and
dangerous comes before inventory and crafting, and survival pressure comes
after both.

What Aerenfall keeps that Terraria does not have is depth on top of that spine,
not a replacement for it: creatures with real habits you can learn and bond
with, and a deep underground worth exploring. Those stay. They stop being the
first thing the player meets.

The class system and skill trees are the least Terraria-shaped thing in here.
They move to last, and may not survive contact with the rest.

## The philosophy

Four rules. Every design argument gets settled against these, so they are
written first and everything else is downstream.

**The world is the protagonist.** The player is a person living in Aerenfall,
not its chosen one. There is no prophecy and no main quest. The world does not
pause, wait, or scale itself to the player. Creatures hunt at the hour they
hunt whether or not anyone is watching.

**You unlock possibilities, not areas.** There are no level gates and no locked
doors that want a key. You can walk to the ocean on day one. You will drown,
because you have no oxygen and nothing to swim with. Nothing stopped you. You
simply were not yet the kind of person who could do it. You come back when you
are.

This is the difference between "you are not allowed" and "you are not able",
and it is the single most important feel in the game. Every barrier must read
as a fact about the world, never as a rule about the player.

**Creatures are the core mechanic.** They are not loot and not a collection.
They live somewhere, they eat something, they keep hours. You learn a creature
by watching it, and the reward for patience is information. Trust is built over
in-game days, and it can be lost.

**Down is where the game is.** A chasm *and* caves: a connected underground you
explore, and one enormous hole through the middle of it that the caves open
onto at every depth. The rock changes
with depth, what lives there changes with depth, and what you find there is
worth the walk. The long-term goal is not a place at the bottom, it is being
the kind of person who can survive further down.

## The pivot

Today the repo holds a placeholder vertical slice: three hand-made zones loaded
from text maps, a player controller, one enemy, one tameable critter, pickups,
a title screen, a HUD and 39 headless checks. It works. Most of it survives.

### Kept as is

The player controller, the crawler, the critter trust hook, the HUD, the title
screen, CI, the headless test runner and the art generator. The controller in
particular is not up for renegotiation: the Mario-feel requirement is already
met by `scripts/player.gd`, and the values live in the inspector on
`scenes/actors/player.tscn` exactly as `CLAUDE.md` requires.

### Replaced

Zone loading. `scripts/level.gd` builds a whole level from one text file at
`_ready()` and never changes it again. A streaming, diggable, 2000x800 world
cannot work that way. World generation replaces it.

### Kept, but repurposed

The text map format. It does not survive as "a level", it survives as **a
stamp**: a hand-authored structure the generator places into the world. Nests,
ruins, huts, village buildings, a shrine in a deep cave. This keeps the rule that
matters from `ARCHITECTURE.md` alive, which is that hand-authored content is
readable in a diff and editable in any text editor, while the bulk of the world
comes from a seed.

### Moved, not deleted

`levels/surface.txt`, `levels/caverns.txt` and `levels/abyss.txt` move to
`levels/legacy/`. The three zone scenes that load them stay working. They stop
being the game — the title screen will boot into the generated world instead —
but they remain a fixture the existing checks run against, which is how the 39
checks stay honest through the pivot rather than being quietly deleted along
with the thing they tested.

Nothing gets deleted without asking first.

## Systems

### 1. The world

Seed-based and deterministic. The same seed produces the same world, and this
is a tested property, not a hope.

| Thing | Decision |
| --- | --- |
| Tile size | 16 x 16 px |
| World size | 2000 x 800 tiles to start, configurable |
| Chunk size | 32 x 32 tiles |
| Surface biomes | Forest, plains, desert, snowy mountains, ocean at both edges |
| Depth bands | Surface, underground, caverns, deep. Rock and danger change with each |
| Sky islands | High above the mountains. Empty for now, cities later |

**Chunks are generated from the seed and their own coordinates, and from
nothing else.** Generating chunk (14, 3) gives the same result whether it is
the first chunk generated or the thousandth. This rules out any generator that
walks the world in order, and it is what makes "same seed, same world" cheap to
guarantee and cheap to test.

Features larger than a chunk — caves, trees, chests, stamped
structures — are placed by deciding them on a coarser grid. A chunk asks which
structure cells overlap it, evaluates those deterministically, and draws its
own slice of the result. The structure does not need to know it spans chunks.

**Memory.** 2000 x 800 is 1.6 million tiles. Held as bytes rather than as
engine objects, a foreground id, a background id and a light value come to
about 4.8 MB for the entire world. That comfortably fits, so the constraint is
not memory, it is the cost of *rendering* and *simulating*. Only chunks near the
camera get a tilemap and a physics body, and only those get water and creature
updates.

**Water** is cellular and per tile, settling downward and sideways, updated
only in active chunks. It is not a fluid simulation and will not be.

**Lighting** works like Terraria's: sunlight from open sky, darkness with
depth, torches and glowing tiles as sources. A light value per tile, flood
filled from sources, drawn as a low-resolution darkness texture over the world,
and recomputed only for regions marked dirty. This is the highest-risk system
in the game for performance and is treated as such in the plan.

**Saving** stores the seed plus, per chunk, only the tiles that changed. An
untouched world is a few hundred bytes. Saves live under `user://`.

### 2. The player

Mining is done with the mouse inside a reach radius. Break time is a function
of tile hardness and tool tier. Blocks, walls and furniture can be placed.

A hotbar on 1 to 0, an inventory screen, stack limits, and item drops that fly
toward the player.

Four meters, and three of them are conditional on purpose:

| Meter | When it matters |
| --- | --- |
| Health | Always |
| Hunger | Slowly, always. Should demand attention about once per in-game day |
| Oxygen | Underwater only |
| Temperature | Snow and desert biomes only |

**Survival must never become a chore.** If a meter is making the player stop
doing the interesting thing more than once a day, it is tuned wrong. These
exist to make gear meaningful and to give the ocean and the peaks teeth, not to
be managed.

A bed or camp sets the respawn point. Resting there also raises bond with
companions, which gives the player a reason to go home that is not storage.

### 3. Materials, crafting and equipment

Tiers: wood, stone, copper, iron, then two or three deeper tiers that exist
only in the deep caves. The deep tiers are the reward for depth and cannot be
reached any other way.

Crafting needs the right station in range, Terraria-style: workbench, furnace,
anvil, more later.

Gear splits into things that make you stronger (tools, melee and ranged
weapons, armour) and **things that open places**: oxygen kit, climbing claws,
warm coat, pressure suit. The second kind is the real progression, because it
is what turns "you drown" into "you go and look".

**All items, tiles and recipes are data, not code.** They live in `data/` so
that a designer can add content without opening a script. This is not a
nice-to-have: `CONTRIBUTING.md` gives design ownership of content and code
ownership of scripts, and a hardcoded item list would break that split on day
one.

### 4. Day, night and the clock

One in-game day is about 20 real minutes, shown on a visible clock. Creatures
and NPCs run their schedules on it, and sky colour and light follow it.

The clock is what turns a creature from a spawn into an inhabitant. If a
creature leaves its nest between 01:00 and 01:30, the player has to *be there
then*, and that single fact is what makes observation a mechanic rather than a
menu.

### 5. Creatures

The most important system in the game. Every species is a data file:

- habitat: biome and layer
- active hours on the clock
- diet and favourite food
- temperament: shy, neutral, territorial, aggressive
- nest or den placement rules
- whether it has eggs or young
- its power, and its companion mode

**Observation.** Watching a creature from close range without being seen fills
in its Bestiary entry, and it fills in *in order*: habitat, then schedule, then
favourite food, then how to bond. Information is the reward for patience. The
Bestiary is the quest log of a game that has no quests.

**Three ways to gain a companion**, in rising order of difficulty:

1. **Steal an egg.** Reach the nest while the parent is away — which means
   knowing its hours, which means having watched it. If the parent returns and
   sees you holding the egg inside its territory, it attacks. At home the egg
   needs the right incubation, warmth and time, and the young that hatches must
   be fed and cared for before it trusts you.
2. **Build trust.** Return at the right hour with the right food. Watch, then
   leave food, then close the distance, then stay. Trust accrues over several
   in-game days. Frightening it undoes progress. A trusting adult may follow
   you, or give you one of its young.
3. **Win over an adult.** Possible, much harder, and meant to feel earned.
   Adults hold territory and have fear that a young creature does not.

There is no capture. Nothing is thrown at a creature to make it yours. The
existing trust bar on `scripts/critter.gd` is the seed this grows from.

**Companions.** One active companion is chosen before heading out. Two modes:

- **Mount** — you ride it and use its power. Wolf: fast run, pounce, senses
  nearby creatures. Horse: overland speed. Hippogriff: flight, and the only way
  to a sky island. Whale: crosses the open ocean. Leviathan: dives deep, though
  you still need your own air.
- **Rider** — it travels on you and lends a power. Rabbit on the shoulder:
  higher jump, faster digging through dirt. A glowbug that lights the dark. A
  lizard that senses danger.

Bonded creatures not currently out stay at the base. Bond grows with care and
shared time, and a stronger bond makes the power stronger.

### 6. Gating

Every blocked place states its reason in the fiction and answers to a kind of
preparation, never to a permission.

| Place | What stops you | What gets you in |
| --- | --- | --- |
| Deep ocean | You drown | Swimming companion plus oxygen kit |
| Sky islands | Too high to reach | Flying companion |
| Snowy peaks | Cold drains health | Warm coat, or a warm-blooded companion |
| The deep caves | Dark, long way from home, stronger creatures | Light, better gear, somewhere safe to come back to |

### 7. Underground

Four bands, each a different place to be rather than a different level:

| Band | What it is |
| --- | --- |
| Surface | Grass and dirt, a few tiles deep. The rim of the Abyss is here |
| Underground | Narrow winding tunnels through dirt and stone |
| Caverns | Chambers you can lose your bearings in |
| Deep | Darker, harder rock. Further from anywhere safe |

Cutting through all of them is **the Abyss**: one chasm near the middle of the
map, widening as it falls, with a lip of harder rock along its wall. Caves open
onto it at every depth. It is numbered in layers for the story's sake, and the
rim is where Beiral stands.

**It is all one cave system.** Not a set of floors with a lift between them.
A tunnel found near the surface can lead, eventually, to the deep rock, and
that continuity is the reason to follow one rather than dig your own shaft
straight down.

**What is down there is found, not made.** Chests holding tools, torches,
materials and sometimes armour, better the deeper they are. Life crystals that
permanently add a heart. Ore visible in the walls as you walk past it. This is
the answer to "how do you get resources": you go and look, and mining is what
you do when you already know what you want.

Going back up is the cost. Nothing stops you digging a straight shaft home, and
it should stay that way, but it takes as long as it takes.

Deep caves will eventually hold societies that have never seen the sky. Leave
room for them. Do not build them yet.

### 8. Bosses

Terraria's shape: a handful of fights you choose to start, each one a wall you
prepare for rather than grind through. Beating one changes what the world does
next, so a boss is a gate on progression and not a trophy.

Rules for every boss here:

- **Summoned, not stumbled into.** You build or find the thing that calls it
  and use it when you are ready. Nothing ambushes a player who has not opted in.
- **An arena you built matters.** The fight rewards having dug, lit and
  prepared a space, which makes the building half of the game pay off in the
  fighting half.
- **It drops the key to somewhere.** Materials for gear that opens a place that
  was closed: the deepest caves, the ocean floor, the sky.
- **It belongs to a place.** A boss of the forest, of the desert, of the deep
  caves. Aerenfall does not have a boss queue; it has dangerous residents.

First one to build: a surface boss summoned at night, beatable with the first
tier of gear, dropping what is needed to survive the deep caves.

### 8. NPCs, classes and combat

NPCs move in when a condition is met, Terraria-style, and each has a job, a
home and a daily schedule on the same clock the creatures use. A merchant who
buys and sells comes first.

At the start the player picks a class: Warrior, Ranger, Rogue, Arcanist or
Beastmaster. Each gives a starting kit and a small skill tree, and skills from
other trees can be unlocked later. **The class sets your start, not your fate.**

This is the least Terraria-shaped idea in the document and it is now scheduled
last, on purpose. Terraria has no classes; it has gear that implies a
playstyle. If the gear ends up doing that job well enough, this should be cut
rather than built.

Combat is Terraria-style and the companion fights alongside. Fighting is never
the only answer: running, hiding in tall grass and bushes that break line of
sight, sneaking and avoiding are all supported, and a shy creature cannot be
befriended by someone who only knows how to swing.

## Decisions taken

Where the brief left a choice open, the simplest option that keeps the
philosophy was taken. Each is recorded here so it can be argued with later.

**Chunks generate purely from seed and coordinates.** The alternative, walking
the world in order, makes "same seed, same world" a property you hope for
instead of one you can test. Cross-chunk features use a coarse structure grid.

**The whole world's tile data lives in memory; only nearby chunks render.**
4.8 MB is affordable and it removes a whole category of streaming bug. Should
the world grow far past 2000x800, this is the first decision to revisit.

**Text maps become structure stamps.** They stop being levels and become the
hand-authored pieces the generator places, which keeps them reviewable in a
diff, keeps design's ownership of `levels/`, and keeps `tools/gen_levels.py`
useful instead of orphaned.

**The three legacy zones stay loadable.** They are a test fixture after the
pivot, not content. This is what lets the existing 39 checks keep passing
honestly rather than being deleted alongside the system they covered.

**The third shipped species is a glowbug** (rider, lights the dark). It is the
cheapest possible proof that a rider power can change what the player can *do*
rather than only what they can survive, and it pairs directly with the
lighting system built in milestone 2.

**Data files are JSON.** Godot resources are more idiomatic, but JSON is
diffable, editable without opening the engine, and writable by
`tools/`. Given design owns `data/` and may not be in Godot when adding an
item, diffability wins.

## Open questions

Things worth a decision from the owner rather than a guess. Carried into the
milestone summary rather than silently resolved.

**The viewport is 320x180.** At 16 px tiles that is 20 tiles wide by 11 tall.
That framing is right for a tight platformer and is probably too tight for a
sandbox where you want to see a cave system, aim a mouse at a distant tile, and
read the shape of a biome. 640x360 shows 40 by 22 and is still crisp pixel art.
This affects how every level and structure reads, so it wants deciding before
milestone 2, not after.

**Combat depth is unspecified.** "Terraria-style" covers a lot. The plan
assumes the placeholder's contact damage and stomping, plus one melee and one
ranged weapon, and nothing more until milestone 7.

**Nothing is decided about what is at the very bottom**, on purpose. Flagged
only so it is clear that is a choice and not an omission.
