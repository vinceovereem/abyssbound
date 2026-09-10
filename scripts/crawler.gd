extends CharacterBody2D
## Crawler. Walks a ledge, turns at walls and edges, dies when stomped.

@export var speed := 34.0
@export var gravity := 900.0
@export var direction := 1

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var floor_probe: RayCast2D = $FloorProbe
@onready var hitbox: Area2D = $Hitbox

var _dying := false


func _ready() -> void:
	add_to_group("enemy")


func _physics_process(delta: float) -> void:
	if _dying:
		return

	velocity.y += gravity * delta
	velocity.x = direction * speed

	# Turn around at a wall, or when the ground ahead runs out.
	floor_probe.position.x = absf(floor_probe.position.x) * direction
	if is_on_wall() or (is_on_floor() and not floor_probe.is_colliding()):
		direction *= -1

	move_and_slide()
	sprite.flip_h = direction < 0
	sprite.play("walk")

	_check_player()


func _check_player() -> void:
	for body in hitbox.get_overlapping_bodies():
		if not body.is_in_group("player"):
			continue
		var stomped: bool = body.velocity.y > 0.0 and body.global_position.y < global_position.y - 4.0
		if stomped:
			body.bounce()
			die()
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
