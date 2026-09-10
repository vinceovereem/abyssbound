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
var _resources: VBoxContainer
var _clock: Label


func _ready() -> void:
	_full = _slice(0)
	_empty = _slice(1)
	message.visible = false
	zone_label.modulate.a = 0.0
	fade.color.a = 0.0
	set_gameplay_visible(false)

	_build_resource_list()
	_build_clock()

	Game.health_changed.connect(_on_health_changed)
	Game.crystals_changed.connect(_on_crystals_changed)
	Game.resource_collected.connect(_on_resource_collected)


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


## What breaking blocks has given you, down the right hand side.
func _build_resource_list() -> void:
	_resources = VBoxContainer.new()
	_resources.name = "Resources"
	_resources.anchor_left = 1.0
	_resources.anchor_right = 1.0
	_resources.offset_left = -118.0
	_resources.offset_right = -6.0
	_resources.offset_top = 22.0
	_resources.add_theme_constant_override("separation", 1)
	$Root.add_child(_resources)


## The time, top centre. Knowing dusk is coming is the whole point of having a
## clock, and it cannot live only behind a debug key.
func _build_clock() -> void:
	_clock = Label.new()
	_clock.name = "Clock"
	_clock.anchor_left = 0.5
	_clock.anchor_right = 0.5
	_clock.offset_left = -40.0
	_clock.offset_right = 40.0
	_clock.offset_top = 4.0
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock.add_theme_font_size_override("font_size", 8)
	_clock.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_clock.add_theme_constant_override("outline_size", 3)
	$Root.add_child(_clock)


func _process(_delta: float) -> void:
	if _clock == null or not _clock.visible:
		return
	_clock.text = DayClock.clock_text()
	# Cold at night, warm in the day, so a glance at the colour is enough.
	_clock.add_theme_color_override("font_color",
		Color(0.62, 0.70, 0.95) if DayClock.is_night() else Color(1.0, 0.93, 0.72))


func _on_resource_collected(_resource: String, _amount: int, _total: int) -> void:
	for child in _resources.get_children():
		child.queue_free()
	var names: Array = Game.resources.keys()
	names.sort()
	for resource: String in names:
		var row := Label.new()
		row.text = "%s  %d" % [TileDB.pretty(resource), int(Game.resources[resource])]
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_theme_font_size_override("font_size", 8)
		row.add_theme_color_override("font_color", Color(0.86, 0.91, 1.0))
		row.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		row.add_theme_constant_override("outline_size", 3)
		_resources.add_child(row)


## Hearts and the crystal count only belong on screen during a level.
func set_gameplay_visible(shown: bool) -> void:
	$Root/TopLeft.visible = shown
	$Root/TopRight.visible = shown
	if _resources:
		_resources.visible = shown
	if _clock:
		_clock.visible = shown


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
