class_name TileDB
extends RefCounted
## Tile definitions, loaded once from data/tiles.json.
##
## Design owns the json. Code owns this loader. Lookups are packed arrays
## indexed by tile id rather than dictionaries, because the lighting pass asks
## for opacity once per tile per recompute and a dictionary lookup there is
## measurable.

const PATH := "res://data/tiles.json"

const AIR := 0

static var _db: TileDB = null

var solid := PackedByteArray()
var hardness := PackedInt32Array()
var opacity := PackedByteArray()
var emit := PackedByteArray()
var wall := PackedByteArray()
var drop := {}       ## id -> what breaking it gives you, "" for nothing
var id_of := {}      ## name -> id
var name_of := {}    ## id -> name
var max_id := 0


static func get_db() -> TileDB:
	if _db == null:
		_db = TileDB.new()
		_db._load()
	return _db


## Only for tests that want a clean reload.
static func reset() -> void:
	_db = null


func _load() -> void:
	if not FileAccess.file_exists(PATH):
		push_error("TileDB: %s is missing. It must be in the export include_filter." % PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("tiles"):
		push_error("TileDB: %s is not the expected shape." % PATH)
		return

	var rows: Array = parsed["tiles"]
	for row: Dictionary in rows:
		max_id = maxi(max_id, int(row["id"]))

	var size := max_id + 1
	solid.resize(size)
	hardness.resize(size)
	opacity.resize(size)
	emit.resize(size)
	wall.resize(size)

	for row: Dictionary in rows:
		var id := int(row["id"])
		solid[id] = 1 if row.get("solid", false) else 0
		hardness[id] = int(row.get("hardness", 0))
		opacity[id] = int(row.get("opacity", 0))
		emit[id] = int(row.get("emit", 0))
		wall[id] = 1 if row.get("wall", false) else 0
		var tile_name: String = row["name"]
		# Unstated means it gives back itself, which is true of most rock.
		drop[id] = str(row.get("drop", tile_name if row.get("solid", false) else ""))
		id_of[tile_name] = id
		name_of[id] = tile_name


func is_solid(id: int) -> bool:
	return id > 0 and id < solid.size() and solid[id] == 1


func drop_of(id: int) -> String:
	return str(drop.get(id, ""))


## "copper_ore" reads as "Copper Ore" on screen.
static func pretty(resource: String) -> String:
	return resource.replace("_", " ").capitalize()


func id(tile_name: String) -> int:
	return int(id_of.get(tile_name, 0))
