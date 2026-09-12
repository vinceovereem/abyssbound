class_name WorldGen
extends RefCounted
## Turns a seed into Aerenfall.
##
## The one rule this file must never break: a chunk is a pure function of the
## seed and its own coordinates. Nothing here may depend on which chunks were
## generated before it, because "same seed, same world" is a tested property
## and cross-chunk state is how that quietly stops being true.
##
## Features bigger than a chunk stay deterministic by being recomputed rather
## than remembered. A tree whose leaves spill across a chunk edge is found by
## asking the neighbouring columns whether they hold a trunk, not by a previous
## chunk having written leaves into this one.

const WIDTH := 2000
const HEIGHT := 800

const SEA_LEVEL := 130
## Where the rock opens out. Above this the underground is tunnels; below it
## there are chambers big enough to lose your bearings in.
const CAVERN_TOP := 200
## Darker, harder rock. Depth for its own sake, not a separate place.
const DEEP_TOP := 460

## The Abyss itself: one enormous chasm through the middle of the world.
##
## It came out once, because when it was the *only* interesting place to go the
## rest of the underground was just rock you tunnelled through. It is back now
## that the caves stand on their own, and the two work on each other: cave
## systems open onto the chasm wall at every depth, so it is a hub rather than
## a corridor, and the rim is somewhere to stand and look down.
const ABYSS_CENTRE := 1000
const ABYSS_RIM := 118
## Half width at the rim, and how much wider it gets per tile of depth.
const ABYSS_MOUTH := 15
const ABYSS_FLARE := 0.030
## Rock shelves across the chasm, alternating sides, so going down it is a
## climb rather than one long fall onto the bottom. Without these the Abyss is
## a hole you drop through, which is not somewhere to go.
const LEDGE_EVERY := 13
const LEDGE_THICK := 2
const SKY_ISLAND_X0 := 1100
const SKY_ISLAND_X1 := 1450

## How wide the blend between two biomes is, in tiles.
const TRANSITION := 48.0

const BIOMES := [
	{ "name": "ocean",     "end": 120,  "base": 168.0, "amp": 3.0 },
	{ "name": "plains",    "end": 420,  "base": 128.0, "amp": 5.0 },
	{ "name": "forest",    "end": 700,  "base": 124.0, "amp": 7.0 },
	{ "name": "desert",    "end": 900,  "base": 132.0, "amp": 6.0 },
	{ "name": "plains",    "end": 1100, "base": 128.0, "amp": 5.0 },
	{ "name": "mountains", "end": 1450, "base": 86.0,  "amp": 30.0 },
	{ "name": "forest",    "end": 1750, "base": 124.0, "amp": 7.0 },
	{ "name": "plains",    "end": 1880, "base": 128.0, "amp": 5.0 },
	{ "name": "ocean",     "end": 2000, "base": 168.0, "amp": 3.0 },
]

var world_seed := 0

var _db: TileDB
var _height := FastNoiseLite.new()
var _cave := FastNoiseLite.new()
var _cavern := FastNoiseLite.new()
var _copper := FastNoiseLite.new()
var _iron := FastNoiseLite.new()
var _cross := FastNoiseLite.new()
var _chasm := FastNoiseLite.new()
var _island := FastNoiseLite.new()

# Tile ids, resolved once so the inner loops compare integers.
var AIR := 0
var DIRT := 0
var GRASS := 0
var STONE := 0
var SAND := 0
var SNOW := 0
var WOOD := 0
var TRUNK := 0
var LEAVES := 0
var COPPER := 0
var IRON := 0
var ICE := 0
var ABYSS := 0
var CHEST := 0
var CRYSTAL := 0
var DIRT_WALL := 0
var STONE_WALL := 0


