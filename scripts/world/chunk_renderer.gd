class_name ChunkRenderer
extends Node2D
## Draws the chunks near the camera and forgets the rest.
##
## Three TileMapLayers total, not one per chunk. Cells for a chunk are written
## when it enters the window and erased when it leaves, so the number of live
## cells stays bounded by the window rather than by the size of the world.

const SOURCE_ID := 0
const TILESET := preload("res://assets/tiles/tileset.tres")
const WATER_ATLAS := 21
const EDGE_ATLAS := 22

var store: ChunkStore
var bg_layer: TileMapLayer
var water_layer: TileMapLayer
var fg_layer: TileMapLayer
var edge_layer: TileMapLayer

var _loaded := {}
var _db: TileDB
var _grass := 0


func setup(chunk_store: ChunkStore) -> void:
	store = chunk_store
	bg_layer = _make_layer("Background", -2)
	water_layer = _make_layer("Water", -1)
	fg_layer = _make_layer("Tiles", 0)
	edge_layer = _make_layer("Edges", 1)
	_db = TileDB.get_db()
	_grass = _db.id("grass")
	# Walls sit behind everything and must never be mistaken for something you
	# can stand on, so they are drawn darker than the solid tile of the same rock.
	bg_layer.modulate = Color(0.85, 0.86, 0.92)


func _make_layer(layer_name: String, z: int) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = TILESET
	layer.z_index = z
	add_child(layer)
	return layer


func loaded_count() -> int:
	return _loaded.size()


func refresh(centre: Vector2i, radius: int) -> void:
	var wanted := {}
	for cx in range(centre.x - radius, centre.x + radius + 1):
		for cy in range(centre.y - radius, centre.y + radius + 1):
			if cx < 0 or cy < 0 or cx >= store.chunks_x or cy >= store.chunks_y:
				continue
			wanted[Vector2i(cx, cy)] = true

	for key: Vector2i in _loaded.keys():
		if not wanted.has(key):
			_unload(key)

	for key: Vector2i in wanted.keys():
		var chunk := store.get_chunk(key.x, key.y)
		if not _loaded.has(key) or chunk.dirty_render:
			_draw_chunk(key, chunk)


func _draw_chunk(key: Vector2i, chunk: Chunk) -> void:
	var ox := key.x * Chunk.SIZE
	var oy := key.y * Chunk.SIZE
	for ly in Chunk.SIZE:
		for lx in Chunk.SIZE:
			var i := ly * Chunk.SIZE + lx
			var cell := Vector2i(ox + lx, oy + ly)
			_put(fg_layer, cell, chunk.fg[i])
			_put(bg_layer, cell, chunk.bg[i])
			_edge(cell.x, cell.y, chunk.fg[i])
			if chunk.water[i] > 0:
				water_layer.set_cell(cell, SOURCE_ID, Vector2i(WATER_ATLAS, 0))
			else:
				water_layer.erase_cell(cell)
	chunk.dirty_render = false
	_loaded[key] = true


func _put(layer: TileMapLayer, cell: Vector2i, id: int) -> void:
	if id == 0:
		layer.erase_cell(cell)
	else:
		layer.set_cell(cell, SOURCE_ID, Vector2i(id, 0))


func _unload(key: Vector2i) -> void:
	var ox := key.x * Chunk.SIZE
	var oy := key.y * Chunk.SIZE
	for ly in Chunk.SIZE:
		for lx in Chunk.SIZE:
			var cell := Vector2i(ox + lx, oy + ly)
			fg_layer.erase_cell(cell)
			bg_layer.erase_cell(cell)
			water_layer.erase_cell(cell)
			edge_layer.erase_cell(cell)
	_loaded.erase(key)


## Whether this tile wears a lit lip: solid, with open air above it. Grass is
## skipped because it already has a green top of its own and would double up.
func _edge(x: int, y: int, id: int) -> void:
	var cell := Vector2i(x, y)
	if id != 0 and id != _grass and _db.is_solid(id) and not _db.is_solid(store.get_fg(x, y - 1)):
		edge_layer.set_cell(cell, SOURCE_ID, Vector2i(EDGE_ATLAS, 0))
	else:
		edge_layer.erase_cell(cell)


## One tile changed. Redraw that cell, and the one under it, whose lip appears
## or disappears depending on what just happened above it.
func update_tile(x: int, y: int) -> void:
	var cell := Vector2i(x, y)
	_put(fg_layer, cell, store.get_fg(x, y))
	_put(bg_layer, cell, store.get_bg(x, y))
	_edge(x, y, store.get_fg(x, y))
	_edge(x, y + 1, store.get_fg(x, y + 1))
