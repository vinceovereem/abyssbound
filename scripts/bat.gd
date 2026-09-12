class_name Bat
extends CharacterBody2D
## An abyss bat. Everything else in the world walks; this does not.
##
## Built entirely in code rather than as a scene, because hand-writing a .tscn
## node tree is how nodes get silently dropped, and this one is simple enough
## to say out loud.
##
## It drifts on a sine when it has not seen you, and swoops when it has: a
## lunge toward where you were, then a climb, then round again. The point is
## that it threatens from a direction nothing else does.

const TILE := 16

@export var speed := 52.0
@export var swoop_speed := 132.0
@export var sight := 13.0      ## tiles
@export var health := 1
@export var damage := 1
@export var hurts_every := 0.8

var sprite: AnimatedSprite2D

var _player: Node2D = null
var _drift := 0.0
var _home := Vector2.ZERO
var _swooping := false
var _swoop_for := 0.0
var _cooldown := 0.0
var _hurt_flash := 0.0
var _touch := 0.0
var _dying := false


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("hostile")
	_home = global_position
	_drift = randf() * TAU
	collision_layer = 4
	collision_mask = 1

	sprite = AnimatedSprite2D.new()
	sprite.name = "Sprite"
	add_child(sprite)
	ArtManifest.dress(sprite, "bat")
	sprite.play("fly")

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(10, 8)
	shape.shape = rect
	add_child(shape)


func _physics_process(delta: float) -> void:
	if _dying:
		return
	_drift += delta * 3.0
	_cooldown = maxf(0.0, _cooldown - delta)
	_touch = maxf(0.0, _touch - delta)
	_hurt_flash = maxf(0.0, _hurt_flash - delta)
	sprite.modulate = Color(1.7, 0.8, 0.9) if _hurt_flash > 0.0 else Color.WHITE

	if _sees_player():
		_hunt(delta)
	else:
		_wander(delta)

	move_and_slide()
	if absf(velocity.x) > 3.0:
		sprite.flip_h = velocity.x < 0.0
	_bite()


func _sees_player() -> bool:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	return _player != null and is_instance_valid(_player) \
		and global_position.distance_to(_player.global_position) <= sight * TILE


## Nothing hovers still. Even ignoring you it moves.
func _wander(delta: float) -> void:
	var target := _home + Vector2(sin(_drift) * 46.0, cos(_drift * 0.7) * 26.0)
	velocity = velocity.lerp((target - global_position).limit_length(speed), delta * 2.2)


func _hunt(delta: float) -> void:
	if _swooping:
		_swoop_for -= delta
		if _swoop_for <= 0.0:
			_swooping = false
			_cooldown = 1.1
	elif _cooldown <= 0.0:
		_swooping = true
		_swoop_for = 0.62

	if _swooping:
		var toward: Vector2 = (_player.global_position - global_position).normalized()
		velocity = velocity.lerp(toward * swoop_speed, delta * 7.0)
	else:
		# Climbing back out of the dive, above the player, ready to come again.
		var above: Vector2 = _player.global_position + Vector2(sin(_drift) * 58.0, -46.0)
		velocity = velocity.lerp((above - global_position).limit_length(speed), delta * 3.0)


func _bite() -> void:
	if _touch > 0.0 or _player == null or not is_instance_valid(_player):
		return
	if global_position.distance_to(_player.global_position) > 13.0:
		return
	if _player.has_method("is_invulnerable") and _player.is_invulnerable():
		return
	_touch = hurts_every
	var away: int = 1 if _player.global_position.x > global_position.x else -1
	_player.take_damage(damage, away)


func hurt(amount: int, from_direction: int) -> bool:
	if _dying:
		return false
	health -= amount
	_hurt_flash = 0.2
	velocity = Vector2(from_direction * 120.0, -60.0)
	if health <= 0:
		die()
		return true
	return false


func die() -> void:
	if _dying:
		return
	_dying = true
	Goals.note_defeat()
	var world := get_tree().get_first_node_in_group("world")
	if world != null and is_instance_valid(world) and world.has_method("spawn_drop"):
		world.spawn_drop(global_position, "hide", 1)
	var tween := create_tween()
	tween.tween_property(sprite, "modulate:a", 0.0, 0.18)
	tween.parallel().tween_property(self, "position:y", position.y + 14.0, 0.18)
	tween.tween_callback(queue_free)
