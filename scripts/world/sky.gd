class_name WorldSky
extends CanvasLayer
## The backdrop behind the world.
##
## Without this everything reads as a cave, because the clear colour is nearly
## black and the surface has nothing behind it. The gradient follows depth:
## daylight at the top, dark underground, and a colder dark down the Abyss.

const DAY_TOP := Color(0.29, 0.51, 0.76)
const DAY_BOTTOM := Color(0.65, 0.79, 0.89)
const DEEP_TOP := Color(0.04, 0.05, 0.08)
const DEEP_BOTTOM := Color(0.07, 0.08, 0.12)
const ABYSS_TOP_C := Color(0.06, 0.03, 0.10)
const ABYSS_BOTTOM_C := Color(0.10, 0.05, 0.16)

var _rect: TextureRect
var _gradient: Gradient
var _texture: GradientTexture2D


func _ready() -> void:
	layer = -100

	_gradient = Gradient.new()
	_gradient.set_color(0, DAY_TOP)
	_gradient.set_color(1, DAY_BOTTOM)

	_texture = GradientTexture2D.new()
	_texture.gradient = _gradient
	_texture.fill_from = Vector2(0, 0)
	_texture.fill_to = Vector2(0, 1)
	_texture.width = 8
	_texture.height = 256

	_rect = TextureRect.new()
	_rect.texture = _texture
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


## depth_tile is the player's tile y. The bands match the world's layers so the
## backdrop changes at the same places the tiles do.
func update_for_depth(depth_tile: int) -> void:
	var top: Color
	var bottom: Color
	if depth_tile < 140:
		top = DAY_TOP
		bottom = DAY_BOTTOM
	elif depth_tile < WorldGen.ABYSS_TOP:
		var t := clampf(float(depth_tile - 140) / 120.0, 0.0, 1.0)
		top = DAY_TOP.lerp(DEEP_TOP, t)
		bottom = DAY_BOTTOM.lerp(DEEP_BOTTOM, t)
	else:
		var t := clampf(float(depth_tile - WorldGen.ABYSS_TOP) / 240.0, 0.0, 1.0)
		top = DEEP_TOP.lerp(ABYSS_TOP_C, t)
		bottom = DEEP_BOTTOM.lerp(ABYSS_BOTTOM_C, t)
	_gradient.set_color(0, top)
	_gradient.set_color(1, bottom)
