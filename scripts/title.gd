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
	# Lets a built artifact be checked, not just the source tree. Three
	# releases shipped with an input map that matched nothing, and running the
	# game was the only way that would have shown up.
	#   BocciaBound --check-input
	if BootConfig.has("check-input"):
		var dead := InputCheck.dead_bindings()
		if dead.is_empty():
			print("input map OK: every key binding responds to its own key")
		else:
			printerr("DEAD KEY BINDINGS: ", ", ".join(dead))
		get_tree().quit(0 if dead.is_empty() else 1)
		return

	if BootConfig.has("start"):
		call_deferred("_begin")
		return
	var tween := create_tween().set_loops()
	tween.tween_property(prompt, "modulate:a", 0.25, 0.7)
	tween.tween_property(prompt, "modulate:a", 1.0, 0.7)


func _begin() -> void:
	Game.change_zone(FIRST_ZONE, "Aerenfall")


func _unhandled_input(event: InputEvent) -> void:
	# A click counts as well as a key. In a browser the canvas often does not
	# receive keystrokes until it has been clicked once, so a player who loads
	# the page and presses space gets nothing and assumes it is broken.
	var pressed_key: bool = event.is_action_pressed("jump") or event.is_action_pressed("interact")
	var pressed_pointer: bool = (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed)
	if pressed_key or pressed_pointer:
		get_viewport().set_input_as_handled()
		_begin()
