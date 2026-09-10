extends Node
## One screenshot, fast. For checking a change by eye without waiting for a
## whole survey.
##
##   godot --path . --always-on-top res://tests/playtest/look.tscn -- --spawn-x=560 --time=0.5
##
## Writes user://look/look.png

const WorldScene := preload("res://scenes/world.tscn")


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://look")
	DisplayServer.window_move_to_foreground()

	DayClock.paused = true
	DayClock.set_time(float(BootConfig.get_int("time-pct", 50)) / 100.0)

	var world: Node2D = WorldScene.instantiate()
	world.seed_override = BootConfig.get_int("seed", 20260910)
	world.spawn_override_x = BootConfig.get_int("spawn-x", 560)
	add_child(world)
	world.debug_overlay.visible = BootConfig.has("overlay")
	for i in 40:
		await get_tree().physics_frame

	if BootConfig.has("dig"):
		# Cut a room so the player is not buried behind terrain in the shot.
		var t: Vector2i = world.player_tile()
		for dx in range(-6, 7):
			for dy in range(-4, 3):
				world.store.set_fg(t.x + dx, t.y + dy, 0)
		world.renderer.refresh(world.store.chunk_coord(t.x, t.y), 2)
		world.lighting.mark_dirty()
		world.lighting.update_now(t)
		for i in 10:
			await get_tree().physics_frame

	if BootConfig.has("creatures"):
		# Put them where the camera can see them, which the spawner
		# deliberately never does.
		var t: Vector2i = world.player_tile()
		Game.collect("wood", 4)
		Game.collect("stone", 6)
		for spec in [[1, "crawler"], [-7, "crawler"], [9, "critter"]]:
			var path := "res://scenes/actors/%s.tscn" % spec[1]
			var node: Node2D = load(path).instantiate()
			var cx: int = t.x + int(spec[0])
			node.position = Vector2(cx * 16 + 8, (world.store.gen.surface_height(cx) - 2) * 16)
			if node.has_method("hurt"):
				node.speed = 0.0
			world.entities.add_child(node)
		for i in 40:
			await get_tree().physics_frame
		# Swing at the one standing next to us, so the shot shows the hit.
		world.combat._swing()
		for i in 4:
			await get_tree().physics_frame

	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://look/look.png")
	print("look -> %s  tile=%s" % [
		ProjectSettings.globalize_path("user://look/look.png"), world.player_tile()])
	get_tree().quit(0)