func _init(seed_value: int = 0) -> void:
	world_seed = seed_value
	_db = TileDB.get_db()

	DIRT = _db.id("dirt")
	GRASS = _db.id("grass")
	STONE = _db.id("stone")
	SAND = _db.id("sand")
	SNOW = _db.id("snow")
	WOOD = _db.id("wood")
	TRUNK = _db.id("tree_trunk")
	LEAVES = _db.id("leaves")
	COPPER = _db.id("copper_ore")
	IRON = _db.id("iron_ore")
	ICE = _db.id("ice")
	ABYSS = _db.id("abyss_stone")
	CHEST = _db.id("chest")
	CRYSTAL = _db.id("life_crystal")
	DIRT_WALL = _db.id("dirt_wall")
	STONE_WALL = _db.id("stone_wall")

	_setup(_height, 0, FastNoiseLite.TYPE_SIMPLEX, 0.006, 3)
	_setup(_cave, 1, FastNoiseLite.TYPE_SIMPLEX, 0.028, 2)
	_setup(_cavern, 2, FastNoiseLite.TYPE_SIMPLEX, 0.020, 2)
	_setup(_copper, 3, FastNoiseLite.TYPE_SIMPLEX, 0.090, 1)
	_setup(_iron, 4, FastNoiseLite.TYPE_SIMPLEX, 0.090, 1)
	_setup(_cross, 5, FastNoiseLite.TYPE_SIMPLEX, 0.021, 2)
	_setup(_chasm, 8, FastNoiseLite.TYPE_SIMPLEX, 0.008, 2)
	_setup(_island, 6, FastNoiseLite.TYPE_SIMPLEX, 0.035, 2)


func _setup(n: FastNoiseLite, salt: int, type: int, freq: float, octaves: int) -> void:
	n.seed = world_seed + salt * 7919
	n.noise_type = type
	n.frequency = freq
	n.fractal_octaves = octaves


# ---------------------------------------------------------------------------
# Surface shape
# ---------------------------------------------------------------------------
func biome_index(x: int) -> int:
	for i in BIOMES.size():
		if x < int(BIOMES[i]["end"]):
			return i
	return BIOMES.size() - 1


func biome_name(x: int) -> String:
	return str(BIOMES[biome_index(x)]["name"])


## Blend a biome field across the boundary so there is no cliff between them.
## Both sides of a boundary evaluate to the same value, which keeps the surface
## continuous without any biome needing to know about its neighbours.
func _blend(x: int, key: String) -> float:
	var i := biome_index(x)
	var here := float(BIOMES[i][key])
	var start := 0 if i == 0 else int(BIOMES[i - 1]["end"])
	var end := int(BIOMES[i]["end"])

	if i > 0 and float(x - start) < TRANSITION:
		var t := 0.5 + 0.5 * float(x - start) / TRANSITION
		return lerpf(float(BIOMES[i - 1][key]), here, t)
	if i < BIOMES.size() - 1 and float(end - x) < TRANSITION:
		var t := 0.5 * float(x - (end - int(TRANSITION))) / TRANSITION
		return lerpf(here, float(BIOMES[i + 1][key]), t)
	return here


func surface_height(x: int) -> int:
	var base := _blend(x, "base")
	var amp := _blend(x, "amp")
	var n := _height.get_noise_1d(float(x))
	return clampi(int(round(base + n * amp)), 24, HEIGHT - 60)


# ---------------------------------------------------------------------------
# Depth
# ---------------------------------------------------------------------------
## How deep you are, as a band: 0 surface, 1 underground, 2 caverns, 3 deep.
## Replaced a single giant chasm, which made one column of the map the only
## interesting place to go.
func depth_band(y: int, surface: int) -> int:
	if y < surface + 8:
		return 0
	if y < CAVERN_TOP:
		return 1
	if y < DEEP_TOP:
		return 2
	return 3


## The chasm wanders as it descends rather than falling in a straight line.
func abyss_centre(y: int) -> int:
	return ABYSS_CENTRE + int(round(_chasm.get_noise_1d(float(y) * 1.4) * 26.0))


