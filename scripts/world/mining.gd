class_name Mining
extends Node2D
## Digging and placing with the mouse.
##
## Break time is hardness divided by dig power, so a tier of tool later only
## has to change one number. The target tile is drawn with its progress so the
## player can see that holding the button is doing something, which is the
## difference between "slow" and "broken".

const TILE := 16
const REACH := 5.0          ## tiles, measured centre to centre
const DIG_POWER := 20.0     ## hardness units per second. Tool tiers scale this.
## Holding the place button lays a run of tiles, at this interval. One press
## per tile turns building a wall into a clicking exercise.
const PLACE_INTERVAL := 0.12

signal tile_changed(x: int, y: int)

var store: ChunkStore
var renderer: ChunkRenderer
var world: Node2D

var placeable: Array[String] = ["dirt", "stone", "torch"]
var place_index := 0

## Playtests aim here instead of using the real cursor. Everything downstream
## of the aim is the same code the player exercises: reach, break time,
## support rules, overlap.
var aim_override := Vector2.INF

var _target := Vector2i(-9999, -9999)
var _progress := 0.0
var _in_reach := false
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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cycle_place"):
		place_index = (place_index + 1) % placeable.size()


func _process(delta: float) -> void:
	if world == null or world.player == null or not is_instance_valid(world.player):
		return

	var mouse := aim_override if aim_override != Vector2.INF else get_global_mouse_position()
	var tile := Vector2i(int(floor(mouse.x / TILE)), int(floor(mouse.y / TILE)))
	var centre: Vector2 = world.player.global_position / float(TILE)
	_in_reach = Vector2(tile).distance_to(centre) <= REACH

	if tile != _target:
		_target = tile
		_progress = 0.0

	_place_cooldown = maxf(0.0, _place_cooldown - delta)

	if _in_reach:
		if Input.is_action_pressed("mine"):
			_dig(delta)
		elif Input.is_action_pressed("place"):
			if _place_cooldown <= 0.0:
				_place_cooldown = PLACE_INTERVAL
				_place()
		else:
			_progress = 0.0
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
	if _progress >= float(hardness):
		_progress = 0.0
		_set_tile(_target.x, _target.y, 0)


func _place() -> void:
	if store.get_fg(_target.x, _target.y) != 0:
		return
	var id := _db.id(selected_tile_name())
	if id == 0:
		return
	# Nothing floats in mid air: it needs rock next to it or a wall behind it.
	if not _has_support(_target.x, _target.y):
		return
	# And it may not be placed inside the player.
	if _db.is_solid(id) and _overlaps_player(_target):
		return
	_set_tile(_target.x, _target.y, id)


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
	var edge := Color(1, 1, 1, 0.55) if _in_reach else Color(1, 1, 1, 0.12)
	draw_rect(rect, edge, false, 1.0)

	if _progress > 0.0:
		var id := store.get_fg(_target.x, _target.y)
		var hardness := _db.hardness[id] if id > 0 else 1
		if hardness > 0:
			var t := clampf(_progress / float(hardness), 0.0, 1.0)
			draw_rect(Rect2(rect.position, Vector2(TILE * t, 2.0)), Color(1, 0.9, 0.5, 0.9))
