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


func _process(delta: float) -> void:
	if not visible or world == null or world.player == null:
		return
	# Smoothed, because a number that flickers every frame cannot be read off
	# a screenshot.
	_fps = lerpf(_fps, 1.0 / maxf(delta, 0.0001), 0.1)

	var tile: Vector2i = world.player_tile()
	var chunk: Vector2i = world.store.chunk_coord(tile.x, tile.y)
	var layer: int = world.store.gen.abyss_layer(tile.y)

	_label.text = "\n".join([
		"seed     %d" % world.store.world_seed(),
		"fps      %.0f   light %.1f ms" % [_fps, world.lighting.last_ms],
		"tile     %d, %d" % [tile.x, tile.y],
		"chunk    %d, %d   loaded %d" % [chunk.x, chunk.y, world.renderer.loaded_count()],
		"biome    %s" % world.store.gen.biome_name(tile.x),
		"abyss    %s" % ("layer %d" % layer if layer > 0 else "above"),
		"light    %d" % world.lighting.light_at(tile.x, tile.y),
		"place    %s" % world.mining.selected_tile_name(),
		"clock    %s   creature %s" % [FIELDS_HIDDEN_UNTIL_LATER, FIELDS_HIDDEN_UNTIL_LATER],
	])