func abyss_half_width(y: int) -> int:
	if y < ABYSS_RIM:
		return 0
	return ABYSS_MOUTH + int(float(y - ABYSS_RIM) * ABYSS_FLARE)


func in_abyss(x: int, y: int) -> bool:
	if y < ABYSS_RIM:
		return false
	return absi(x - abyss_centre(y)) <= abyss_half_width(y)


## A shelf reaching out from one wall, leaving a gap at the other end to drop
## through. Which wall alternates as you descend, so the way down zig-zags.
func abyss_ledge(x: int, y: int) -> bool:
	if y < ABYSS_RIM + LEDGE_EVERY:
		return false
	if (y - ABYSS_RIM) % LEDGE_EVERY >= LEDGE_THICK:
		return false
	var centre := abyss_centre(y)
	var half := abyss_half_width(y)
	# A little jitter so the gaps do not line up into a straight chute.
	var reach := int(float(half) * 1.45) + int(_chasm.get_noise_1d(float(y) * 6.0) * 4.0)
	if ((y - ABYSS_RIM) / LEDGE_EVERY) % 2 == 0:
		return x <= centre - half + reach
	return x >= centre + half - reach


## How far into the chasm's wall a tile is, in tiles. Negative means inside the
## open air of it. Used to put a lip of harder rock along the edge.
func abyss_wall_depth(x: int, y: int) -> int:
	if y < ABYSS_RIM:
		return 9999
	return absi(x - abyss_centre(y)) - abyss_half_width(y)


## Which Abyss layer a depth belongs to, 0 meaning not down there.
func abyss_layer(y: int) -> int:
	if y < ABYSS_RIM:
		return 0
	return 1 + mini(4, int(float(y - ABYSS_RIM) / float(HEIGHT - ABYSS_RIM) * 5.0))


func band_name(y: int, surface: int) -> String:
	return ["surface", "underground", "caverns", "deep"][depth_band(y, surface)]


# ---------------------------------------------------------------------------
# What is waiting in the caves
#
# One candidate per grid cell, decided by a hash of the cell, then kept only if
# it lands somewhere a thing could actually sit. That keeps placement a pure
# function of position, so the same seed puts the same chest in the same cave.
# ---------------------------------------------------------------------------
const CHEST_CELL := 60
const CRYSTAL_CELL := 90


func _candidate(cell_x: int, cell_y: int, cell: int, salt: int) -> Vector2i:
	var h := _hash(cell_x * 7919 + cell_y * 104729, salt)
	return Vector2i(cell_x * cell + h % cell, cell_y * cell + (h / cell) % cell)


func is_chest_spot(x: int, y: int) -> bool:
	if y < CAVERN_TOP - 70 or y > HEIGHT - 20:
		return false
	return _candidate(x / CHEST_CELL, y / CHEST_CELL, CHEST_CELL, 31) == Vector2i(x, y)


func is_crystal_spot(x: int, y: int) -> bool:
	if y < CAVERN_TOP + 40 or y > HEIGHT - 20:
		return false
	return _candidate(x / CRYSTAL_CELL, y / CRYSTAL_CELL, CRYSTAL_CELL, 57) == Vector2i(x, y)


## What is inside the chest at this spot. Deterministic, and better the deeper
## you went to find it.
func chest_loot(x: int, y: int) -> Array:
	var r := _hash(x * 13 + y, 91)
	var deep := clampf(float(y) / float(HEIGHT), 0.0, 1.0)
	var out: Array = [["torch", 5 + r % 8]]

	var picks := ["wood_pick", "stone_pick", "copper_pick", "iron_pick"]
	out.append([picks[mini(3, int(deep * 4.5))], 1])

	match (r / 7) % 4:
		0: out.append(["copper_ore", 8 + (r / 11) % 12])
		1: out.append(["iron_ore", 6 + (r / 11) % 10])
		2: out.append(["wood", 18 + (r / 11) % 20])
		_: out.append(["stone", 20 + (r / 11) % 25])

	if deep > 0.45 and (r / 3) % 3 == 0:
		out.append([["copper_helm", "copper_greaves", "iron_helm"][(r / 5) % 3], 1])
	if deep > 0.6:
		out.append([["copper_bar", "iron_bar"][(r / 17) % 2], 3 + (r / 19) % 6])
	return out


