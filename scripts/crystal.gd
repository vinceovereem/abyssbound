extends Area2D
## A collectible crystal. Bobs, sparkles, pops when picked up.

@export var value := 1
@export var bob_height := 2.0
@export var bob_speed := 2.4

@onready var sprite: AnimatedSprite2D = $Sprite

var _origin_y := 0.0
var _phase := 0.0
var _taken := false


func _ready() -> void:
	add_to_group("pickup")
	_origin_y = position.y
	_phase = randf() * TAU
	sprite.play("spin")
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_phase += delta * bob_speed
	position.y = _origin_y + sin(_phase) * bob_height


func _on_body_entered(body: Node2D) -> void:
	if _taken or not body.is_in_group("player"):
		return
	_taken = true
	set_deferred("monitoring", false)
	Game.add_crystals(value)
	set_process(false)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.6, 1.6), 0.08)
	tween.parallel().tween_property(self, "position:y", position.y - 8.0, 0.18)
	tween.parallel().tween_property(sprite, "modulate:a", 0.0, 0.18)
	tween.tween_callback(queue_free)
