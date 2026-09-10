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

	# Let the world build and the player settle onto the ground.
	for i in 30:
		await get_tree().physics_frame

	if int(place["y"]) >= 0:
		world.teleport(int(place["x"]), int(place["y"]))
		for i in 20:
			await get_tree().physics_frame

	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_dir, place["name"]]
	img.save_png(path)
	print("  %s  %dx%d  biome=%s  tile=%s" % [
		place["name"], img.get_width(), img.get_height(),
		world.store.gen.biome_name(world.player_tile().x), world.player_tile()])

	world.queue_free()
	await get_tree().process_frame
