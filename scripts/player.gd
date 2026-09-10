extends CharacterBody2D
## The descender. A deliberately plain 2D platformer controller.
##
## The feel knobs are all exported, so tuning happens in the inspector and not
## in this file. Coyote time and jump buffering are in because without them a
## pixel platformer feels broken, not hard.

@export_group("Movement")
@export var max_speed := 108.0
@export var acceleration := 900.0
@export var ground_friction := 1100.0
@export var air_friction := 320.0

@export_group("Jump")
@export var jump_velocity := -340.0
@export var gravity := 980.0
@export var fall_gravity_multiplier := 1.35
@export var max_fall_speed := 380.0
@export var coyote_time := 0.10
@export var jump_buffer_time := 0.12
@export var bounce_velocity := -220.0

@export_group("Traversal")
## Height of a ledge the player walks up without jumping, in pixels. One tile.
## Natural ground is full of single tile steps and having to jump every one of
## them turns walking into work. Set to 0 to go back to jumping over everything.
@export var step_height := 16.0

@export_group("Damage")
@export var invulnerable_time := 1.0
@export var knockback_speed := 130.0

@onready var sprite: AnimatedSprite2D = $Sprite

var _coyote := 0.0
var _buffer := 0.0
var _invulnerable := 0.0
var _knockback := 0.0
var _facing := 1


func _ready() -> void:
	add_to_group("player")


func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	_apply_gravity(delta)
	_apply_input(delta)
	_apply_jump()
	_try_step_up()

	move_and_slide()
	_animate()


func _tick_timers(delta: float) -> void:
	_coyote = coyote_time if is_on_floor() else max(0.0, _coyote - delta)
	_buffer = jump_buffer_time if Input.is_action_just_pressed("jump") else max(0.0, _buffer - delta)
	_invulnerable = max(0.0, _invulnerable - delta)
	_knockback = max(0.0, _knockback - delta)
	sprite.modulate.a = 0.4 if _invulnerable > 0.0 and int(_invulnerable * 20) % 2 == 0 else 1.0


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	var g := gravity
	# Heavier on the way down. Cheap trick, big difference to the feel.
	if velocity.y > 0.0 or not Input.is_action_pressed("jump"):
		g *= fall_gravity_multiplier
	velocity.y = min(velocity.y + g * delta, max_fall_speed)


func _apply_input(delta: float) -> void:
	if _knockback > 0.0:
		return
	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		velocity.x = move_toward(velocity.x, direction * max_speed, acceleration * delta)
		_facing = signi(int(direction))
	else:
		var friction := ground_friction if is_on_floor() else air_friction
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)


func _apply_jump() -> void:
	if _buffer > 0.0 and _coyote > 0.0:
		velocity.y = jump_velocity
		_buffer = 0.0
		_coyote = 0.0
	# Release the jump key early, cut the rise short.
	if Input.is_action_just_released("jump") and velocity.y < jump_velocity * 0.4:
		velocity.y = jump_velocity * 0.4


## Walk up a single tile ledge instead of stopping dead at it. Only when
## grounded and already moving into the thing, and only when there is really
## room up there, so it cannot be used to climb a wall or clip a ceiling.
func _try_step_up() -> void:
	if step_height <= 0.0 or not is_on_floor() or absf(velocity.x) < 4.0:
		return
	var ahead := Vector2(signf(velocity.x) * 3.0, 0.0)
	if not test_move(global_transform, ahead):
		return  # nothing in the way
	if test_move(global_transform, Vector2(0.0, -step_height)):
		return  # no headroom to rise into
	var lifted := global_transform.translated(Vector2(0.0, -step_height))
	if test_move(lifted, ahead):
		return  # still blocked up there, so it is a wall and not a step
	global_position.y -= step_height


func _animate() -> void:
	sprite.flip_h = _facing < 0
	if not is_on_floor():
		sprite.play("jump" if velocity.y < 0.0 else "fall")
	elif absf(velocity.x) > 8.0:
		sprite.play("run")
	else:
		sprite.play("idle")


## Which way the player is looking. Digging aims with this.
func facing() -> int:
	return _facing


## Called by an enemy when the player lands on its head.
func bounce() -> void:
	velocity.y = bounce_velocity
	_coyote = 0.0


func is_invulnerable() -> bool:
	return _invulnerable > 0.0


func take_damage(amount: int, from_direction: int) -> void:
	if _invulnerable > 0.0:
		return
	_invulnerable = invulnerable_time
	_knockback = 0.18
	velocity = Vector2(from_direction * knockback_speed, bounce_velocity * 0.6)
	Game.damage(amount)
