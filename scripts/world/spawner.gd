class_name Spawner
extends Node2D
## Puts things in the world, and takes them away again.
##
## The rules are the interesting part, because they are what make shelter mean
## something rather than being a suggestion:
##
##   - hostiles only appear in the dark, so a lit room is safe
##   - nothing appears where the player can watch it appear
##   - nothing appears inside rock, or floating in the air
##   - dawn clears the night's hostiles off the surface
##
## Milestone 4 replaces the "what" with real species from data/creatures/. The
## "where and when" here should survive that.

const TILE := 16
const MAX_ALIVE := 14
const INTERVAL := 1.4
## Far enough away to be off screen at 640x360, near enough to walk into.
const MIN_TILES := 24
const MAX_TILES := 46
const FORGET_TILES := 84
## Hostiles will not appear on a tile lit at least this much. A torch is worth
## about 220 at its own tile, so one torch clears a good pocket around it.
const DARK_ENOUGH := 70

const CrawlerScene := preload("res://scenes/actors/crawler.tscn")
const CritterScene := preload("res://scenes/actors/critter.tscn")

var world: Node2D
var store: ChunkStore
var lighting: Lighting

var _timer := 0.0
var _rng := RandomNumberGenerator.new()


func setup(world_node: Node2D, chunk_store: ChunkStore, light: Lighting) -> void:
	world = world_node
	store = chunk_store
	lighting = light
	_rng.seed = chunk_store.world_seed()
	DayClock.day_broke.connect(_on_day_broke)


func alive() -> int:
	return get_tree().get_nodes_in_group("enemy").size() \
		+ get_tree().get_nodes_in_group("critter").size()


func _process(delta: float) -> void:
	if world == null or world.player == null or not is_instance_valid(world.player):
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = INTERVAL
	_forget_distant()
	if alive() < MAX_ALIVE:
		_try_spawn()


func _forget_distant() -> void:
	var here: Vector2 = world.player.global_position
	for group in ["enemy", "critter"]:
		for node in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(node):
				continue
			if node.global_position.distance_to(here) > FORGET_TILES * TILE:
				node.queue_free()


## Dawn burns off whatever came out in the night, so morning is a real relief
## rather than yesterday's problems still standing there.
func _on_day_broke(_day: int) -> void:
	for node in get_tree().get_nodes_in_group("hostile"):
		if not is_instance_valid(node):
			continue
		var tile_y := int(node.global_position.y / TILE)
		if tile_y <= store.gen.surface_height(int(node.global_position.x / TILE)) + 6:
			node.queue_free()


func _try_spawn() -> void:
	var here: Vector2i = world.player_tile()
	var offset := _rng.randi_range(MIN_TILES, MAX_TILES) * (1 if _rng.randf() < 0.5 else -1)
	var x := here.x + offset
	if x < 4 or x >= WorldGen.WIDTH - 4:
		return

	var surface := store.gen.surface_height(x)
	var underground := here.y > surface + 10

	var y := _find_footing(x, here.y) if underground else _surface_footing(x, surface)
	if y < 0:
		return

	var hostile := underground or DayClock.is_night()
	if hostile and lighting.light_at(x, y) >= DARK_ENOUGH:
		return  # somebody lit this place; nothing comes here

	var creature: Node2D
	if hostile:
		creature = CrawlerScene.instantiate()
		creature.hunts = true
	else:
		creature = CritterScene.instantiate()
	creature.position = Vector2(x * TILE + TILE * 0.5, y * TILE + TILE * 0.5)
	world.entities.add_child(creature)


## Standing room on the surface: solid underfoot, two clear tiles of headroom.
func _surface_footing(x: int, surface: int) -> int:
	if not store.is_solid(x, surface):
		return -1
	if store.is_solid(x, surface - 1) or store.is_solid(x, surface - 2):
		return -1
	return surface - 1


## The same, but hunting for a pocket in the caves near the player's depth.
func _find_footing(x: int, near_y: int) -> int:
	for dy in range(-12, 13):
		var y := near_y + dy
		if y < 2 or y >= WorldGen.HEIGHT - 2:
			continue
		if store.is_solid(x, y + 1) and not store.is_solid(x, y) and not store.is_solid(x, y - 1):
			return y
	return -1
