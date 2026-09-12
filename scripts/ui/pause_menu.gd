extends CanvasLayer
## Escape. Resume, the keys, save, quit.
##
## Escape used to quit the game on the spot, with no warning and no save, which
## is the worst thing a key can do. Now it opens this.

signal resumed

const KEYS := [
	["A / D", "Walk"],
	["Space / W", "Jump. Hold for higher"],
	["F", "Dig the tile you are aiming at"],
	["G", "Place what you are holding, or wear armour"],
	["Direction + F or G", "Aim: any of the eight around you"],
	["X", "Swing"],
	["E", "Open a chest you are standing by"],
	["1 to 0, or Q", "Choose a hotbar slot"],
	["C", "Crafting. Numbers make things while it is open"],
	["I", "Backpack and what you are wearing"],
	["F3", "Seed, position, time, frame rate"],
	["Esc", "This menu"],
]

var world: Node2D

var _panel: PanelContainer
var _status: Label
var _open := false


func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS   # runs while the tree is paused
	_build()


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.05, 0.66)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	_panel = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.06, 0.10, 0.96)
	box.border_color = Color(0.78, 0.68, 0.48)
	box.set_border_width_all(1)
	box.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", box)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -170.0
	_panel.offset_right = 170.0
	_panel.offset_top = -140.0
	_panel.offset_bottom = 140.0
	add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	_panel.add_child(column)
	column.add_child(_line("PAUSED", 12, Color(1.0, 0.88, 0.62)))
	column.add_child(_line("", 4, Color.WHITE))

	for pair: Array in KEYS:
		var row := HBoxContainer.new()
		var key := _line(str(pair[0]), 8, Color(1.0, 0.90, 0.68))
		key.custom_minimum_size = Vector2(110, 0)
		row.add_child(key)
		row.add_child(_line(str(pair[1]), 8, Color(0.80, 0.86, 0.94)))
		column.add_child(row)

	column.add_child(_line("", 4, Color.WHITE))
	column.add_child(_line("Esc resume     S save     Q quit", 9, Color(0.95, 0.90, 0.72)))
	_status = _line("", 8, Color(0.70, 1.0, 0.78))
	column.add_child(_status)

	visible = false


func _line(text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	return label


func open() -> void:
	_open = true
	visible = true
	_status.text = ""
	get_tree().paused = true


func close() -> void:
	_open = false
	visible = false
	get_tree().paused = false
	resumed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _open:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
		return
	if not _open:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_S:
				_save()
				get_viewport().set_input_as_handled()
			KEY_Q:
				get_tree().paused = false
				get_tree().quit()


func _save() -> void:
	if world == null or world.player == null:
		return
	var ok := WorldSave.save_world(world.store, world.player.global_position)
	_status.text = "Saved. It will be here when you come back." if ok \
		else "Could not save."
