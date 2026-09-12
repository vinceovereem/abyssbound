class_name WorldParallax
extends CanvasLayer
## Layers of distance behind the world.
##
## Four per zone, scrolling at different rates: a far ridge that barely moves,
## mid hills, a near treeline, and a sheet of fog or haze over the lot. Depth is
## the single biggest thing the flat backdrop was missing.
##
## It sits in front of the sky gradient and behind everything else, and fades
## out as you go underground, where the rock is the backdrop.

const WIDTH := 640.0
const HEIGHT := 360.0

## Back to front. The fog moves least because haze hangs in the air rather than
## sitting at a distance.
const SLOTS := [
	{ "suffix": "far",  "factor": 0.06, "drift": 0.02 },
	{ "suffix": "mid",  "factor": 0.14, "drift": 0.05 },
	{ "suffix": "near", "factor": 0.28, "drift": 0.10 },
	{ "suffix": "fog",  "factor": 0.04, "drift": 0.01 },
]

## Which set of layers belongs to which depth.
const ZONES := [
	{ "name": "surface", "until": 170 },
	{ "name": "cavern",  "until": 460 },
	{ "name": "abyss",   "until": 100000 },
]

var _rects: Array[TextureRect] = []
var _zone := ""


func _ready() -> void:
	layer = -95
	for slot: Dictionary in SLOTS:
		var rect := TextureRect.new()
		rect.name = str(slot["suffix"])
		# Twice the screen wide and tiled, so scrolling can wrap without a seam.
		rect.size = Vector2(WIDTH * 2.0, HEIGHT)
		rect.stretch_mode = TextureRect.STRETCH_TILE
		rect.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rect)
		_rects.append(rect)


func _zone_for(depth_tile: int) -> String:
	for zone: Dictionary in ZONES:
		if depth_tile < int(zone["until"]):
			return str(zone["name"])
	return "abyss"


func _use(zone: String) -> void:
	if zone == _zone:
		return
	_zone = zone
	for i in SLOTS.size():
		var path := "res://assets/generated/bg/%s_%s.png" % [zone, SLOTS[i]["suffix"]]
		_rects[i].texture = load(path) if ResourceLoader.exists(path) else null


## camera_centre is where the view is looking, in world pixels.
func update(camera_centre: Vector2, depth_tile: int, daylight: float) -> void:
	_use(_zone_for(depth_tile))

	# Underground the rock is the backdrop; the layers have nothing to say.
	var underground := clampf(1.0 - float(depth_tile - 150) / 90.0, 0.0, 1.0)
	var lit: float = lerpf(0.35, 1.0, daylight) if _zone == "surface" else 1.0
	var visible_amount: float = maxf(underground, 0.55 if _zone != "surface" else 0.0)

	for i in SLOTS.size():
		var slot: Dictionary = SLOTS[i]
		var rect := _rects[i]
		# Wrapped by the layer's own width so it never runs out of picture.
		rect.position = Vector2(
			-fposmod(camera_centre.x * float(slot["factor"]), WIDTH),
			-fposmod(camera_centre.y * float(slot["drift"]), HEIGHT) * 0.25)
		rect.modulate = Color(lit, lit, lit, visible_amount)
