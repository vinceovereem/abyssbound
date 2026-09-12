extends Node
## The game in stages. Autoloaded as `Goals`.
##
## A stage is a handful of things to do; finishing them all moves you on and
## says what the next part of the game is about. They stay **nudges rather than
## gates**: nothing is locked behind them, because deciding what to do is the
## point of the world. What a stage buys is a sense of where you are in it.

signal completed(id: String, text: String)
signal progressed(id: String, have: int, need: int)
signal stage_finished(index: int, name: String)
signal stage_started(index: int, name: String, blurb: String)

const PATH := "res://data/objectives.json"

var stages: Array = []
var stage := 0
var progress := {}
var done := {}


func _ready() -> void:
	_load()
	Game.resource_collected.connect(_on_resource)
	Game.health_changed.connect(_on_health)
	DayClock.day_broke.connect(_on_dawn)


func _load() -> void:
	if not FileAccess.file_exists(PATH):
		push_error("Objectives: %s is missing. Add it to the export include_filter." % PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Objectives: %s is not the expected shape." % PATH)
		return
	stages = parsed.get("stages", [])


func reset() -> void:
	progress.clear()
	done.clear()
	stage = 0


# ---------------------------------------------------------------------------
# Where you are
# ---------------------------------------------------------------------------
func current() -> Dictionary:
	if stage < 0 or stage >= stages.size():
		return {}
	return stages[stage]


func stage_name() -> String:
	return str(current().get("name", ""))


func stage_blurb() -> String:
	return str(current().get("blurb", ""))


func all_finished() -> bool:
	return stage >= stages.size()


## The objectives of the stage you are on, finished ones included so the list
## does not jump about as you tick them off.
func active() -> Array:
	return current().get("objectives", [])


func have(id: String) -> int:
	return int(progress.get(id, 0))


func need(objective: Dictionary) -> int:
	return int(objective.get("count", 1))


func is_done(id: String) -> bool:
	return done.has(id)


# ---------------------------------------------------------------------------
# Things happening in the world
# ---------------------------------------------------------------------------
func _on_resource(resource: String, amount: int, _total: int) -> void:
	_advance("collect", resource, amount)


func _on_dawn(_day: int) -> void:
	_advance("dawn", "", 1)


func _on_health(_current: int, maximum: int) -> void:
	_reach("hearts", maximum)


func note_placed(tile_name: String) -> void:
	_advance("place", tile_name, 1)


func note_crafted(item_id: String, amount: int) -> void:
	_advance("craft", item_id, amount)


func note_defeat() -> void:
	_advance("defeat", "", 1)


func note_chest() -> void:
	_advance("chest", "", 1)


func note_heart() -> void:
	_advance("heart", "", 1)


func note_tamed() -> void:
	_advance("tame", "", 1)


func note_depth(below_surface: int, band: int) -> void:
	_reach("depth", below_surface)
	_reach("layer", band)


# ---------------------------------------------------------------------------
func _advance(kind: String, what: String, amount: int) -> void:
	for objective: Dictionary in active():
		if objective["kind"] != kind or done.has(objective["id"]):
			continue
		if objective.has("what") and str(objective["what"]) != what:
			continue
		_bump(objective, have(objective["id"]) + amount)


func _reach(kind: String, value: int) -> void:
	for objective: Dictionary in active():
		if objective["kind"] != kind or done.has(objective["id"]):
			continue
		if value > have(objective["id"]):
			_bump(objective, value)


func _bump(objective: Dictionary, value: int) -> void:
	var id: String = objective["id"]
	var target := need(objective)
	progress[id] = mini(value, target)
	progressed.emit(id, progress[id], target)
	if progress[id] < target:
		return
	done[id] = true
	completed.emit(id, str(objective["text"]))
	_check_stage()


func _check_stage() -> void:
	for objective: Dictionary in active():
		if not done.has(objective["id"]):
			return
	if all_finished():
		return
	stage_finished.emit(stage, stage_name())
	stage += 1
	if not all_finished():
		stage_started.emit(stage, stage_name(), stage_blurb())
