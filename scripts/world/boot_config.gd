class_name BootConfig
extends RefCounted
## Where the world's starting parameters come from.
##
## A play script has to be able to jump straight to the thing it tests, so the
## seed and the spawn column are readable from the command line on desktop and
## from the query string on the web:
##
##   godot --path . -- --seed=1234 --spawn-x=940
##   index.html?seed=1234&spawn-x=940

const DEFAULT_SPAWN_X := 940

static var _args: Dictionary = {}
static var _parsed := false


static func _parse() -> void:
	if _parsed:
		return
	_parsed = true

	var raw: PackedStringArray = OS.get_cmdline_args()
	raw.append_array(OS.get_cmdline_user_args())

	if OS.has_feature("web"):
		var query: String = str(JavaScriptBridge.eval("window.location.search", true))
		for pair in query.trim_prefix("?").split("&"):
			if pair.is_empty():
				continue
			var bits := pair.split("=")
			_args[bits[0]] = bits[1] if bits.size() == 2 else "1"

	for arg in raw:
		if not arg.begins_with("--"):
			continue
		var bits := arg.trim_prefix("--").split("=")
		_args[bits[0]] = bits[1] if bits.size() == 2 else "1"


static func has(key: String) -> bool:
	_parse()
	return _args.has(key)


static func get_int(key: String, fallback: int) -> int:
	_parse()
	if not _args.has(key):
		return fallback
	return int(str(_args[key]).to_int())


## No seed given means a new world every run, and the seed is printed so a
## playtest that finds something odd can be replayed exactly.
static func world_seed() -> int:
	_parse()
	if _args.has("seed"):
		return get_int("seed", 0)
	return int(randi())


static func spawn_x() -> int:
	return get_int("spawn-x", DEFAULT_SPAWN_X)