# ---------------------------------------------------------------------------
# Trees
# ---------------------------------------------------------------------------
func _hash(x: int, salt: int) -> int:
	var h := (x * 374761393) ^ (salt * 668265263) ^ (world_seed * 1274126177)
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))


func _is_tree(x: int) -> bool:
	var b := biome_name(x)
	if b != "forest" and b != "plains":
		return false
	if in_abyss(x, surface_height(x) + 2):
		return false
	return _hash(x, 7) % 9 == 0


func _tree_height(x: int) -> int:
	return 4 + _hash(x, 8) % 4


# ---------------------------------------------------------------------------
# Generation
# ---------------------------------------------------------------------------
func generate_chunk(chunk: Chunk) -> void:
	var x0 := chunk.cx * Chunk.SIZE
	var y0 := chunk.cy * Chunk.SIZE

	# Columns are shared by every row in the chunk, and trees reach two columns
	# sideways, so both are computed once with a two column margin.
	var span := Chunk.SIZE + 4
	var heights := PackedInt32Array()
	var tree_h := PackedInt32Array()
	heights.resize(span)
	tree_h.resize(span)
	for i in span:
		var wx := x0 - 2 + i
		heights[i] = surface_height(wx) if wx >= 0 and wx < WIDTH else 9999
		tree_h[i] = _tree_height(wx) if (wx >= 0 and wx < WIDTH and _is_tree(wx)) else -1

	for ly in Chunk.SIZE:
		var wy := y0 + ly
		for lx in Chunk.SIZE:
			var wx := x0 + lx
			var i := ly * Chunk.SIZE + lx
			if wx < 0 or wx >= WIDTH or wy < 0 or wy >= HEIGHT:
				chunk.fg[i] = AIR
				chunk.bg[i] = 0
				continue

			var h := heights[lx + 2]
			var fg := _tile_at(wx, wy, h, lx + 2, heights, tree_h)
			chunk.fg[i] = fg
			chunk.bg[i] = _wall_at(wx, wy, h, fg)
			chunk.water[i] = _water_at(wx, wy, h, fg)

	_place_finds(chunk, x0, y0, heights, tree_h)

	chunk.generated = true
	chunk.dirty_render = true
	chunk.dirty_light = true


## Chests and life crystals, laid in after the rock so they can ask what is
## underneath them without the rock having to know they exist.
func _place_finds(chunk: Chunk, x0: int, y0: int,
		heights: PackedInt32Array, tree_h: PackedInt32Array) -> void:
	for ly in Chunk.SIZE:
		var wy := y0 + ly
		for lx in Chunk.SIZE:
			var i := ly * Chunk.SIZE + lx
			if chunk.fg[i] != AIR:
				continue
			var wx := x0 + lx
			var chest := is_chest_spot(wx, wy)
			if not chest and not is_crystal_spot(wx, wy):
				continue
			var h := heights[lx + 2]
			# Only if there is a floor to stand it on.
			if not _db.is_solid(_tile_at(wx, wy + 1, h, lx + 2, heights, tree_h)):
				continue
			chunk.fg[i] = CHEST if chest else CRYSTAL


