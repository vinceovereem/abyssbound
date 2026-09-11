extends Node2D
## The generated world. Root of scenes/world.tscn.
##
## Built in code rather than as a scene tree on purpose: CLAUDE.md warns that
## hand-editing .tscn node structure is how nodes get silently dropped, and
## everything here is created the same way every run anyway.

const TILE := 16
const RADIUS := 2

const PlayerScene := preload("res://scenes/actors/player.tscn")

var store: ChunkStore
var renderer: ChunkRenderer
var sky: WorldSky
var mining: Mining
var lighting: Lighting
var combat: Combat
var spawner: Spawner
var entities: Node2D
var debug_overlay: CanvasLayer
var inventory_ui: CanvasLayer
var player: CharacterBody2D

var _camera: Camera2D
var _last_centre := Vector2i(-9999, -9999)
var _web_tick := 0
var _last_sky_light := -1
var _respawning := false
var _spawn_x := 0

## Set before the node enters the tree to override what BootConfig would give.
## Playtest scripts use these to jump straight to what they are inspecting.
var seed_override := -1
var spawn_override_x := -1


func _ready() -> void:
	var world_seed := seed_override if seed_override >= 0 else BootConfig.world_seed()
	# Printed so a playtest that trips over something can be replayed exactly.
	print("[world] seed=%d" % world_seed)

	store = ChunkStore.new(world_seed)

	sky = WorldSky.new()
	sky.name = "Sky"
	add_child(sky)

	renderer = ChunkRenderer.new()
	renderer.name = "Renderer"
	add_child(renderer)
	renderer.setup(store)

	entities = Node2D.new()
	entities.name = "Entities"
	add_child(entities)

	_spawn_player()

	mining = Mining.new()
	mining.name = "Mining"
	add_child(mining)
	mining.setup(self, store, renderer)

	combat = Combat.new()
	combat.name = "Combat"
	add_child(combat)
	combat.setup(self)

	lighting = Lighting.new()
	lighting.name = "Lighting"
	add_child(lighting)
	lighting.setup(store)
	mining.tile_changed.connect(func(_x: int, _y: int) -> void: lighting.mark_dirty())
	mining.tile_broken.connect(_on_tile_broken)
	mining.tile_placed.connect(func(_x: int, _y: int, n: String) -> void: Goals.note_placed(n))
	lighting.update_now(player_tile())

	Game.player_died.connect(_on_player_died)
	Game.player_hurt.connect(_on_player_hurt)

	spawner = Spawner.new()
	spawner.name = "Spawner"
	add_child(spawner)
	spawner.setup(self, store, lighting)

	inventory_ui = preload("res://scenes/ui/inventory_ui.tscn").instantiate()
	inventory_ui.world = self
	add_child(inventory_ui)

	debug_overlay = preload("res://scenes/ui/debug_overlay.tscn").instantiate()
	debug_overlay.world = self
	add_child(debug_overlay)

	sky.update_for_depth(player_tile().y, DayClock.daylight())
	lighting.sky_light = int(lerpf(28.0, float(Lighting.SKY), DayClock.daylight()))
	Game.zone_name = "Aerenfall"
	Ui.set_gameplay_visible(true)
	Ui.announce_zone(store.gen.biome_name(player_tile().x))


func _spawn_player() -> void:
	var wanted := spawn_override_x if spawn_override_x >= 0 else BootConfig.spawn_x()
	var x := clampi(wanted, 8, WorldGen.WIDTH - 8)
	_spawn_x = x
	var h := store.gen.surface_height(x)

	# Draw the ground before dropping the player onto it, or the first frames
	# are spent falling through a world that has not been built yet.
	renderer.refresh(store.chunk_coord(x, h), RADIUS)

	player = PlayerScene.instantiate()
	player.position = Vector2(x * TILE + TILE * 0.5, (h - 3) * TILE)
	add_child(player)

	_camera = player.get_node_or_null("Camera") as Camera2D
	if _camera:
		# Pulled in from the full 640x360. At 1:1 the character was a speck in
		# forty tiles of world; this shows about twenty seven, which is roughly
		# what the concept art frames.
		_camera.zoom = Vector2(1.5, 1.5)
		_camera.limit_left = 0
		_camera.limit_top = 0
		_camera.limit_right = WorldGen.WIDTH * TILE
		_camera.limit_bottom = WorldGen.HEIGHT * TILE


