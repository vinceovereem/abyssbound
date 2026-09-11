extends CanvasLayer
## The hotbar, the backpack and the crafting list.
##
## Lives with the world rather than on the HUD autoload, because none of it
## means anything outside a world. Keyboard driven like everything else:
##
##   1 to 0   pick a hotbar slot          Q  next slot
##   I        open the backpack           C  open the crafting list
##   1 to 9   while crafting is open, make that recipe

const TILE_SHEET := preload("res://assets/tiles/tiles.png")
const ITEM_SHEET := preload("res://assets/sprites/items.png")
const SLOT := 20

var world: Node2D

var _items: ItemDB
var _tiles: TileDB
var _book: RecipeBook

var _hotbar: HBoxContainer
var _bag: PanelContainer
var _bag_grid: GridContainer
var _craft: PanelContainer
var _craft_rows: VBoxContainer
var _available: Array[int] = []


func _ready() -> void:
	layer = 50
	_items = ItemDB.get_db()
	_tiles = TileDB.get_db()
	_book = RecipeBook.get_book()

	_build_hotbar()
	_build_bag()
	_build_craft()

	Game.inventory.changed.connect(_refresh)
	_refresh()


# ---------------------------------------------------------------------------
# Icons
# ---------------------------------------------------------------------------
func icon_for(id: String) -> Texture2D:
	if id.is_empty():
		return null
	var tex := AtlasTexture.new()
	var tile := _items.tile_of(id)
	if not tile.is_empty():
		tex.atlas = TILE_SHEET
		tex.region = Rect2(_tiles.id(tile) * 16, 0, 16, 16)
		return tex
	if _items.of(id).has("icon"):
		tex.atlas = ITEM_SHEET
		tex.region = Rect2(int(_items.of(id)["icon"]) * 16, 0, 16, 16)
		return tex
	return null


func _make_slot() -> Panel:
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(SLOT, SLOT)

	var art := TextureRect.new()
	art.name = "Art"
	art.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(art)

	var count := Label.new()
	count.name = "Count"
	count.set_anchors_preset(Control.PRESET_FULL_RECT)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count.add_theme_font_size_override("font_size", 8)
	count.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	count.add_theme_constant_override("outline_size", 3)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(count)
	return slot


func _style(selected: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.06, 0.07, 0.11, 0.82)
	box.border_color = Color(1.0, 0.86, 0.5) if selected else Color(0.36, 0.40, 0.5)
	box.set_border_width_all(1)
	return box


func _fill_slot(slot: Panel, index: int, selected: bool) -> void:
	var inv := Game.inventory
	var id: String = "" if inv.is_empty_slot(index) else inv.ids[index]
	slot.add_theme_stylebox_override("panel", _style(selected))
	(slot.get_node("Art") as TextureRect).texture = icon_for(id)
	var count := slot.get_node("Count") as Label
	count.text = str(inv.counts[index]) if inv.counts[index] > 1 else ""


# ---------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------
func _build_hotbar() -> void:
	_hotbar = HBoxContainer.new()
	_hotbar.name = "Hotbar"
	_hotbar.add_theme_constant_override("separation", 2)
	_hotbar.anchor_left = 0.5
	_hotbar.anchor_right = 0.5
	_hotbar.anchor_top = 1.0
	_hotbar.anchor_bottom = 1.0
	_hotbar.offset_left = -(Inventory.HOTBAR * (SLOT + 2)) / 2.0
	_hotbar.offset_top = -(SLOT + 6)
	add_child(_hotbar)
	for i in Inventory.HOTBAR:
		_hotbar.add_child(_make_slot())


func _framed(title: String, body: Control, width: float, height: float) -> PanelContainer:
	var frame := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.06, 0.10, 0.94)
	box.border_color = Color(0.40, 0.45, 0.56)
	box.set_border_width_all(1)
	box.set_content_margin_all(6)
	frame.add_theme_stylebox_override("panel", box)
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.anchor_top = 0.5
	frame.anchor_bottom = 0.5
	frame.offset_left = -width / 2.0
	frame.offset_right = width / 2.0
	frame.offset_top = -height / 2.0
	frame.offset_bottom = height / 2.0
	frame.visible = false

	var column := VBoxContainer.new()
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 9)
	heading.add_theme_color_override("font_color", Color(0.95, 0.90, 0.72))
	column.add_child(heading)
	column.add_child(body)
	frame.add_child(column)
	add_child(frame)
	return frame


func _build_bag() -> void:
	_bag_grid = GridContainer.new()
	_bag_grid.columns = Inventory.HOTBAR
	_bag_grid.add_theme_constant_override("h_separation", 2)
	_bag_grid.add_theme_constant_override("v_separation", 2)
	for i in Inventory.SLOTS:
		_bag_grid.add_child(_make_slot())
	_bag = _framed("CARRYING   (I to close)", _bag_grid, 240, 106)


func _build_craft() -> void:
	_craft_rows = VBoxContainer.new()
	_craft_rows.add_theme_constant_override("separation", 1)
	_craft = _framed("CRAFTING   (C to close, number to make)", _craft_rows, 250, 120)


# ---------------------------------------------------------------------------
# Input and refresh
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		_bag.visible = not _bag.visible
		_craft.visible = false
		_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("craft"):
		_craft.visible = not _craft.visible
		_bag.visible = false
		_refresh()
		get_viewport().set_input_as_handled()
	elif _craft.visible:
		# While the list is open the number keys make things instead of
		# choosing a hotbar slot.
		for i in mini(9, _available.size()):
			if event.is_action_pressed("hotbar_%d" % (i + 1)):
				_make(_available[i])
				get_viewport().set_input_as_handled()
				return


func _make(index: int) -> void:
	var stations: Dictionary = world.mining.stations_in_reach() if world else {}
	if not _book.make(index, Game.inventory, stations):
		return
	var recipe: Dictionary = _book.recipes[index]
	Goals.note_crafted(str(recipe["out"]), int(recipe.get("count", 1)))
	if world:
		world.float_text(world.player.global_position - Vector2(0, 22),
			"made %s" % _items.display_name(str(recipe["out"])), Color(0.75, 1.0, 0.8), 20.0)
	_refresh()


func _refresh() -> void:
	for i in Inventory.HOTBAR:
		_fill_slot(_hotbar.get_child(i), i, i == Game.inventory.selected)
	if _bag.visible:
		for i in Inventory.SLOTS:
			_fill_slot(_bag_grid.get_child(i), i, i == Game.inventory.selected)
	if _craft.visible:
		_refresh_craft()


func _refresh_craft() -> void:
	for child in _craft_rows.get_children():
		child.queue_free()
	var stations: Dictionary = world.mining.stations_in_reach() if world else {}
	_available = _book.available(Game.inventory, stations)

	if _available.is_empty():
		_craft_rows.add_child(_hint("Nothing can be made yet. Gather wood, or stand by a station."))
		return

	for i in mini(9, _available.size()):
		var recipe: Dictionary = _book.recipes[_available[i]]
		var needs: Array = []
		for id: String in recipe["needs"].keys():
			needs.append("%s %d" % [_items.display_name(id), int(recipe["needs"][id])])
		var row := Label.new()
		row.text = "%d.  %s x%d      %s" % [i + 1, _items.display_name(str(recipe["out"])),
			int(recipe.get("count", 1)), ", ".join(needs)]
		row.add_theme_font_size_override("font_size", 8)
		row.add_theme_color_override("font_color", Color(0.88, 0.93, 1.0))
		_craft_rows.add_child(row)


func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color(0.68, 0.74, 0.84))
	return label
