extends CharacterBody2D
## Critter. Harmless. Hold the interact key nearby to earn its trust, then it
## follows you. This is the smallest possible version of the taming hook, here
## so the loop is visible in the placeholder.

@export var speed := 70.0
@export var gravity := 900.0
@export var trust_rate := 55.0
@export var follow_distance := 26.0

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var trust_area: Area2D = $TrustArea
@onready var trust_bar: ProgressBar = $TrustBar
@onready var heart: Label = $Heart

var trust := 0.0
var tamed := false
var _player: Node2D = null


func _ready() -> void:
	add_to_group("critter")
	trust_bar.visible = false
	heart.visible = false


func _physics_process(delta: float) -> void:
	velocity.y += gravity * delta

	if tamed:
		_follow(delta)
	else:
		_wait_to_be_tamed(delta)

	move_and_slide()
	if absf(velocity.x) > 4.0:
		sprite.flip_h = velocity.x < 0.0
	sprite.play("walk" if absf(velocity.x) > 4.0 else "idle")


func _wait_to_be_tamed(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
	var near := _player_in_range()
	trust_bar.visible = near != null

	if near and Input.is_action_pressed("interact"):
		trust = min(100.0, trust + trust_rate * delta)
		trust_bar.value = trust
		if trust >= 100.0:
			_tame(near)
	elif trust > 0.0:
		trust = max(0.0, trust - trust_rate * 0.5 * delta)
		trust_bar.value = trust


func _player_in_range() -> Node2D:
	for body in trust_area.get_overlapping_bodies():
		if body.is_in_group("player"):
			return body
	return null


func _tame(player: Node2D) -> void:
	tamed = true
	_player = player
	trust_bar.visible = false
	heart.visible = true
	var tween := create_tween()
	tween.tween_property(heart, "position:y", heart.position.y - 8.0, 0.6)
	tween.parallel().tween_property(heart, "modulate:a", 0.0, 0.6)
	tween.tween_callback(func() -> void: heart.visible = false)


func _follow(delta: float) -> void:
	if not is_instance_valid(_player):
		velocity.x = 0.0
		return
	var gap := _player.global_position.x - global_position.x
	if absf(gap) > follow_distance:
		velocity.x = move_toward(velocity.x, signf(gap) * speed, 600.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
	# Hop if the player is well above and we are grounded.
	if is_on_floor() and _player.global_position.y < global_position.y - 20.0:
		velocity.y = -210.0
