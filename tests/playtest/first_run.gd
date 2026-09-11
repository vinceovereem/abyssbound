extends Node
## A scripted play of the first minute: spawn, walk, dig, place, save, reload.
##
##   godot --path . res://tests/playtest/first_run.tscn
##
## This is the "play it" half of the build loop. It drives the same code a
## player does, screenshots each beat into user://playtest/, and prints a
## verdict so it can also run as a check.

const WorldScene := preload("res://scenes/world.tscn")
const SEED := 20260910
const SPAWN_X := 940

var _dir := "user://playtest"
var _passed := 0
var _failed := 0
var _fps_samples: Array[float] = []
var world: Node2D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(_dir)
	print("Abyssbound first run")
	print("--------------------")

	world = WorldScene.instantiate()
	world.seed_override = SEED
	world.spawn_override_x = SPAWN_X
	add_child(world)
	world.debug_overlay.visible = true
	await _settle(30)

	await _spawn()
	await _walk()
	await _dig()
	await _place_torch()
	await _save_and_reload()

	var avg := 0.0
	for f in _fps_samples:
		avg += f
	avg /= maxf(1.0, float(_fps_samples.size()))
	print("--------------------")
	print("average fps over the run: %.0f" % avg)
	print("%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _ok(label: String, condition: bool, detail := "") -> void:
	if condition:
		_passed += 1
		print("  PASS  %s%s" % [label, (" (%s)" % detail) if detail else ""])
	else:
		_failed += 1
		print("  FAIL  %s%s" % [label, (" (%s)" % detail) if detail else ""])


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame
		_fps_samples.append(Engine.get_frames_per_second())


## Headless has no renderer, so there is nothing to capture. Run this one
## headless for the assertions, which are fast and do not depend on the window
## having focus, and use postcards.tscn for pictures.
func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_dir, name])


func _spawn() -> void:
	print("\nspawn")
	_ok("the player is standing on ground, not falling", world.player.is_on_floor(),
		"tile %s" % world.player_tile())
	_ok("spawn is in daylight",
		world.lighting.light_at(world.player_tile().x, world.player_tile().y) > 200)
	_ok("the Abyss is within walking distance of spawn",
		absi(WorldGen.ABYSS_CENTER_X - SPAWN_X) < 120,
		"%d tiles east" % (WorldGen.ABYSS_CENTER_X - SPAWN_X))
	await _shot("01_spawn")


func _walk() -> void:
	print("\nwalking east toward the Abyss")
	var start: Vector2i = world.player_tile()
	# Re-pressed every frame on purpose. Godot releases every held action when
	# the window loses focus, and a window launched from a shell often never
	# has focus, so a single action_press quietly does nothing and the player
	# stands still while the test reports the ground is impassable.
	Input.action_press("move_right")
	# Jump when we stop making progress, which is what a player does at a
	# ledge. Natural terrain has one tile steps all over it and this controller
	# does not step up on its own.
	var jumps := 0
	var last_x: float = world.player.global_position.x
	for i in 240:
		await get_tree().physics_frame
		Input.action_press("move_right")
		_fps_samples.append(Engine.get_frames_per_second())
		if i % 20 == 19:
			var progress: float = world.player.global_position.x - last_x
			last_x = world.player.global_position.x
			if progress < 6.0 and world.player.is_on_floor():
				Input.action_press("jump")
				await get_tree().physics_frame
				await get_tree().physics_frame
				Input.action_release("jump")
				jumps += 1
	Input.action_release("move_right")
	await _settle(20)
	var moved: int = world.player_tile().x - start.x
	_ok("walking east crosses the ground", moved > 8,
		"%d tiles, %d jumps needed" % [moved, jumps])
	_ok("the player did not fall out of the world",
		world.player_tile().y < WorldGen.HEIGHT - 40, "y=%d" % world.player_tile().y)
	_ok("chunks streamed in as we went", world.renderer.loaded_count() > 0,
		"%d loaded" % world.renderer.loaded_count())
	await _shot("02_walked_east")


