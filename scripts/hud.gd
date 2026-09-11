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
var _clock: Label
var _goals: VBoxContainer
var _toast: Label


func _ready() -> void:
	_full = _slice(0)
	_empty = _slice(1)
	message.visible = false
	zone_label.modulate.a = 0.0
	fade.color.a = 0.0
	set_gameplay_visible(false)

	_build_clock()
	_build_goals()

	Game.health_changed.connect(_on_health_changed)
	Game.crystals_changed.connect(_on_crystals_changed)
	Goals.progressed.connect(func(_i: String, _h: int, _n: int) -> void: _redraw_goals())
	Goals.completed.connect(_on_goal_completed)


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


## The next few things worth doing, down the left. Nudges, not a quest log:
## nothing gates on them and nothing is lost by ignoring them.
func _build_goals() -> void:
	_goals = VBoxContainer.new()
	_goals.name = "Goals"
	_goals.offset_left = 8.0
	_goals.offset_top = 22.0
	_goals.offset_right = 200.0
	_goals.add_theme_constant_override("separation", 1)
	$Root.add_child(_goals)

	_toast = Label.new()
	_toast.name = "GoalToast"
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.offset_left = -140.0
	_toast.offset_right = 140.0
	_toast.offset_top = 40.0
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 10)
	_toast.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_toast.add_theme_constant_override("outline_size", 4)
	_toast.modulate.a = 0.0
	$Root.add_child(_toast)
	_redraw_goals()


func _redraw_goals() -> void:
	if _goals == null:
		return
	for child in _goals.get_children():
		child.queue_free()
	for objective: Dictionary in Goals.active():
		var id: String = objective["id"]
		var need: int = Goals.need(objective)
		var have: int = Goals.have(id)
		var row := Label.new()
		row.text = "%s%s" % [objective["text"], ("  %d/%d" % [have, need]) if need > 1 else ""]
		row.add_theme_font_size_override("font_size", 8)
		row.add_theme_color_override("font_color",
			Color(0.98, 0.92, 0.70) if have > 0 else Color(0.72, 0.78, 0.86))
		row.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		row.add_theme_constant_override("outline_size", 3)
		_goals.add_child(row)


func _on_goal_completed(_id: String, text: String) -> void:
	_redraw_goals()
	_toast.text = "%s  ✓" % text
	_toast.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_toast, "modulate:a", 1.0, 0.25)
	tween.tween_interval(1.9)
	tween.tween_property(_toast, "modulate:a", 0.0, 0.6)


## Hearts and the crystal count only belong on screen during a level.
func set_gameplay_visible(shown: bool) -> void:
	$Root/TopLeft.visible = shown
	$Root/TopRight.visible = shown
	if _clock:
		_clock.visible = shown
	if _goals:
		_goals.visible = shown


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
