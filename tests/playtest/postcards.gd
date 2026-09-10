extends Node
## Visual survey. Spawns the world at a list of places and saves a screenshot
## of each, so the generator can be judged by looking rather than by trusting
## the numbers a headless check prints.
##
##   godot --path . res://tests/playtest/postcards.tscn
##
## Writes to user://postcards/. Not headless: it needs a real renderer.

const WorldScene := preload("res://scenes/world.tscn")
const SEED := 20260910

## x, and an optional tile y to drop to. y of -1 means stand on the surface.
const PLACES := [
	{ "name": "01_ocean_west",  "x": 60,   "y": -1 },
	{ "name": "02_plains",      "x": 300,  "y": -1 },
	{ "name": "03_forest",      "x": 560,  "y": -1 },
	{ "name": "04_desert",      "x": 800,  "y": -1 },
	{ "name": "05_abyss_mouth", "x": 1000, "y": -1 },
	{ "name": "05b_waterline",  "x": 60,   "y": 132 },
	{ "name": "06_mountains",   "x": 1300, "y": -1 },
	{ "name": "07_underground", "x": 600,  "y": 200 },
	{ "name": "08_caverns",     "x": 600,  "y": 380 },
	{ "name": "09_abyss_deep",  "x": 1000, "y": 600 },
	{ "name": "10_torch",       "x": 640,  "y": 260, "torch": true },
	{ "name": "11_mining",      "x": 600,  "y": 200, "mining": true },
]

var _dir := "user://postcards"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(_dir)
	print("postcards -> %s" % ProjectSettings.globalize_path(_dir))

	for place: Dictionary in PLACES:
		await _shoot(place)

	print("done")
	get_tree().quit(0)


func _shoot(place: Dictionary) -> void:
	var world: Node2D = WorldScene.instantiate()
	world.seed_override = SEED
	world.spawn_override_x = int(place["x"])
	add_child(world)
	# Every postcard carries its own seed, position and frame time, so a shot
	# that shows something odd is a reproducible report rather than a picture.
	world.debug_overlay.visible = true

	# Let the world build and the player settle onto the ground.
	for i in 30:
		await get_tree().physics_frame

	if int(place["y"]) >= 0:
		world.teleport(int(place["x"]), int(place["y"]))
		for i in 20:
			await get_tree().physics_frame

	if bool(place.get("torch", false)):
		# Hollow out a small room and light it, which is the only way to see
		# whether a torch actually does anything.
		var t: Vector2i = world.player_tile()
		for dx in range(-6, 7):
			for dy in range(-4, 3):
				world.store.set_fg(t.x + dx, t.y + dy, 0)
		world.store.set_fg(t.x + 3, t.y, TileDB.get_db().id("torch"))
		world.renderer.refresh(world.store.chunk_coord(t.x, t.y), 2)
		world.lighting.mark_dirty()
		world.lighting.update_now(t)
		for i in 5:
			await get_tree().physics_frame

	if bool(place.get("mining", false)):
		# Drive the real HUD and the real pickup popup, so the screenshot shows
		# what a player sees rather than a mock up of it.
		var t: Vector2i = world.player_tile()
		for dx in range(-5, 6):
			for dy in range(-3, 3):
				world.store.set_fg(t.x + dx, t.y + dy, 0)
		world.renderer.refresh(world.store.chunk_coord(t.x, t.y), 2)
		world.lighting.mark_dirty()
		world.lighting.update_now(t)
		Game.collect("dirt", 14)
		Game.collect("stone", 9)
		Game.collect("copper_ore", 3)
		world.mining.tile_broken.emit(t.x + 1, t.y + 1, "stone")
		for i in 12:
			await get_tree().physics_frame

	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_dir, place["name"]]
	img.save_png(path)
	print("  %s  biome=%s  tile=%s  light=%.2fms" % [
		place["name"], world.store.gen.biome_name(world.player_tile().x),
		world.player_tile(), world.lighting.last_ms])

	world.queue_free()
	await get_tree().process_frame