func player_tile() -> Vector2i:
	if not player or not is_instance_valid(player):
		return Vector2i.ZERO
	return Vector2i(
		int(floor(player.global_position.x / TILE)),
		int(floor(player.global_position.y / TILE)))


func _process(_delta: float) -> void:
	if not player or not is_instance_valid(player):
		return
	var tile := player_tile()
	var daylight := DayClock.daylight()
	sky.update_for_depth(tile.y, daylight)

	# Night is dark because the sun stops giving light, not because a filter is
	# drawn over the top. Only nudge the lighting when it has actually moved,
	# or every frame becomes a recompute.
	var sun := int(lerpf(28.0, float(Lighting.SKY), daylight))
	if absi(sun - _last_sky_light) >= 6:
		_last_sky_light = sun
		lighting.sky_light = sun
		lighting.mark_dirty()

	lighting.update(tile)
	Goals.note_depth(tile.y - store.gen.surface_height(tile.x), store.gen.abyss_layer(tile.y))
	_publish_web_stats(tile)
	var centre := store.chunk_coord(tile.x, tile.y)
	if centre != _last_centre:
		_last_centre = centre
		renderer.refresh(centre, RADIUS)


## Put the player somewhere specific and make sure the ground there exists.
## Used by playtests to inspect a place without walking to it.
func teleport(tile_x: int, tile_y: int) -> void:
	if not player or not is_instance_valid(player):
		return
	var centre := store.chunk_coord(tile_x, tile_y)
	renderer.refresh(centre, RADIUS)
	_last_centre = centre
	player.global_position = Vector2(tile_x * TILE + TILE * 0.5, tile_y * TILE)
	player.velocity = Vector2.ZERO


## In a browser, hand the page what the F3 overlay shows.
##
## A headless CI browser renders in software and its frame rate says nothing
## about real hardware, so this is not a performance gate. It is how an
## automated check confirms the build actually reached the point of running,
## and how a real browser can be asked for a real number.
func _publish_web_stats(tile: Vector2i) -> void:
	if not OS.has_feature("web"):
		return
	_web_tick += 1
	if _web_tick % 30 != 0:
		return
	JavaScriptBridge.eval("window.__abyss=%s;" % JSON.stringify({
		"ready": true,
		"fps": Engine.get_frames_per_second(),
		"seed": store.world_seed(),
		"tile": [tile.x, tile.y],
		"biome": store.gen.biome_name(tile.x),
		"light_ms": lighting.last_ms,
		"chunks": renderer.loaded_count(),
	}), true)


## Floating text in world space: what a block gave you, what a hit took off.
## Feedback belongs where the thing happened, not only in a corner of the HUD.
func float_text(at: Vector2, text: String, colour: Color, rise := 14.0) -> void:
	var label := Label.new()
	label.text = text
	# A 4 px outline on an 8 px font swallows the glyph and the text reads as a
	# grey blob, which is what it did at the zoomed in camera.
	label.add_theme_font_size_override("font_size", 12)
	# Tinting the whole node rather than overriding the font colour: the theme
	# override was not taking on a Label built in code, and modulate always does.
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 1)
	label.modulate = colour
	label.position = at - Vector2(12, 6)
	label.z_index = 30
	add_child(label)

	var tween := create_tween()
	tween.tween_property(label, "position:y", label.position.y - rise, 0.7)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.3)
	tween.tween_callback(label.queue_free)


func _on_tile_broken(x: int, y: int, drop: String) -> void:
	float_text(Vector2(x * TILE, y * TILE), "+1 %s" % TileDB.pretty(drop),
		Color(1, 0.96, 0.82))


func _on_player_hurt(amount: int) -> void:
	if player and is_instance_valid(player):
		float_text(player.global_position - Vector2(0, 10), "-%d" % amount,
			Color(1.0, 0.42, 0.42), 18.0)


## Dying puts you back where you started, in the same world.
##
## It used to reload the scene, which regenerated the world from a fresh seed
## and threw away everything that had been dug. In a game about digging that is
## not a death penalty, it is losing the save.
func _on_player_died() -> void:
	if _respawning:
		return
	_respawning = true

	await Ui.fade_out(0.4)

	Game.health = Game.MAX_HEALTH
	Game.health_changed.emit(Game.health, Game.MAX_HEALTH)
	Ui.hide_message()

	var x := clampi(_spawn_x, 8, WorldGen.WIDTH - 8)
	teleport(x, store.gen.surface_height(x) - 3)
	lighting.mark_dirty()
	lighting.update_now(player_tile())

	await Ui.fade_in(0.5)
	_respawning = false
