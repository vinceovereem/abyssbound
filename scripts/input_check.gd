class_name InputCheck
extends RefCounted
## Does every key binding actually match a press of its own key?
##
## This exists because the answer was "no" for the whole project's life: every
## key was bound to a device real presses never come from, so nothing on the
## keyboard did anything. Shared between the headless check and the shipped
## build, so what CI verifies and what a player runs are the same code.


## Bindings that would not respond to their own key. Empty means all is well.
static func dead_bindings() -> Array[String]:
	var dead: Array[String] = []
	for action: StringName in InputMap.get_actions():
		if str(action).begins_with("ui_"):
			continue
		for event in InputMap.action_get_events(action):
			if not (event is InputEventKey):
				continue
			var probe := InputEventKey.new()
			probe.physical_keycode = event.physical_keycode
			probe.keycode = event.keycode
			probe.pressed = true
			if not InputMap.event_is_action(probe, action):
				dead.append("%s / %s" % [action, event.as_text()])
	return dead
