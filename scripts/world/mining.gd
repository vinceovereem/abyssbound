class_name Mining
extends Node2D
## Digging and placing, from the keyboard, one tile at a time.
##
## You can only reach what you could actually touch: the block you are standing
## on, and the ones directly beside and above you. Which of them is decided by
## the direction you are holding, so digging is aimed with the same keys you
## walk with rather than with a cursor:
##
##   F              break the tile you are facing
##   Down + F       break the tile under your feet
##   Up + F         break the tile over your head
##   G              same three directions, but places instead
##
## Break time is hardness over dig power, so a tier of tool later changes one
## number rather than this file.

const TILE := 16
const DIG_POWER := 20.0
## Holding the place key lays a run of tiles at this interval.
const PLACE_INTERVAL := 0.14

signal tile_changed(x: int, y: int)
signal tile_broken(x: int, y: int, drop: String)
signal tile_placed(x: int, y: int, tile_name: String)

var store: ChunkStore
var renderer: ChunkRenderer
var world: Node2D

var placeable: Array[String] = ["dirt", "stone", "torch"]
var place_index := 0

var _target := Vector2i(-9999, -9999)
var _progress := 0.0
var _place_cooldown := 0.0
var _db: TileDB


func setup(world_node: Node2D, chunk_store: ChunkStore, chunk_renderer: ChunkRenderer) -> void:
	world = world_node
	store = chunk_store
	renderer = chunk_renderer
	_db = TileDB.get_db()
	z_index = 5


func selected_tile_name() -> String:
	return placeable[place_index]


## The one tile within arm's reach, chosen by which direction is held.
func target_tile() -> Vector2i:
	if world == null or world.player == null or not is_instance_valid(world.player):
		return Vector2i(-9999, -9999)
	var here: Vector2i = world.player_tile()
	if Input.is_action_pressed("move_down"):
		return here + Vector2i(0, 1)
	if Input.is_action_pressed("move_up"):
		return here + Vector2i(0, -1)
	var facing: int = world.player.facing()
	return here + Vector2i(facing, 0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cycle_place"):
		place_index = (place_index + 1) % placeable.size()


func _process(delta: float) -> void:
	if world == null or world.player == null or not is_instance_valid(world.player):
		return

	_place_cooldown = maxf(0.0, _place_cooldown - delta)

	var tile := target_tile()
	if tile != _target:
		_target = tile
		_progress = 0.0

	if Input.is_action_pressed("mine"):
		_dig(delta)
	elif Input.is_action_pressed("place"):
		if _place_cooldown <= 0.0:
			_place_cooldown = PLACE_INTERVAL
			_place()
	else:
		_progress = 0.0

	queue_redraw()


func _dig(delta: float) -> void:
	var id := store.get_fg(_target.x, _target.y)
	if id == 0:
		_progress = 0.0
		return
	var hardness := _db.hardness[id]
	if hardness <= 0:
		return
	_progress += DIG_POWER * delta
	if _progress < float(hardness):
		return

	_progress = 0.0
	var drop := _db.drop_of(id)
	_set_tile(_target.x, _target.y, 0)
	if not drop.is_empty():
		Game.collect(drop, 1)
		tile_broken.emit(_target.x, _target.y, drop)


func _place() -> void:
	if store.get_fg(_target.x, _target.y) != 0:
		return
	var id := _db.id(selected_tile_name())
	if id == 0:
		return
	if not _has_support(_target.x, _target.y):
		return
	if _db.is_solid(id) and _overlaps_player(_target):
		return
	_set_tile(_target.x, _target.y, id)
	tile_placed.emit(_target.x, _target.y, selected_tile_name())


func _has_support(x: int, y: int) -> bool:
	if store.get_bg(x, y) != 0:
		return true
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if store.get_fg(x + d.x, y + d.y) != 0:
			return true
	return false


func _overlaps_player(tile: Vector2i) -> bool:
	var tile_rect := Rect2(tile.x * TILE, tile.y * TILE, TILE, TILE)
	var p: Vector2 = world.player.global_position
	var body := Rect2(p.x - 6.0, p.y - 10.0, 12.0, 20.0)
	return tile_rect.intersects(body)


func _set_tile(x: int, y: int, id: int) -> void:
	store.set_fg(x, y, id)
	renderer.update_tile(x, y)
	tile_changed.emit(x, y)


func _draw() -> void:
	if _target.x < -1000:
		return
	var rect := Rect2(_target.x * TILE, _target.y * TILE, TILE, TILE)
	# Solid outline on something breakable, faint on empty air, so the aim is
	# readable before the key goes down.
	var reachable := store.get_fg(_target.x, _target.y) != 0
	draw_rect(rect, Color(1, 1, 1, 0.6 if reachable else 0.15), false, 1.0)

	if _progress > 0.0:
		var id := store.get_fg(_target.x, _target.y)
		var hardness := _db.hardness[id] if id > 0 else 1
		if hardness > 0:
			var t := clampf(_progress / float(hardness), 0.0, 1.0)
			draw_rect(Rect2(rect.position, Vector2(TILE * t, 2.0)), Color(1, 0.9, 0.5, 0.95))
