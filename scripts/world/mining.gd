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
## Digging with your hands. A pickaxe replaces this, which is the whole reason
## to make one.
const HAND_POWER := 14.0
## How far a crafting station can be and still count as being at it.
const STATION_REACH := 6
## Holding the place key lays a run of tiles at this interval.
const PLACE_INTERVAL := 0.14

signal tile_changed(x: int, y: int)
signal tile_broken(x: int, y: int, drop: String)
signal tile_placed(x: int, y: int, tile_name: String)
signal chest_opened(x: int, y: int, loot: Array)
signal heart_gained(x: int, y: int)
signal tree_felled(x: int, y: int, wood: int)

var store: ChunkStore
var renderer: ChunkRenderer
var world: Node2D

var _items: ItemDB

var _target := Vector2i(-9999, -9999)
var _progress := 0.0
var _place_cooldown := 0.0
var _db: TileDB


func setup(world_node: Node2D, chunk_store: ChunkStore, chunk_renderer: ChunkRenderer) -> void:
	world = world_node
	store = chunk_store
	renderer = chunk_renderer
	_db = TileDB.get_db()
	_items = ItemDB.get_db()
	z_index = 5


## What is in the selected hotbar slot, as a tile name, or "" if that slot is
## empty or holds something that is not a block.
func selected_tile_name() -> String:
	return _items.tile_of(Game.inventory.selected_item())


## How fast we dig: the selected tool, or bare hands.
func dig_power() -> float:
	var power := _items.power_of(Game.inventory.selected_item())
	return float(power) if power > 0 else HAND_POWER


## Which crafting stations are close enough to use.
func stations_in_reach() -> Dictionary:
	var out := {}
	if world == null or world.player == null:
		return out
	var here: Vector2i = world.player_tile()
	for dy in range(-STATION_REACH, STATION_REACH + 1):
		for dx in range(-STATION_REACH, STATION_REACH + 1):
			var id := store.get_fg(here.x + dx, here.y + dy)
			if id == 0:
				continue
			var station: String = _items.station_for_tile.get(_db.name_of.get(id, ""), "")
			if not station.is_empty():
				out[station] = true
	return out


## The one tile within arm's reach, chosen by which directions are held.
##
## All eight, not three: holding down and right aims at the corner, which is
## what you want when cutting a staircase down into the rock rather than a
## shaft. With nothing held it aims at whatever you are facing.
func target_tile() -> Vector2i:
	if world == null or world.player == null or not is_instance_valid(world.player):
		return Vector2i(-9999, -9999)

	var step := Vector2i.ZERO
	if Input.is_action_pressed("move_left"):
		step.x -= 1
	if Input.is_action_pressed("move_right"):
		step.x += 1
	if Input.is_action_pressed("move_up"):
		step.y -= 1
	if Input.is_action_pressed("move_down"):
		step.y += 1
	if step == Vector2i.ZERO:
		step.x = world.player.facing()

	return world.player_tile() + step


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_open_nearby_chest()
		return
	if event.is_action_pressed("cycle_place"):
		Game.inventory.select((Game.inventory.selected + 1) % Inventory.HOTBAR)
		return
	for i in Inventory.HOTBAR:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			Game.inventory.select(i)
			return


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


## Chests are opened by standing next to one and pressing interact, rather
## than by breaking them: a chest you have to mine is a chest you can lose.
func _open_nearby_chest() -> void:
	if world == null or world.player == null:
		return
	var here: Vector2i = world.player_tile()
	var chest := _db.id("chest")
	var shut := _db.id("door_shut")
	var open := _db.id("door_open")

	# A door first, since you are more likely to be stood in one.
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var at := here + Vector2i(dx, dy)
			var what := store.get_fg(at.x, at.y)
			if what != shut and what != open:
				continue
			_set_tile(at.x, at.y, open if what == shut else shut)
			return

	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var at := here + Vector2i(dx, dy)
			if store.get_fg(at.x, at.y) != chest:
				continue
			var loot: Array = store.gen.chest_loot(at.x, at.y)
			for entry: Array in loot:
				Game.collect(str(entry[0]), int(entry[1]))
			_set_tile(at.x, at.y, _db.id("chest_open"))
			Goals.note_chest()
			chest_opened.emit(at.x, at.y, loot)
			return


