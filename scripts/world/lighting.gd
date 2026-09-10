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

## Full daylight. Scaled down at night so the surface goes dark and a torch
## becomes the difference between seeing and not.
const SKY := 255
## What the sun is currently worth. Set from the clock.
var sky_light := SKY
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
# Per tile id lookups, built once. The read loop runs 8000 times a pass and a
# method call per tile in there is not free.
var _lut_solid := PackedByteArray()
var _lut_fall := PackedByteArray()
var _lut_emit := PackedByteArray()
var _origin := Vector2i(-99999, -99999)
var _image: Image
var _texture: ImageTexture
var _sprite: Sprite2D
var _db: TileDB
var _dirty := true
var last_ms := 0.0
## A pass is split across two frames. Compiled to wasm the whole thing costs
## about 26 ms, which is a dropped frame every time the window drifts or a tile
## is dug. Half of it comfortably fits instead, and light arriving a frame late
## is not something anyone can see.
var _phase := 0
var last_phase_ms := 0.0
var _pass_ms := 0.0


func setup(chunk_store: ChunkStore) -> void:
	store = chunk_store
	_db = TileDB.get_db()
	_light.resize(REGION_W * REGION_H)
	_fall.resize(REGION_W * REGION_H)
	_solid.resize(REGION_W * REGION_H)
	_pixels.resize(REGION_W * REGION_H * 4)

	var ids := _db.max_id + 1
	_lut_solid.resize(ids)
	_lut_fall.resize(ids)
	_lut_emit.resize(ids)
	for id in ids:
		var solid := _db.is_solid(id)
		_lut_solid[id] = 1 if solid else 0
		_lut_fall[id] = maxi(MIN_SOLID_FALLOFF, int(_db.opacity[id])) if solid else AIR_FALLOFF
		_lut_emit[id] = int(_db.emit[id])

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
	if _phase == 0 and not _dirty \
			and absi(wanted.x - _origin.x) < MARGIN and absi(wanted.y - _origin.y) < MARGIN:
		return
	if _phase == 0:
		_origin = wanted
		_dirty = false
		_phase = 1

	# Four steps, not two. The sweeps are most of the cost, so splitting them
	# from the read is not enough on its own: one round of sweeps alone is
	# still a dropped frame in wasm.
	var start := Time.get_ticks_usec()
	match _phase:
		1:
			_read_tiles()
			_sunlight()
			_phase = 2
		2:
			_sweep_round()
			_phase = 3
		3:
			_sweep_round()
			_phase = 4
		_:
			_apply_ambient()
			_write_image()
			_phase = 0
	last_phase_ms = float(Time.get_ticks_usec() - start) / 1000.0
	_pass_ms += last_phase_ms
	if _phase == 0:
		last_ms = _pass_ms
		_pass_ms = 0.0


## True when no pass is part way through. Playtests wait on this.
func is_idle() -> bool:
	return _phase == 0


func light_at(x: int, y: int) -> int:
	var lx := x - _origin.x
	var ly := y - _origin.y
	if lx < 0 or ly < 0 or lx >= REGION_W or ly >= REGION_H:
		return 0
	return _light[ly * REGION_W + lx]


## The whole pass at once. Tests and playtests want the answer immediately
## rather than on the next frame.
func update_now(centre: Vector2i) -> void:
	_origin = Vector2i(centre.x - REGION_W / 2, centre.y - REGION_H / 2)
	_dirty = false
	_phase = 0
	var start := Time.get_ticks_usec()
	_read_tiles()
	_sunlight()
	_spread()
	_write_image()
	last_ms = float(Time.get_ticks_usec() - start) / 1000.0


## Two rounds of four sweeps is enough for a torch to fill a room.
func _spread() -> void:
	_sweep_round()
	_sweep_round()
	_apply_ambient()


func _sweep_round() -> void:
	_sweep_x(1)
	_sweep_x(-1)
	_sweep_y(1)
	_sweep_y(-1)


