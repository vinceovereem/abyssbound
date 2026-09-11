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

	if BootConfig.has("give"):
		Game.inventory.add("wood", 34)
		Game.inventory.add("stone", 61)
		Game.inventory.add("copper_ore", 9)
		Game.inventory.add("torch", 12)
		Game.inventory.add("wood_pick", 1)
		Game.inventory.add("workbench", 1)
		# Stand a workbench next to us so the station recipes show up.
		var t: Vector2i = world.player_tile()
		world.store.set_fg(t.x + 2, t.y, TileDB.get_db().id("workbench"))
		world.renderer.update_tile(t.x + 2, t.y)
		for i in 4:
			await get_tree().physics_frame

	if BootConfig.has("drops"):
		var t: Vector2i = world.player_tile()
		for spec in [[-3, "stone"], [-1, "wood"], [2, "copper_ore"], [4, "hide"], [6, "iron_bar"]]:
			world.spawn_drop(Vector2((t.x + int(spec[0])) * 16 + 8, (t.y - 2) * 16),
				str(spec[1]), 1)
		for i in 45:
			await get_tree().physics_frame

	if BootConfig.has("bag"):
		for piece in ["iron_helm", "copper_mail", "iron_greaves"]:
			Game.inventory.add(piece, 1)
			Game.inventory.equip(piece)
		Game.inventory.add("copper_helm", 1)
		world.inventory_ui._bag.visible = true
		world.inventory_ui._refresh()
		for i in 4:
			await get_tree().physics_frame

	if BootConfig.has("craft"):
		world.inventory_ui._craft.visible = true
		world.inventory_ui._refresh()
		for i in 4:
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
