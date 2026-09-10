class_name ChunkStore
extends RefCounted
## Holds the world's tiles and hands them out in world tile coordinates.
##
## Chunks are generated on demand and then kept. The whole world as bytes is
## under 7 MB, so there is no eviction: dropping and regenerating a chunk would
## also drop the player's edits, and keeping them is cheaper than the bug.

var gen: WorldGen
var chunks := {}   ## Vector2i -> Chunk

## Edits read from a save for chunks that have not been generated yet. A chunk
## is only built when something needs it, which can be long after loading, so
## the edits wait here and are applied the moment it is.
var pending_edits := {}

var chunks_x := 0
var chunks_y := 0


func _init(seed_value: int = 0) -> void:
	gen = WorldGen.new(seed_value)
	chunks_x = int(ceil(float(WorldGen.WIDTH) / float(Chunk.SIZE)))
	chunks_y = int(ceil(float(WorldGen.HEIGHT) / float(Chunk.SIZE)))


func world_seed() -> int:
	return gen.world_seed


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < WorldGen.WIDTH and y >= 0 and y < WorldGen.HEIGHT


func chunk_coord(x: int, y: int) -> Vector2i:
	return Vector2i(x >> 5, y >> 5)   # Chunk.SIZE is 32


func get_chunk(cx: int, cy: int) -> Chunk:
	var key := Vector2i(cx, cy)
	var chunk: Chunk = chunks.get(key)
	if chunk == null:
		chunk = Chunk.new(cx, cy)
		gen.generate_chunk(chunk)
		if pending_edits.has(key):
			var edits: Dictionary = pending_edits[key]
			for index: int in edits.keys():
				chunk.fg[index] = int(edits[index])
				chunk.edited[index] = true
			chunk.dirty_render = true
			chunk.dirty_light = true
			pending_edits.erase(key)
		chunks[key] = chunk
	return chunk


## Generate a chunk without keeping it. Used by the determinism checks, which
## have to be able to ask for the same chunk twice from a clean slate.
func generate_detached(cx: int, cy: int) -> Chunk:
	var chunk := Chunk.new(cx, cy)
	gen.generate_chunk(chunk)
	return chunk


func get_fg(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return 0
	var chunk := get_chunk(x >> 5, y >> 5)
	return chunk.fg[(y & 31) * Chunk.SIZE + (x & 31)]


func get_bg(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return 0
	var chunk := get_chunk(x >> 5, y >> 5)
	return chunk.bg[(y & 31) * Chunk.SIZE + (x & 31)]


func get_water(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return 0
	var chunk := get_chunk(x >> 5, y >> 5)
	return chunk.water[(y & 31) * Chunk.SIZE + (x & 31)]


func set_fg(x: int, y: int, id: int) -> void:
	if not in_bounds(x, y):
		return
	var chunk := get_chunk(x >> 5, y >> 5)
	chunk.set_fg(x & 31, y & 31, id)


func is_solid(x: int, y: int) -> bool:
	return TileDB.get_db().is_solid(get_fg(x, y))


## The first air tile below the sky at this column, which is where a player or
## a creature gets put down.
func surface_y(x: int) -> int:
	return gen.surface_height(x)
