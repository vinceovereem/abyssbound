class_name Combat
extends Node2D
## The player's swing.
##
## Aimed the same way digging is, because having two different aiming schemes
## in one game is how a control scheme stops being learnable: X hits what F
## would dig.
##
## Damage is a flat number here. Milestone 4's weapons scale it; nothing else
## about this file should need to change when they do.

const TILE := 16
const COOLDOWN := 0.38
const SWING_SHOWN := 0.14
const DAMAGE := 1
const REACH := 22.0     ## pixels from the player's centre

var world: Node2D

var _cooldown := 0.0
var _shown := 0.0
var _last_hit_rect := Rect2()


func setup(world_node: Node2D) -> void:
	world = world_node
	z_index = 6


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_shown = maxf(0.0, _shown - delta)
	if _shown > 0.0:
		queue_redraw()

	if world == null or world.player == null or not is_instance_valid(world.player):
		return
	if _cooldown <= 0.0 and Input.is_action_pressed("attack"):
		_swing()


func _swing() -> void:
	_cooldown = COOLDOWN
	_shown = SWING_SHOWN

	var origin: Vector2 = world.player.global_position
	var offset := Vector2(float(world.player.facing()) * REACH * 0.6, 0.0)
	if Input.is_action_pressed("move_down"):
		offset = Vector2(0.0, REACH * 0.6)
	elif Input.is_action_pressed("move_up"):
		offset = Vector2(0.0, -REACH * 0.6)

	var centre := origin + offset
	_last_hit_rect = Rect2(centre - Vector2(REACH, REACH) * 0.5, Vector2(REACH, REACH))
	queue_redraw()

	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy) or not enemy.has_method("hurt"):
			continue
		if not _last_hit_rect.has_point(enemy.global_position):
			continue
		var away: int = 1 if enemy.global_position.x > origin.x else -1
		enemy.hurt(DAMAGE, away)
		world.float_text(enemy.global_position - Vector2(0, 10), str(DAMAGE),
			Color(1.0, 0.85, 0.35), 18.0)


func _draw() -> void:
	if _shown <= 0.0:
		return
	var fade := _shown / SWING_SHOWN
	draw_rect(_last_hit_rect, Color(1.0, 0.95, 0.7, 0.35 * fade), true)
	draw_rect(_last_hit_rect, Color(1.0, 1.0, 0.9, 0.7 * fade), false, 1.0)
