extends Control
## Title screen. Press anything to descend.

const FIRST_ZONE := "res://scenes/levels/zone_surface.tscn"

@onready var prompt: Label = $Prompt


func _ready() -> void:
	Ui.set_gameplay_visible(false)
	var tween := create_tween().set_loops()
	tween.tween_property(prompt, "modulate:a", 0.25, 0.7)
	tween.tween_property(prompt, "modulate:a", 1.0, 0.7)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		Game.change_zone(FIRST_ZONE, "Surface")
