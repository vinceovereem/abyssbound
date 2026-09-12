extends Node
## Does pressing the key on the title screen actually start the game?
##
## Reported as "I press space and it doesn't get in". This drives the real
## title scene with the real action and watches for the fade that a scene
## change starts with.

var _passed := 0
var _failed := 0


func _ok(label: String, condition: bool, detail := "") -> void:
	if condition:
		_passed += 1
		print("  PASS  %s%s" % [label, (" (%s)" % detail) if detail else ""])
	else:
		_failed += 1
		print("  FAIL  %s%s" % [label, (" (%s)" % detail) if detail else ""])


func _ready() -> void:
	print("Abyssbound start test")
	print("---------------------")
	await get_tree().process_frame

	_ok("the jump action exists", InputMap.has_action("jump"))
	var keys: Array = []
	for event in InputMap.action_get_events("jump"):
		if event is InputEventKey:
			keys.append(event.physical_keycode)
	_ok("space is still bound to it", keys.has(KEY_SPACE), str(keys))
	_ok("the world scene exists", ResourceLoader.exists("res://scenes/world.tscn"))

	# The bug this file was written for: every key was bound with device 16,
	# so a real key press matched no action at all.
	var unmatched := InputCheck.dead_bindings()
	_ok("every key binding matches a real key press", unmatched.is_empty(),
		", ".join(unmatched) if not unmatched.is_empty() else "all bindings live")

	var title: Control = load("res://scenes/main.tscn").instantiate()
	add_child(title)
	for i in 10:
		await get_tree().physics_frame

	var fade: ColorRect = Ui.get_node("Fade")
	fade.color.a = 0.0

	# A real key event, not Input.action_press: that sets the action state for
	# code that polls, but never produces an event, so it cannot reach an
	# _unhandled_input handler like the title screen's.
	var press := InputEventKey.new()
	press.physical_keycode = KEY_SPACE
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().process_frame
	for i in 8:
		await get_tree().physics_frame

	_ok("pressing it starts a scene change", fade.color.a > 0.01,
		"fade alpha %.2f" % fade.color.a)

	# Changing scene frees this node, because it is the current scene. A
	# watcher parented to the root outlives that and can report whether the
	# world really arrived, which is the half of "does the game start" that
	# checking for a fade does not cover.
	var watcher := Node.new()
	watcher.set_script(load("res://tests/playtest/start_watcher.gd"))
	watcher.passed_so_far = _passed
	get_tree().root.add_child(watcher)

	print("  ... waiting for the world to load")