func _dig(delta: float) -> void:
	var id := store.get_fg(_target.x, _target.y)
	if id == 0:
		_progress = 0.0
		return
	var hardness := _db.hardness[id]
	if hardness <= 0:
		return
	_progress += dig_power() * delta
	if _progress < float(hardness):
		return

	_progress = 0.0

	# A tree comes down whole. Chopping one trunk tile at a time is Minecraft;
	# in Terraria the trunk falls and you get the lot.
	if id == _db.id("tree_trunk"):
		_fell_tree(_target.x, _target.y)
		return

	# A life crystal is not a material, it is a heart.
	if id == _db.id("life_crystal"):
		_set_tile(_target.x, _target.y, 0)
		if Game.gain_heart():
			Goals.note_heart()
			heart_gained.emit(_target.x, _target.y)
		return

	var drop := _db.drop_of(id)
	_set_tile(_target.x, _target.y, 0)
	if drop.is_empty():
		return
	# Breaking always succeeds. What comes out lies on the ground until it is
	# picked up, so a full bag costs you nothing.
	tile_broken.emit(_target.x, _target.y, drop)


## Bring the whole tree down and hand over its wood.
func _fell_tree(x: int, y: int) -> void:
	var trunk := _db.id("tree_trunk")
	var leaves := _db.id("leaves")

	var lowest := y
	while store.get_fg(x, lowest + 1) == trunk:
		lowest += 1
	var highest := y
	while store.get_fg(x, highest - 1) == trunk:
		highest -= 1

	var trunks := 0
	for ty in range(highest, lowest + 1):
		_set_tile(x, ty, 0)
		trunks += 1

	# The canopy goes with it. Leaves themselves are worth nothing; the wood
	# is counted from the trunk.
	for dy in range(-4, 3):
		for dx in range(-3, 4):
			var lx := x + dx
			var ly := highest + dy
			if store.get_fg(lx, ly) == leaves:
				_set_tile(lx, ly, 0)

	var wood: int = maxi(4, trunks * 2)
	tree_felled.emit(x, lowest, wood)


func _place() -> void:
	if store.get_fg(_target.x, _target.y) != 0:
		return
	var held := Game.inventory.selected_item()
	# The place key doubles as "use what I am holding": armour goes on rather
	# than going down.
	if _items.kind(held) == "armour":
		Game.inventory.equip(held)
		return
	var tile_name := _items.tile_of(held)
	if tile_name.is_empty():
		return   # nothing selected, or what is selected is not a block
	var id := _db.id(tile_name)
	if id == 0:
		return

	# Walls go behind everything, which is what makes them a wall. They can be
	# put up where there is already something standing.
	if _db.wall[id] == 1:
		if store.get_bg(_target.x, _target.y) != 0:
			return
		if not Game.inventory.remove(held, 1):
			return
		store.set_bg(_target.x, _target.y, id)
		renderer.update_tile(_target.x, _target.y)
		tile_changed.emit(_target.x, _target.y)
		tile_placed.emit(_target.x, _target.y, tile_name)
		return
	if not _has_support(_target.x, _target.y):
		return
	if _db.is_solid(id) and _overlaps_player(_target) and not _pillaring():
		return
	if not Game.inventory.remove(held, 1):
		return   # not actually carrying one
	_set_tile(_target.x, _target.y, id)
	tile_placed.emit(_target.x, _target.y, tile_name)


func _has_support(x: int, y: int) -> bool:
	if store.get_bg(x, y) != 0:
		return true
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if store.get_fg(x + d.x, y + d.y) != 0:
			return true
	return false


## Putting a block under your own feet while off the ground, and landing on
## it. Standing still and sealing yourself inside one is still refused; this is
## only ever the tile you are about to fall onto.
func _pillaring() -> bool:
	if world.player.is_on_floor():
		return false
	var feet: float = world.player.global_position.y + 8.0
	return float(_target.y * TILE) >= feet - 2.0


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