func _tile_at(x: int, y: int, h: int, ci: int, heights: PackedInt32Array, tree_h: PackedInt32Array) -> int:
	if y < h:
		var canopy := _canopy_at(x, y, ci, heights, tree_h)
		if canopy != AIR:
			return canopy
		if _is_sky_island(x, y):
			return GRASS if not _is_sky_island(x, y - 1) else DIRT
		return AIR

	var b := biome_name(x)
	var depth := y - h

	# The chasm cuts through everything. Caves meet it at every depth, which is
	# what makes it a hub instead of a corridor.
	if in_abyss(x, y):
		return ABYSS if abyss_ledge(x, y) else AIR

	# Caves you explore rather than rock you tunnel through.
	#
	# Three things overlapping: winding tunnels that widen with depth, big
	# chambers once you are past the cavern line, and a second set of tunnels
	# at a different frequency whose only job is to join the first two up.
	# Without the third, the chambers are pockets and the tunnels never meet.
	if depth > 4:
		var deep_ratio := clampf(float(depth) / 380.0, 0.0, 1.0)

		var tunnel := absf(_cave.get_noise_2d(float(x), float(y) * 1.5))
		if tunnel < lerpf(0.055, 0.105, deep_ratio):
			return AIR

		if y > CAVERN_TOP:
			var chamber := _cavern.get_noise_2d(float(x) * 1.05, float(y) * 1.35)
			var opens_at := lerpf(0.38, 0.34, clampf(float(y - CAVERN_TOP) / 380.0, 0.0, 1.0))
			if chamber > opens_at:
				return AIR

		if depth > 16 and absf(_cross.get_noise_2d(float(x) * 0.7, float(y) * 2.2)) < 0.05:
			return AIR

	# A lip of harder rock along the chasm wall, so the edge reads as an edge.
	if abyss_wall_depth(x, y) <= 2:
		return ABYSS

	if y >= DEEP_TOP:
		return ABYSS

	# The top few tiles follow the biome, everything under them is rock.
	if depth == 0:
		if b == "desert" or b == "ocean":
			return SAND
		if b == "mountains" and y < 100:
			return SNOW
		return GRASS
	if depth <= 4:
		if b == "desert" or b == "ocean":
			return SAND
		if b == "mountains" and y < 104:
			return SNOW if depth <= 2 else ICE
		return DIRT

	var stone := STONE
	if depth > 16 and y < 420 and _copper.get_noise_2d(float(x) * 2.0, float(y) * 2.0) > 0.85:
		stone = COPPER
	elif depth > 40 and y < 620 and _iron.get_noise_2d(float(x) * 2.0, float(y) * 2.0) > 0.89:
		stone = IRON
	return stone


## Leaves and trunks. Reads the neighbouring columns rather than remembering
## what an earlier chunk drew, which is what keeps trees chunk-independent.
func _canopy_at(x: int, y: int, ci: int, heights: PackedInt32Array, tree_h: PackedInt32Array) -> int:
	for dx in range(-2, 3):
		var j := ci + dx
		if j < 0 or j >= tree_h.size():
			continue
		var th := tree_h[j]
		if th < 0:
			continue
		var trunk_base := heights[j]
		var top := trunk_base - th
		if dx == 0 and y >= top and y < trunk_base:
			return TRUNK
		var ddy := y - top
		if dx * dx + ddy * ddy <= 6:
			return LEAVES
	return AIR


func _is_sky_island(x: int, y: int) -> bool:
	if x < SKY_ISLAND_X0 or x > SKY_ISLAND_X1 or y < 18 or y > 62:
		return false
	return _island.get_noise_2d(float(x) * 0.9, float(y) * 2.2) > 0.42


func _wall_at(x: int, y: int, h: int, fg: int) -> int:
	# The chasm keeps rock behind it below the rim. Leaving it empty lets the
	# sky show through and the mouth reads as a cliff over open air instead of
	# a hole in the ground; that was a real bug once.
	if in_abyss(x, y):
		return 0 if y <= ABYSS_RIM + 3 else STONE_WALL
	if y <= h:
		return 0
	if y >= DEEP_TOP:
		return STONE_WALL
	return DIRT_WALL if y <= h + 8 else STONE_WALL


func _water_at(x: int, y: int, h: int, fg: int) -> int:
	if fg != AIR:
		return 0
	if y < SEA_LEVEL:
		return 0
	if biome_name(x) != "ocean":
		return 0
	return 8
