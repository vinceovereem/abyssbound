extends Node
## Global game state. Autoloaded as `Game`.
##
## Holds the things that must survive a scene change: health, crystals and
## which zone the player is in. Everything that cares about those values
## listens to the signals below instead of polling.

signal health_changed(current: int, maximum: int)
signal crystals_changed(total: int)
signal zone_changed(zone_name: String)
## Something was broken and picked up. total is how many of it you now hold.
signal resource_collected(resource: String, amount: int, total: int)
## Health reached zero. Whoever owns the world puts the player back; nothing
## here reloads a scene, because reloading a generated world throws it away.
signal player_died
## Took a hit. The world floats the number where it happened.
signal player_hurt(amount: int)

const MAX_HEALTH := 5

var health: int = MAX_HEALTH
var crystals: int = 0
var zone_name: String = "Surface"

## What the player is carrying. This replaced a plain name-to-count tally; do
## not reintroduce one alongside it, or the two will disagree.
var inventory: Inventory

var _changing_zone := false


func _ready() -> void:
	inventory = Inventory.new()
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


## Picked up. Returns what would not fit, which the caller may want to leave
## on the ground rather than quietly destroy.
func collect(resource: String, amount: int) -> int:
	if resource.is_empty() or amount <= 0:
		return amount
	var left := inventory.add(resource, amount)
	var taken := amount - left
	if taken > 0:
		resource_collected.emit(resource, taken, inventory.count_of(resource))
	return left


func amount_of(resource: String) -> int:
	return inventory.count_of(resource)


func damage(amount: int) -> void:
	# Armour softens a hit but never removes it entirely. Being untouchable
	# takes the tension out of a night faster than being fragile does.
	var softened: int = maxi(1, amount - inventory.defence() / 3)
	health = max(0, health - softened)
	player_hurt.emit(softened)
	health_changed.emit(health, MAX_HEALTH)
	if health == 0:
		call_deferred("_on_death")


func heal(amount: int) -> void:
	health = min(MAX_HEALTH, health + amount)
	health_changed.emit(health, MAX_HEALTH)


func _on_death() -> void:
	# The old text said "you fell too deep", from when falling was the only way
	# to die. Being killed by something and being told you fell is worse than
	# saying nothing.
	Ui.show_message("You died.", "Waking up where you started")
	player_died.emit()


## Reset run state and reload the current zone.
func restart() -> void:
	health = MAX_HEALTH
	crystals = 0
	inventory.clear()
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
