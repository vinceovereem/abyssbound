extends Node
## One world, four times of day. Reuses the same world rather than building a
## new one per shot, which is the difference between seconds and minutes.
##
##   godot --path . res://tests/playtest/day_night.tscn

const WorldScene := preload("res://scenes/world.tscn")
const SEED := 20260910
const SPAWN_X := 560

const MOMENTS := [
	{ "name": "20_dawn",  "time": 0.225 },
	{ "name": "21_noon",  "time": 0.50 },
	{ "name": "22_dusk",  "time": 0.775 },
	{ "name": "23_night", "time": 0.92 },
]

var _dir := "user://daynight"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(_dir)
	DayClock.paused = true
	# macOS throttles a window that is not in front, which turns a twenty
	# second screenshot run into a several minute one.
	DisplayServer.window_move_to_foreground()

	var world: Node2D = WorldScene.instantiate()
	world.seed_override = SEED
	world.spawn_override_x = SPAWN_X
	add_child(world)
	world.debug_overlay.visible = true
	for i in 25:
		await get_tree().physics_frame

	for moment: Dictionary in MOMENTS:
		DayClock.set_time(float(moment["time"]))
		# Let the sun value settle and the light finish its four step pass.
		for i in 12:
			await get_tree().physics_frame
		world.lighting.mark_dirty()
		world.lighting.update_now(world.player_tile())

		# Populate it, so the shot shows an inhabited world rather than an
		# empty one that happens to be the right colour.
		for i in 8:
			world.spawner._try_spawn()
		# Spawning happens off screen on purpose, so give the hunters time to
		# walk in. Otherwise the shot shows an empty world that is merely the
		# right colour.
		for i in 420:
			await get_tree().physics_frame

		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_dir, moment["name"]])
		print("  %s  clock=%s  sun=%d  alive=%d" % [
			moment["name"], DayClock.clock_text(), world.lighting.sky_light,
			world.spawner.alive()])

	# One more: a hostile put close and allowed to arrive, so the shot shows the
	# thing that has been taking the hearts off rather than only the aftermath.
	DayClock.set_time(0.92)
	world.lighting.sky_light = 28
	world.lighting.mark_dirty()
	world.lighting.update_now(world.player_tile())
	var health_before: int = Game.health

	var hunter: CharacterBody2D = load("res://scenes/actors/crawler.tscn").instantiate()
	hunter.hunts = true
	var here: Vector2i = world.player_tile()
	var hx: int = here.x + 9
	hunter.position = Vector2(hx * 16 + 8, (world.store.gen.surface_height(hx) - 2) * 16)
	world.entities.add_child(hunter)

	for i in 600:
		await get_tree().physics_frame
		if is_instance_valid(hunter) \
				and hunter.global_position.distance_to(world.player.global_position) < 70.0:
			break
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/24_hunted.png" % _dir)
	var gap := 999.0
	if is_instance_valid(hunter):
		gap = hunter.global_position.distance_to(world.player.global_position) / 16.0
	print("  24_hunted  hunter %.1f tiles away  health %d -> %d" % [
		gap, health_before, Game.health])

	print("done -> %s" % ProjectSettings.globalize_path(_dir))
	get_tree().quit(0)