func _apply_ambient() -> void:
	var n := REGION_W * REGION_H
	for i in n:
		if _light[i] < AMBIENT:
			_light[i] = AMBIENT


## Copy the window's tiles into flat arrays.
##
## Reads run along a row, and a row crosses a chunk boundary only every 32
## tiles, so the chunk is looked up once per run and the tiles inside it are
## read straight out of its byte array. Going through ChunkStore.get_fg for
## every tile meant a bounds check and a dictionary lookup 8000 times a pass.
func _read_tiles() -> void:
	for ly in REGION_H:
		var wy := _origin.y + ly
		var row := ly * REGION_W
		if wy < 0 or wy >= WorldGen.HEIGHT:
			for lx in REGION_W:
				_solid[row + lx] = 0
				_fall[row + lx] = AIR_FALLOFF
				_light[row + lx] = 0
			continue

		var cy := wy >> 5
		var row_in_chunk := (wy & 31) * Chunk.SIZE
		var lx := 0
		while lx < REGION_W:
			var wx := _origin.x + lx
			if wx < 0 or wx >= WorldGen.WIDTH:
				# Off the edge of the map is rock, so light cannot leak in.
				_solid[row + lx] = 1
				_fall[row + lx] = 255
				_light[row + lx] = 0
				lx += 1
				continue
			var lx_in := wx & 31
			var run: int = mini(Chunk.SIZE - lx_in, REGION_W - lx)
			var chunk := store.get_chunk(wx >> 5, cy)
			var base := row_in_chunk + lx_in
			var fg := chunk.fg
			for k in run:
				var id: int = fg[base + k]
				var i := row + lx + k
				_solid[i] = _lut_solid[id]
				_fall[i] = _lut_fall[id]
				_light[i] = _lut_emit[id]
			lx += run


## Sunlight straight down each column: undimmed through air, dying in rock.
func _sunlight() -> void:
	for lx in REGION_W:
		var wx := _origin.x + lx
		var sky := 0
		if _origin.y <= store.gen.surface_height(wx) and not store.gen.in_shaft(wx, _origin.y):
			sky = sky_light
		var i := lx
		for ly in REGION_H:
			if _solid[i] == 1:
				sky = maxi(0, sky - _fall[i])
			if sky > _light[i]:
				_light[i] = sky
			i += REGION_W


# The sweeps are written as while loops on purpose. `for x in range(a, b, s)`
# with the range stored in a variable allocates an Array per row per sweep,
# which is 576 throwaway arrays every recompute.
func _sweep_x(dir: int) -> void:
	for ly in REGION_H:
		var row := ly * REGION_W
		var lx := 1 if dir > 0 else REGION_W - 2
		var stop := REGION_W if dir > 0 else -1
		while lx != stop:
			var i := row + lx
			var value: int = _light[i - dir] - _fall[i]
			if value > _light[i]:
				_light[i] = value
			lx += dir


func _sweep_y(dir: int) -> void:
	var ly := 1 if dir > 0 else REGION_H - 2
	var stop := REGION_H if dir > 0 else -1
	while ly != stop:
		var row := ly * REGION_W
		var prev_row := (ly - dir) * REGION_W
		for lx in REGION_W:
			var i := row + lx
			var value: int = _light[prev_row + lx] - _fall[i]
			if value > _light[i]:
				_light[i] = value
		ly += dir


func _write_image() -> void:
	# Writing the bytes straight into the buffer rather than calling set_pixel
	# per texel. Same result, a fraction of the cost.
	var n := REGION_W * REGION_H
	for i in n:
		_pixels[i * 4 + 3] = int((255 - _light[i]) * MAX_DARKNESS)
	_image.set_data(REGION_W, REGION_H, false, Image.FORMAT_RGBA8, _pixels)
	_texture.update(_image)
	_sprite.position = Vector2(_origin.x * 16, _origin.y * 16)
