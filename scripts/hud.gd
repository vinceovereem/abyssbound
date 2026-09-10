extends CanvasLayer
## Autoloaded as `Ui`. Survives scene changes, so the heads-up display and the
## fade-to-black do not have to be rebuilt in every zone.

const HEART_TEXTURE := preload("res://assets/ui/heart.png")
const HEART_SIZE := Vector2i(9, 8)

@onready var hearts: HBoxContainer = $Root/TopLeft/Hearts
@onready var crystal_label: Label = $Root/TopRight/Crystals/Count
@onready var zone_label: Label = $Root/ZoneTitle
@onready var message: VBoxContainer = $Root/Message
@onready var message_title: Label = $Root/Message/Title
@onready var message_hint: Label = $Root/Message/Hint
@onready var fade: ColorRect = $Fade

var _full: AtlasTexture
var _empty: AtlasTexture


func _ready() -> void:
	_full = _slice(0)
	_empty = _slice(1)
	message.visible = false
	zone_label.modulate.a = 0.0
	fade.color.a = 0.0
	set_gameplay_visible(false)

	Game.health_changed.connect(_on_health_changed)
	Game.crystals_changed.connect(_on_crystals_changed)


func _slice(index: int) -> AtlasTexture:
	var tex := AtlasTexture.new()
	tex.atlas = HEART_TEXTURE
	tex.region = Rect2(index * HEART_SIZE.x, 0, HEART_SIZE.x, HEART_SIZE.y)
	return tex


func _on_health_changed(current: int, maximum: int) -> void:
	for child in hearts.get_children():
		child.queue_free()
	for i in maximum:
		var icon := TextureRect.new()
		icon.texture = _full if i < current else _empty
		icon.custom_minimum_size = HEART_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP
		hearts.add_child(icon)


func _on_crystals_changed(total: int) -> void:
	crystal_label.text = str(total)


## Hearts and the crystal count only belong on screen during a level.
func set_gameplay_visible(shown: bool) -> void:
	$Root/TopLeft.visible = shown
	$Root/TopRight.visible = shown


func announce_zone(title: String) -> void:
	zone_label.text = title.to_upper()
	var tween := create_tween()
	tween.tween_property(zone_label, "modulate:a", 1.0, 0.4)
	tween.tween_interval(1.4)
	tween.tween_property(zone_label, "modulate:a", 0.0, 0.6)


func show_message(title: String, hint: String) -> void:
	message_title.text = title
	message_hint.text = hint
	message.visible = true


func hide_message() -> void:
	message.visible = false


func fade_out(duration := 0.25) -> void:
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 1.0, duration)
	await tween.finished


func fade_in(duration := 0.35) -> void:
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 0.0, duration)
	await tween.finished
