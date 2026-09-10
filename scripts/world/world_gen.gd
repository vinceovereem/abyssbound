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
const CAVERN_TOP := 300
const ABYSS_TOP := 460
const ABYSS_CENTER_X := 1000
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
var _shaft := FastNoiseLite.new()
var _island := FastNoiseLite.new()

# Tile ids, resolved once so the inner loops compare integers.
var AIR := 0
var DIRT := 0
var GRASS := 0
var STONE := 0
var SAND := 0
var SNOW := 0
var WOOD := 0
var LEAVES := 0
var COPPER := 0
var IRON := 0
var ICE := 0
var ABYSS := 0
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
	LEAVES = _db.id("leaves")
	COPPER = _db.id("copper_ore")
	IRON = _db.id("iron_ore")
	ICE = _db.id("ice")
	ABYSS = _db.id("abyss_stone")
	DIRT_WALL = _db.id("dirt_wall")
	STONE_WALL = _db.id("stone_wall")

	_setup(_height, 0, FastNoiseLite.TYPE_SIMPLEX, 0.006, 3)
	_setup(_cave, 1, FastNoiseLite.TYPE_SIMPLEX, 0.028, 2)
	_setup(_cavern, 2, FastNoiseLite.TYPE_SIMPLEX, 0.020, 2)
	_setup(_copper, 3, FastNoiseLite.TYPE_SIMPLEX, 0.090, 1)
	_setup(_iron, 4, FastNoiseLite.TYPE_SIMPLEX, 0.090, 1)
	_setup(_shaft, 5, FastNoiseLite.TYPE_SIMPLEX, 0.010, 2)
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
# The Abyss
# ---------------------------------------------------------------------------
func shaft_center(y: int) -> int:
	return ABYSS_CENTER_X + int(round(_shaft.get_noise_1d(float(y) * 1.5) * 14.0))


func shaft_half_width(y: int) -> int:
	return 10 + int(y / 90)


func in_shaft(x: int, y: int) -> bool:
	if y < 40:
		return false
	return absi(x - shaft_center(y)) <= shaft_half_width(y)


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
	if in_shaft(x, surface_height(x) + 1):
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

	chunk.generated = true
	chunk.dirty_render = true
	chunk.dirty_light = true


func _tile_at(x: int, y: int, h: int, ci: int, heights: PackedInt32Array, tree_h: PackedInt32Array) -> int:
	# The shaft cuts through everything, so it is tested first.
	if in_shaft(x, y):
		return AIR

	if y < h:
		var canopy := _canopy_at(x, y, ci, heights, tree_h)
		if canopy != AIR:
			return canopy
		if _is_sky_island(x, y):
			return GRASS if not _is_sky_island(x, y - 1) else DIRT
		return AIR

	var b := biome_name(x)
	var depth := y - h

	# Caves. Tunnels first, then the big cavern voids further down.
	if depth > 6:
		var width := lerpf(0.035, 0.075, clampf(float(depth) / 420.0, 0.0, 1.0))
		if absf(_cave.get_noise_2d(float(x), float(y) * 1.6)) < width:
			return AIR
		if y > CAVERN_TOP and _cavern.get_noise_2d(float(x) * 0.6, float(y) * 0.9) > 0.42:
			return AIR

	if y >= ABYSS_TOP:
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
			return WOOD
		var ddy := y - top
		if dx * dx + ddy * ddy <= 6:
			return LEAVES
	return AIR


func _is_sky_island(x: int, y: int) -> bool:
	if x < SKY_ISLAND_X0 or x > SKY_ISLAND_X1 or y < 18 or y > 62:
		return false
	return _island.get_noise_2d(float(x) * 0.9, float(y) * 2.2) > 0.42


func _wall_at(x: int, y: int, h: int, fg: int) -> int:
	# The shaft keeps its rock wall. Leaving it empty let the daylight backdrop
	# through, which made the mouth of the Abyss read as a cliff over open sky
	# instead of a hole in the ground. Its darkness is the lighting's job.
	if in_shaft(x, y):
		return 0 if y <= h + 4 else STONE_WALL
	if y <= h:
		return 0
	if y >= ABYSS_TOP:
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
