extends Control
## Title screen. Press anything to descend.

const FIRST_ZONE := "res://scenes/world.tscn"

@onready var prompt: Label = $Prompt


func _ready() -> void:
	Ui.set_gameplay_visible(false)

	# Skip straight into the world. Play scripts and the browser check use this
	# so they do not have to get a key press through a focused canvas, and it is
	# quicker for anyone testing a particular seed:
	#   ./tools/play.sh --start --seed=7
	#   index.html?start&seed=7
	if BootConfig.has("start"):
		call_deferred("_begin")
		return
	var tween := create_tween().set_loops()
	tween.tween_property(prompt, "modulate:a", 0.25, 0.7)
	tween.tween_property(prompt, "modulate:a", 1.0, 0.7)


func _begin() -> void:
	Game.change_zone(FIRST_ZONE, "Aerenfall")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_begin()
