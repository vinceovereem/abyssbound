class_name ItemDrop
extends Node2D
## A thing lying on the ground waiting to be picked up.
##
## Built in code rather than as a scene, and moved by hand against the chunk
## store rather than by the physics engine. There can be a lot of these and
## none of them need to collide with anything except the ground.
##
## A full bag is not an error here: the drop simply stays where it is, which is
## what lets mining always succeed.

const TILE := 16
const GRAVITY := 620.0
const MAX_FALL := 240.0
const FRICTION := 420.0
## How long it stays put before it will follow you, so a freshly dug block pops
## out and is visible rather than vanishing into you instantly.
const SETTLE := 0.28
const PULL_TILES := 3.5
const PULL_SPEED := 300.0
const TAKE_DISTANCE := 7.0
const FORGET_TILES := 90.0

var item_id := ""
var amount := 1

var _store: ChunkStore
var _velocity := Vector2.ZERO
var _age := 0.0
var _bob := 0.0
var _sprite: Sprite2D


func setup(id: String, count: int, store: ChunkStore, pop: Vector2) -> void:
	item_id = id
	amount = count
	_store = store
	_velocity = pop
	z_index = 4

	_sprite = Sprite2D.new()
	_sprite.texture = ItemIcons.texture_for(id)
	# Half size, so it reads as a loose item rather than a placed tile.
	_sprite.scale = Vector2(0.5, 0.5)
	add_child(_sprite)


func _physics_process(delta: float) -> void:
	_age += delta
	_bob += delta * 4.0

	var player := get_tree().get_first_node_in_group("player")
	var has_player: bool = player != null and is_instance_valid(player)

	if has_player:
		var gap: float = global_position.distance_to(player.global_position)
		if gap > FORGET_TILES * TILE:
			queue_free()
			return
		if _age > SETTLE and gap < PULL_TILES * TILE:
			# Close enough: come to the player, ignoring the ground.
			var toward: Vector2 = (player.global_position - global_position).normalized()
			_velocity = _velocity.lerp(toward * PULL_SPEED, 0.25)
			global_position += _velocity * delta
			if gap < TAKE_DISTANCE:
				_take()
			return

	_fall(delta)
	_sprite.position.y = sin(_bob) * 1.5


## Gravity and a floor, done against the tile data rather than with a body.
func _fall(delta: float) -> void:
	_velocity.y = minf(_velocity.y + GRAVITY * delta, MAX_FALL)
	_velocity.x = move_toward(_velocity.x, 0.0, FRICTION * delta)

	var next := global_position + _velocity * delta
	if _store != null and _velocity.y > 0.0:
		var tile_x := int(floor(next.x / TILE))
		var tile_y := int(floor((next.y + 3.0) / TILE))
		if _store.is_solid(tile_x, tile_y):
			next.y = tile_y * TILE - 3.0
			_velocity.y = 0.0
	global_position = next


func _take() -> void:
	var left := Game.collect(item_id, amount)
	if left >= amount:
		return   # bag is full; keep lying here
	amount = left
	if amount <= 0:
		queue_free()
