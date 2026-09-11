class_name WorldSave
extends RefCounted
## Saving a world means saving the seed and the tiles the player changed.
##
## The world is 1.6 million tiles and all but a handful of them are a pure
## function of the seed, so writing them all out would be storing the same
## information twice. A freshly generated world saves in a few hundred bytes.

const PATH := "user://world.save"
const VERSION := 1


static func save_world(store: ChunkStore, player_position: Vector2) -> bool:
	var edits := {}
	for key: Vector2i in store.chunks.keys():
		var chunk: Chunk = store.chunks[key]
		if chunk.edited.is_empty():
			continue
		var per_chunk := {}
		for index: int in chunk.edited.keys():
			per_chunk[index] = chunk.fg[index]
		edits[key] = per_chunk

	# Edits made to chunks that have since been asked for again still count.
	for key: Vector2i in store.pending_edits.keys():
		if not edits.has(key):
			edits[key] = store.pending_edits[key]

	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not write %s" % PATH)
		return false
	file.store_var({
		"version": VERSION,
		"seed": store.world_seed(),
		"player": player_position,
		"edits": edits,
		"inventory": Game.inventory.to_save(),
	}, true)
	file.close()
	return true


static func has_save() -> bool:
	return FileAccess.file_exists(PATH)


## Returns null when there is nothing to load or the file is from a version
## this build does not understand.
static func load_world() -> Dictionary:
	if not has_save():
		return {}
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return {}
	var data: Variant = file.get_var(true)
	file.close()
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != VERSION:
		push_warning("Ignoring a save from another version.")
		return {}

	var store := ChunkStore.new(int(data["seed"]))
	store.pending_edits = data.get("edits", {})
	if data.has("inventory"):
		Game.inventory.from_save(data["inventory"])
	return {
		"store": store,
		"player": data.get("player", Vector2.ZERO),
	}


static func clear() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
