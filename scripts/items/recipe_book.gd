class_name RecipeBook
extends RefCounted
## What can be made from what, loaded from data/recipes.json.

const PATH := "res://data/recipes.json"

static var _book: RecipeBook = null

var recipes: Array = []


static func get_book() -> RecipeBook:
	if _book == null:
		_book = RecipeBook.new()
		_book._load()
	return _book


static func reset() -> void:
	_book = null


func _load() -> void:
	if not FileAccess.file_exists(PATH):
		push_error("RecipeBook: %s is missing. Add it to the export include_filter." % PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("RecipeBook: %s is not the expected shape." % PATH)
		return
	recipes = parsed.get("recipes", [])


func station_for(recipe: Dictionary) -> String:
	return str(recipe.get("station", ""))


## Everything makeable right now, given what is carried and what is standing
## nearby. Returns indices into `recipes`.
func available(inventory: Inventory, stations: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for i in recipes.size():
		if can_make(i, inventory, stations):
			out.append(i)
	return out


func can_make(index: int, inventory: Inventory, stations: Dictionary) -> bool:
	if index < 0 or index >= recipes.size():
		return false
	var recipe: Dictionary = recipes[index]
	var station := station_for(recipe)
	if not station.is_empty() and not stations.has(station):
		return false
	for id: String in recipe["needs"].keys():
		if inventory.count_of(id) < int(recipe["needs"][id]):
			return false
	return true


## Spends the materials and hands over the result. False if it could not.
func make(index: int, inventory: Inventory, stations: Dictionary) -> bool:
	if not can_make(index, inventory, stations):
		return false
	var recipe: Dictionary = recipes[index]
	for id: String in recipe["needs"].keys():
		inventory.remove(id, int(recipe["needs"][id]))
	var left := inventory.add(str(recipe["out"]), int(recipe.get("count", 1)))
	if left > 0:
		# No room. Put the materials back rather than eating them.
		inventory.remove(str(recipe["out"]), int(recipe.get("count", 1)) - left)
		for id: String in recipe["needs"].keys():
			inventory.add(id, int(recipe["needs"][id]))
		return false
	return true
