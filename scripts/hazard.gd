extends Area2D
## Anything that hurts on contact and does not move.

@export var damage := 1


func _physics_process(_delta: float) -> void:
	for body in get_overlapping_bodies():
		if body.is_in_group("player") and not body.is_invulnerable():
			var away: int = 1 if body.global_position.x > global_position.x else -1
			body.take_damage(damage, away)
