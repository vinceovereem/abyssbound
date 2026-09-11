class_name ItemDB
extends RefCounted
## Everything the player can hold, loaded once from data/items.json.
##
## Same shape as TileDB: design owns the json, code owns the loader.

const PATH := "res://data/items.json"

static var _db: ItemDB = null

var items := {}       ## id -> Dictionary
var order: Array[String] = []
## Reverse lookups, built once: which item a tile came from, and which
## crafting station standing on a tile provides.
var item_for_tile := {}
var station_for_tile := {}


static func get_db() -> ItemDB:
	if _db == null:
		_db = ItemDB.new()
		_db._load()
	return _db


static func reset() -> void:
	_db = null


func _load() -> void:
	if not FileAccess.file_exists(PATH):
		push_error("ItemDB: %s is missing. It must be in the export include_filter." % PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ItemDB: %s is not the expected shape." % PATH)
		return
	for row: Dictionary in parsed.get("items", []):
		items[row["id"]] = row
		order.append(str(row["id"]))
		var tile := str(row.get("tile", ""))
		if not tile.is_empty():
			item_for_tile[tile] = str(row["id"])
			var station := str(row.get("station", ""))
			if not station.is_empty():
				station_for_tile[tile] = station


func has(id: String) -> bool:
	return items.has(id)


func of(id: String) -> Dictionary:
	return items.get(id, {})


func display_name(id: String) -> String:
	return str(of(id).get("name", TileDB.pretty(id)))


func kind(id: String) -> String:
	return str(of(id).get("kind", "material"))


func stack_limit(id: String) -> int:
	return int(of(id).get("stack", 99))


## The tile this becomes when placed, or "" if it is not a block.
func tile_of(id: String) -> String:
	return str(of(id).get("tile", ""))


## The crafting station this provides once placed, or "".
func station_of(id: String) -> String:
	return str(of(id).get("station", ""))


func power_of(id: String) -> int:
	return int(of(id).get("power", 0))


func damage_of(id: String) -> int:
	return int(of(id).get("damage", 0))
