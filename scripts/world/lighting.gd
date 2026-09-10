class_name Lighting
extends Node2D
## Terraria-style light: bright under open sky, dark underground, torches make
## a difference.
##
## How it works, and why this way. Light lives on a fixed size window of tiles
## around the player rather than on the whole world, because the whole world is
## 1.6 million tiles and almost none of it is on screen. Inside that window the
## spread is four directional sweeps rather than a queue: a queue is the
## textbook answer but allocating and draining one in GDScript every recompute
## costs more than sweeping a flat array twice.
##
## The result is drawn as one texel per tile, scaled up with linear filtering,
## which is what turns 16 px steps into a smooth falloff for free.

const REGION_W := 112
const REGION_H := 72
## How far the player may move before the window is rebuilt around them.
const MARGIN := 16

const SKY := 255
const AIR_FALLOFF := 16
const MIN_SOLID_FALLOFF := 40
## Never fully black, or a dark cave becomes an unreadable void.
const MAX_DARKNESS := 0.88
## The floor under every tile's light. Without it, going underground with no
## torch shows a completely black screen, which reads as a broken renderer
## rather than as darkness. Enough to make out the shape of the rock, not
## enough to make a torch pointless.
const AMBIENT := 45

var store: ChunkStore

var _light := PackedByteArray()
var _fall := PackedByteArray()
var _solid := PackedByteArray()
var _pixels := PackedByteArray()
var _origin := Vector2i(-99999, -99999)
var _image: Image
var _texture: ImageTexture
var _sprite: Sprite2D
var _db: TileDB
var _dirty := true
var last_ms := 0.0


func setup(chunk_store: ChunkStore) -> void:
	store = chunk_store
	_db = TileDB.get_db()
	_light.resize(REGION_W * REGION_H)
	_fall.resize(REGION_W * REGION_H)
	_solid.resize(REGION_W * REGION_H)
	_pixels.resize(REGION_W * REGION_H * 4)

	_image = Image.create_empty(REGION_W, REGION_H, false, Image.FORMAT_RGBA8)
	_texture = ImageTexture.create_from_image(_image)

	_sprite = Sprite2D.new()
	_sprite.name = "Darkness"
	_sprite.texture = _texture
	_sprite.centered = false
	_sprite.scale = Vector2(16, 16)
	# Linear so the per-tile values blend instead of showing as 16 px squares.
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_sprite.z_index = 20
	add_child(_sprite)


func mark_dirty() -> void:
	_dirty = true


## Called with the player's tile. Rebuilds only when the window has drifted
## too far or a tile changed.
func update(centre: Vector2i) -> void:
	var wanted := Vector2i(centre.x - REGION_W / 2, centre.y - REGION_H / 2)
	if not _dirty and absi(wanted.x - _origin.x) < MARGIN and absi(wanted.y - _origin.y) < MARGIN:
		return
	_origin = wanted
	_dirty = false
	_recompute()


func light_at(x: int, y: int) -> int:
	var lx := x - _origin.x
	var ly := y - _origin.y
	if lx < 0 or ly < 0 or lx >= REGION_W or ly >= REGION_H:
		return 0
	return _light[ly * REGION_W + lx]


func _recompute() -> void:
	var start := Time.get_ticks_usec()

	# Read every tile once into flat arrays. The sweeps below touch each tile
	# eight times, and going back to the chunk store for all of that was the
	# single most expensive thing this function did: 30 ms became 4.
	var n := REGION_W * REGION_H
	for ly in REGION_H:
		var wy := _origin.y + ly
		var row := ly * REGION_W
		for lx in REGION_W:
			var id := store.get_fg(_origin.x + lx, wy)
			var i := row + lx
			_solid[i] = 1 if _db.is_solid(id) else 0
			_fall[i] = maxi(MIN_SOLID_FALLOFF, int(_db.opacity[id])) if _solid[i] == 1 else AIR_FALLOFF
			_light[i] = int(_db.emit[id]) if id > 0 else 0

	# Pass 1: sunlight straight down each column, undimmed through air and
	# dying inside rock.
	for lx in REGION_W:
		var wx := _origin.x + lx
		var sky := 0
		if _origin.y <= store.gen.surface_height(wx) and not store.gen.in_shaft(wx, _origin.y):
			sky = SKY
		for ly in REGION_H:
			var i := ly * REGION_W + lx
			if _solid[i] == 1:
				sky = maxi(0, sky - _fall[i])
			if sky > _light[i]:
				_light[i] = sky

	# Pass 2: spread into the places sunlight cannot reach. Two rounds of four
	# sweeps is enough for a torch to fill a room.
	for round in 2:
		_sweep_x(1)
		_sweep_x(-1)
		_sweep_y(1)
		_sweep_y(-1)

	for i in n:
		if _light[i] < AMBIENT:
			_light[i] = AMBIENT

	_write_image()
	last_ms = float(Time.get_ticks_usec() - start) / 1000.0


func _sweep_x(dir: int) -> void:
	for ly in REGION_H:
		var row := ly * REGION_W
		var xs: Array = range(1, REGION_W) if dir > 0 else range(REGION_W - 2, -1, -1)
		for lx: int in xs:
			var i := row + lx
			var value: int = _light[i - dir] - _fall[i]
			if value > _light[i]:
				_light[i] = value


func _sweep_y(dir: int) -> void:
	var ys: Array = range(1, REGION_H) if dir > 0 else range(REGION_H - 2, -1, -1)
	for ly: int in ys:
		var row := ly * REGION_W
		var prev_row := (ly - dir) * REGION_W
		for lx in REGION_W:
			var i := row + lx
			var value: int = _light[prev_row + lx] - _fall[i]
			if value > _light[i]:
				_light[i] = value


func _write_image() -> void:
	# Writing the bytes straight into the buffer rather than calling set_pixel
	# per texel. Same result, a fraction of the cost.
	var n := REGION_W * REGION_H
	for i in n:
		_pixels[i * 4 + 3] = int((255 - _light[i]) * MAX_DARKNESS)
	_image.set_data(REGION_W, REGION_H, false, Image.FORMAT_RGBA8, _pixels)
	_texture.update(_image)
	_sprite.position = Vector2(_origin.x * 16, _origin.y * 16)