func _dig() -> void:
	print("\ndigging down")
	var t: Vector2i = world.player_tile()
	var target := t + Vector2i(0, 1)
	var before: int = world.store.get_fg(target.x, target.y)
	_ok("there is ground under our feet", before != 0,
		TileDB.get_db().name_of.get(before, "?"))
	var had: int = Game.amount_of(TileDB.get_db().drop_of(before))

	# Hold down and dig: the block you are standing on.
	var broke := false
	for i in 300:
		Input.action_press("move_down")
		Input.action_press("mine")
		await get_tree().physics_frame
		_fps_samples.append(Engine.get_frames_per_second())
		if world.store.get_fg(target.x, target.y) == 0:
			broke = true
			break
	Input.action_release("mine")
	Input.action_release("move_down")

	_ok("holding down and the dig key breaks the block underfoot", broke,
		TileDB.get_db().name_of.get(before, "?"))
	if broke:
		var drop := TileDB.get_db().drop_of(before)
		_ok("breaking it gives you the material", Game.amount_of(drop) > had,
			"%s %d -> %d" % [drop, had, Game.amount_of(drop)])
	await _settle(20)
	await _shot("03_dug")


func _place_torch() -> void:
	print("\nplacing a torch")
	var db := TileDB.get_db()
	# Torches are made from wood now, not chosen from a fixed list, so make one
	# the way a player would: gather, then craft it by hand.
	Game.inventory.add("wood", 4)
	var book := RecipeBook.get_book()
	var torch_recipe := -1
	for i in book.recipes.size():
		if book.recipes[i]["out"] == "torch":
			torch_recipe = i
	_ok("a torch can be made from wood by hand",
		book.make(torch_recipe, Game.inventory, {}))
	_ok("the torch ends up in the bag", Game.inventory.count_of("torch") >= 1,
		"%d" % Game.inventory.count_of("torch"))

	# Put it in the selected hotbar slot.
	for i in Inventory.HOTBAR:
		if Game.inventory.ids[i] == "torch":
			Game.inventory.select(i)
	_ok("the torch can be selected", world.mining.selected_tile_name() == "torch")

	# Dig a nook in the wall beside us and put the torch in that. A torch needs
	# something to hang on: the tile over an open hole has nothing either side
	# of it and is refused, which is the rule working rather than a bug.
	var here: Vector2i = world.player_tile()
	var facing: int = world.player.facing()
	var spot := here + Vector2i(facing, 0)
	for i in 300:
		Input.action_press("mine")
		await get_tree().physics_frame
		if world.store.get_fg(spot.x, spot.y) == 0:
			break
	Input.action_release("mine")
	_ok("digging sideways opens a nook", world.store.get_fg(spot.x, spot.y) == 0)

	var before_light: int = world.lighting.light_at(spot.x, spot.y)
	for i in 12:
		Input.action_press("place")
		await get_tree().physics_frame
	Input.action_release("place")
	await _settle(10)

	var placed: bool = world.store.get_fg(spot.x, spot.y) == db.id("torch")
	_ok("the place key puts the torch in the nook", placed,
		db.name_of.get(world.store.get_fg(spot.x, spot.y), "?"))
	world.lighting.mark_dirty()
	world.lighting.update_now(world.player_tile())
	if placed:
		_ok("the torch makes the place brighter",
			world.lighting.light_at(spot.x, spot.y) >= before_light,
			"%d -> %d" % [before_light, world.lighting.light_at(spot.x, spot.y)])
	await _shot("04_torch_placed")


func _save_and_reload() -> void:
	print("\nsave and come back")
	var t: Vector2i = world.player_tile()
	var dug := Vector2i(t.x, t.y + 2)
	while world.store.get_fg(dug.x, dug.y) != 0 and dug.y < t.y + 10:
		dug.y += 1
	world.mining._set_tile(dug.x, dug.y, 0)

	_ok("the world saves", WorldSave.save_world(world.store, world.player.global_position))
	var loaded := WorldSave.load_world()
	_ok("the world loads", not loaded.is_empty())
	if not loaded.is_empty():
		var reloaded: ChunkStore = loaded["store"]
		_ok("the hole we dug is still there after coming back",
			reloaded.get_fg(dug.x, dug.y) == 0)
	WorldSave.clear()
