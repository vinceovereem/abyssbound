extends Node
## Global game state. Autoloaded as `Game`.
##
## Holds the things that must survive a scene change: health, crystals and
## which zone the player is in. Everything that cares about those values
## listens to the signals below instead of polling.

signal health_changed(current: int, maximum: int)
signal crystals_changed(total: int)
signal zone_changed(zone_name: String)

const MAX_HEALTH := 5

var health: int = MAX_HEALTH
var crystals: int = 0
var zone_name: String = "Surface"

var _changing_zone := false


func _ready() -> void:
	# Autoloads start before the first scene, so announce the initial values
	# on the next frame once listeners exist.
	call_deferred("_broadcast")


func _broadcast() -> void:
	health_changed.emit(health, MAX_HEALTH)
	crystals_changed.emit(crystals)
	zone_changed.emit(zone_name)


func add_crystals(amount: int) -> void:
	crystals += amount
	crystals_changed.emit(crystals)


func damage(amount: int) -> void:
	health = max(0, health - amount)
	health_changed.emit(health, MAX_HEALTH)
	if health == 0:
		call_deferred("_on_death")


func heal(amount: int) -> void:
	health = min(MAX_HEALTH, health + amount)
	health_changed.emit(health, MAX_HEALTH)


func _on_death() -> void:
	Ui.show_message("You fell too deep.", "Press R to try again")


## Reset run state and reload the current zone.
func restart() -> void:
	health = MAX_HEALTH
	crystals = 0
	_broadcast()
	Ui.hide_message()
	change_zone(get_tree().current_scene.scene_file_path, zone_name)


## Fade out, swap the scene, fade back in.
func change_zone(scene_path: String, new_zone_name: String) -> void:
	if _changing_zone:
		return
	_changing_zone = true
	await Ui.fade_out()
	zone_name = new_zone_name
	zone_changed.emit(zone_name)
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("Could not load zone: %s" % scene_path)
	await get_tree().process_frame
	await Ui.fade_in()
	_changing_zone = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		restart()
	elif event.is_action_pressed("ui_cancel"):
		get_tree().quit()
