extends Node
## What there is to do. Autoloaded as `Goals`.
##
## Terraria never tells you what to do, and it works because the world is full
## enough to suggest it. This world is not there yet, so until it is, a short
## list of the next few things gives a new player somewhere to point themselves.
## They are written as nudges, not quests: nothing gates on them and nothing is
## lost by ignoring them.
##
## The list is data. Adding one needs no code as long as its kind already
## exists here.

signal completed(id: String, text: String)
signal progressed(id: String, have: int, need: int)

const PATH := "res://data/objectives.json"
## How many to show at once. A wall of them is a chore list, not a nudge.
const SHOWN := 3

var objectives: Array = []
var progress := {}
var done := {}


func _ready() -> void:
	_load()
	Game.resource_collected.connect(_on_resource)
	DayClock.day_broke.connect(_on_dawn)


func _load() -> void:
	if not FileAccess.file_exists(PATH):
		push_error("Objectives: %s is missing. Add it to the export include_filter." % PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Objectives: %s is not the expected shape." % PATH)
		return
	objectives = parsed.get("objectives", [])


func reset() -> void:
	progress.clear()
	done.clear()


## The next few unfinished ones, in order.
func active() -> Array:
	var out: Array = []
	for objective: Dictionary in objectives:
		if done.has(objective["id"]):
			continue
		out.append(objective)
		if out.size() >= SHOWN:
			break
	return out


func have(id: String) -> int:
	return int(progress.get(id, 0))


func need(objective: Dictionary) -> int:
	return int(objective.get("count", 1))


func is_done(id: String) -> bool:
	return done.has(id)


func all_done() -> bool:
	return done.size() >= objectives.size()


# ---------------------------------------------------------------------------
# Things happening in the world
# ---------------------------------------------------------------------------
func _on_resource(resource: String, amount: int, _total: int) -> void:
	_advance("collect", resource, amount)


func _on_dawn(_day: int) -> void:
	_advance("dawn", "", 1)


func note_placed(tile_name: String) -> void:
	_advance("place", tile_name, 1)


func note_defeat() -> void:
	_advance("defeat", "", 1)


## Called with the player's depth below the surface, and their Abyss layer.
## These are "reached" rather than counted, so they take the best seen.
func note_depth(below_surface: int, abyss_layer: int) -> void:
	_reach("depth", below_surface)
	_reach("layer", abyss_layer)


func _advance(kind: String, what: String, amount: int) -> void:
	for objective: Dictionary in objectives:
		if objective["kind"] != kind or done.has(objective["id"]):
			continue
		if objective.has("what") and str(objective["what"]) != what:
			continue
		_bump(objective, have(objective["id"]) + amount)


func _reach(kind: String, value: int) -> void:
	for objective: Dictionary in objectives:
		if objective["kind"] != kind or done.has(objective["id"]):
			continue
		if value > have(objective["id"]):
			_bump(objective, value)


func _bump(objective: Dictionary, value: int) -> void:
	var id: String = objective["id"]
	var target := need(objective)
	progress[id] = mini(value, target)
	progressed.emit(id, progress[id], target)
	if progress[id] >= target:
		done[id] = true
		completed.emit(id, str(objective["text"]))
