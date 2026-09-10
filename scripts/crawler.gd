extends CharacterBody2D
## Crawler. Walks a ledge, turns at walls and edges, dies when stomped.

@export var speed := 34.0
@export var gravity := 900.0
@export var direction := 1

@export_group("Hunting")
## A hunter walks toward the player instead of patrolling, and will drop off a
## ledge to keep coming. This is what makes night mean something.
@export var hunts := false
@export var sight := 16.0        ## tiles
@export var hunt_speed := 46.0
@export var health := 2
@export var jump_velocity := -260.0

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var floor_probe: RayCast2D = $FloorProbe
@onready var hitbox: Area2D = $Hitbox

var _dying := false
var _hurt_flash := 0.0
var _player: Node2D = null


func _ready() -> void:
	add_to_group("enemy")
	if hunts:
		add_to_group("hostile")


func _physics_process(delta: float) -> void:
	if _dying:
		return

	velocity.y += gravity * delta

	var chasing := hunts and _sees_player()
	if chasing:
		direction = 1 if _player.global_position.x > global_position.x else -1
		velocity.x = direction * hunt_speed
		# A hunter that stops at every ledge is not a threat. Hop over what is
		# in the way and take the fall on the far side.
		if is_on_floor() and is_on_wall():
			velocity.y = jump_velocity
	else:
		velocity.x = direction * speed
		# Patrolling, turn around at a wall or where the ground runs out.
		floor_probe.position.x = absf(floor_probe.position.x) * direction
		if is_on_wall() or (is_on_floor() and not floor_probe.is_colliding()):
			direction *= -1

	move_and_slide()

	_hurt_flash = maxf(0.0, _hurt_flash - delta)
	sprite.modulate = Color(1.6, 0.7, 0.7) if _hurt_flash > 0.0 else Color.WHITE
	sprite.flip_h = direction < 0
	sprite.play("walk")

	_check_player()


func _sees_player() -> bool:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player == null or not is_instance_valid(_player):
		return false
	return global_position.distance_to(_player.global_position) <= sight * 16.0


## Took a hit. Returns true if that killed it.
func hurt(amount: int, from_direction: int) -> bool:
	if _dying:
		return false
	health -= amount
	_hurt_flash = 0.18
	velocity.x = from_direction * 90.0
	velocity.y = -110.0
	if health <= 0:
		die()
		return true
	return false


func _check_player() -> void:
	for body in hitbox.get_overlapping_bodies():
		if not body.is_in_group("player"):
			continue
		var stomped: bool = body.velocity.y > 0.0 and body.global_position.y < global_position.y - 4.0
		if stomped:
			body.bounce()
			hurt(2, 0)
		else:
			var away: int = 1 if body.global_position.x > global_position.x else -1
			body.take_damage(1, away)
		return


func die() -> void:
	if _dying:
		return
	_dying = true
	set_deferred("collision_layer", 0)
	hitbox.set_deferred("monitoring", false)
	var tween := create_tween()
	tween.tween_property(sprite, "scale:y", 0.2, 0.08)
	tween.parallel().tween_property(sprite, "modulate:a", 0.0, 0.12)
	tween.tween_callback(queue_free)
