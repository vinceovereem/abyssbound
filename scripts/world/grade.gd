class_name WorldGrade
extends CanvasLayer
## A colour over everything, by where you are and what time it is.
##
## The first comparison against the target scored 2 for mood and 2 for colour
## for the same reason: nothing was lit. A flat blue midday has no hour in it.
## This is the cheapest thing that puts one there.

const DAWN_DUSK := Color(1.0, 0.58, 0.30)
const NOON := Color(1.0, 0.88, 0.66)
const NIGHT := Color(0.34, 0.44, 0.78)
const CAVERN := Color(0.42, 0.62, 0.95)
const DEEP := Color(0.62, 0.36, 0.92)

var _rect: ColorRect


func _ready() -> void:
	layer = 30   # over the world, under the HUD
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)


func update(depth_tile: int, surface: int, daylight: float) -> void:
	var tint: Color
	var strength: float

	if depth_tile < surface + 30:
		# Golden hour is strongest halfway between dark and light, which is
		# exactly dawn and dusk.
		var warm := 1.0 - absf(daylight * 2.0 - 1.0)
		tint = NIGHT.lerp(NOON, daylight).lerp(DAWN_DUSK, warm * 0.85)
		strength = lerpf(0.16, 0.24, warm) if daylight > 0.05 else 0.20
	elif depth_tile < WorldGen.DEEP_TOP:
		tint = CAVERN
		strength = 0.13
	else:
		tint = DEEP
		strength = 0.17

	_rect.color = Color(tint.r, tint.g, tint.b, strength)
