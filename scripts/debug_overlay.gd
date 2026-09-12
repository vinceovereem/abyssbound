extends CanvasLayer
## F3. What the screenshots need in order to be judgeable.
##
## A screenshot of a cave is not evidence of anything on its own. The same
## screenshot with the seed, the position, the biome and the frame time on it
## is a bug report.

const FIELDS_HIDDEN_UNTIL_LATER := "-"

var world: Node2D

var _label: Label
var _panel: ColorRect
var _fps := 0.0


func _ready() -> void:
	layer = 90
	visible = false

	_panel = ColorRect.new()
	_panel.color = Color(0, 0, 0, 0.55)
	_panel.position = Vector2(6, 24)
	_panel.size = Vector2(232, 132)
	add_child(_panel)

	_label = Label.new()
	_label.position = Vector2(12, 27)
	_label.add_theme_font_size_override("font_size", 8)
	_label.add_theme_color_override("font_color", Color(0.85, 0.93, 1.0))
	add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_overlay"):
		visible = not visible


## What is closest, how far, and whether it has noticed you. The single most
## useful thing to have on a screenshot of something behaving oddly.
func _nearest_creature() -> String:
	var here: Vector2 = world.player.global_position
	var best: Node2D = null
	var best_distance := INF
	for group in ["enemy", "critter"]:
		for node in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(node):
				continue
			var d: float = node.global_position.distance_to(here)
			if d < best_distance:
				best_distance = d
				best = node
	if best == null:
		return "none"
	# Named from its group, not its node name: Godot gives an instanced scene
	# an auto name like @CharacterBody2D@15 the moment two of them collide.
	var kind := "creature"
	var state := "wandering"
	if best.is_in_group("critter"):
		kind = "critter"
		state = "tame" if best.get("tamed") else "shy"
	elif best.is_in_group("enemy"):
		kind = "crawler"
		state = "hunting" if best.get("hunts") else "patrolling"
	return "%s %s %.0f tiles" % [kind, state, best_distance / 16.0]


func _process(delta: float) -> void:
	if not visible or world == null or world.player == null:
		return
	# Smoothed, because a number that flickers every frame cannot be read off
	# a screenshot.
	_fps = lerpf(_fps, 1.0 / maxf(delta, 0.0001), 0.1)

	var tile: Vector2i = world.player_tile()
	var chunk: Vector2i = world.store.chunk_coord(tile.x, tile.y)
	var surface: int = world.store.gen.surface_height(tile.x)

	_label.text = "\n".join([
		"seed     %d" % world.store.world_seed(),
		"fps      %.0f   light %.1f ms" % [_fps, world.lighting.last_ms],
		"tile     %d, %d" % [tile.x, tile.y],
		"chunk    %d, %d   loaded %d" % [chunk.x, chunk.y, world.renderer.loaded_count()],
		"biome    %s" % world.store.gen.biome_name(tile.x),
		"depth    %s   %d below" % [world.store.gen.band_name(tile.y, surface),
			maxi(0, tile.y - surface)],
		"light    %d" % world.lighting.light_at(tile.x, tile.y),
		"place    %s" % world.mining.selected_tile_name(),
		"clock    %s  day %d  %s" % [DayClock.clock_text(), DayClock.day,
			"night" if DayClock.is_night() else "day"],
		"sun      %d   alive %d" % [world.lighting.sky_light, world.spawner.alive()],
		"nearest  %s" % _nearest_creature(),
	])
