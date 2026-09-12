class_name ArtManifest
extends RefCounted
## Where art comes from.
##
## Nothing in the code knows a filename. An actor asks for "player" and gets
## whatever `data/art.json` currently points at, sliced into the animations
## that file describes. Replacing a placeholder with real art is an edit to
## that json and nothing else.
##
## If an entry is missing or its file will not load, the actor keeps whatever
## frames its scene already had, so a bad manifest degrades to the old look
## rather than to an invisible character.

const PATH := "res://data/art.json"

static var _sprites := {}
static var _loaded := false
static var _cache := {}


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		push_error("ArtManifest: %s is missing. Add it to the export include_filter." % PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ArtManifest: %s is not the expected shape." % PATH)
		return
	_sprites = parsed.get("sprites", {})


static func has(sprite_name: String) -> bool:
	_load()
	return _sprites.has(sprite_name)


## Built once per name and shared, because every crawler wants the same frames.
static func frames_for(sprite_name: String) -> SpriteFrames:
	_load()
	if _cache.has(sprite_name):
		return _cache[sprite_name]
	if not _sprites.has(sprite_name):
		return null

	var entry: Dictionary = _sprites[sprite_name]
	var texture: Texture2D = load(str(entry["file"]))
	if texture == null:
		push_error("ArtManifest: %s points at %s, which will not load."
			% [sprite_name, entry["file"]])
		return null

	var size := Vector2(int(entry["frame"][0]), int(entry["frame"][1]))
	var frames := SpriteFrames.new()
	frames.remove_animation("default")

	for animation: String in entry.get("animations", {}).keys():
		var spec: Dictionary = entry["animations"][animation]
		frames.add_animation(animation)
		frames.set_animation_speed(animation, float(spec.get("fps", 8)))
		frames.set_animation_loop(animation, bool(spec.get("loop", true)))
		for index: int in spec.get("frames", []):
			var slice := AtlasTexture.new()
			slice.atlas = texture
			slice.region = Rect2(index * size.x, 0, size.x, size.y)
			frames.add_frame(animation, slice)

	_cache[sprite_name] = frames
	return frames


## Point an AnimatedSprite2D at whatever the manifest says. Leaves the scene's
## own frames alone if there is nothing to say.
static func dress(sprite: AnimatedSprite2D, sprite_name: String) -> void:
	var frames := frames_for(sprite_name)
	if frames == null:
		return
	var playing := sprite.animation
	sprite.sprite_frames = frames
	if frames.has_animation(playing):
		sprite.play(playing)


static func reset() -> void:
	_loaded = false
	_sprites.clear()
	_cache.clear()
