class_name Chunk
extends RefCounted
## One 32x32 square of the world.
##
## Four byte arrays rather than four objects per tile. A chunk is 4 KB, so the
## whole 2000x800 world is under 7 MB and can stay resident. What streams is
## the rendering and the physics, not the data.

const SIZE := 32
const AREA := SIZE * SIZE

var cx := 0
var cy := 0

var fg := PackedByteArray()      ## foreground tile id, 0 is air
var bg := PackedByteArray()      ## background wall id, 0 is none
var water := PackedByteArray()   ## 0 to 8, how full the tile is
var light := PackedByteArray()   ## 0 to 255

var generated := false
var dirty_render := true
var dirty_light := true

## Local index -> true for every tile the player changed. This is all that
## gets written to a save; the rest is regenerated from the seed.
var edited := {}


func _init(chunk_x: int = 0, chunk_y: int = 0) -> void:
	cx = chunk_x
	cy = chunk_y
	fg.resize(AREA)
	bg.resize(AREA)
	water.resize(AREA)
	light.resize(AREA)


static func index(lx: int, ly: int) -> int:
	return ly * SIZE + lx


func get_fg(lx: int, ly: int) -> int:
	return fg[ly * SIZE + lx]


func set_fg(lx: int, ly: int, id: int, record_edit: bool = true) -> void:
	var i := ly * SIZE + lx
	if fg[i] == id:
		return
	fg[i] = id
	if record_edit:
		edited[i] = true
	dirty_render = true
	dirty_light = true
