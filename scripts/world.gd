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
var player: CharacterBody2D

var _camera: Camera2D
var _last_centre := Vector2i(-9999, -9999)

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

	_spawn_player()

	sky.update_for_depth(player_tile().y)
	Game.zone_name = "Aerenfall"
	Ui.set_gameplay_visible(true)
	Ui.announce_zone(store.gen.biome_name(player_tile().x))


func _spawn_player() -> void:
	var wanted := spawn_override_x if spawn_override_x >= 0 else BootConfig.spawn_x()
	var x := clampi(wanted, 8, WorldGen.WIDTH - 8)
	var h := store.gen.surface_height(x)

	# Draw the ground before dropping the player onto it, or the first frames
	# are spent falling through a world that has not been built yet.
	renderer.refresh(store.chunk_coord(x, h), RADIUS)

	player = PlayerScene.instantiate()
	player.position = Vector2(x * TILE + TILE * 0.5, (h - 3) * TILE)
	add_child(player)

	_camera = player.get_node_or_null("Camera") as Camera2D
	if _camera:
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
	sky.update_for_depth(tile.y)
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
