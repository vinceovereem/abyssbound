extends Node2D
## Builds a zone from a plain text map in res://levels/.
##
## Text maps were chosen over editor-painted tilemaps on purpose: they are
## readable in a pull request, trivial to hand-edit, and easy for a tool (or an
## AI) to generate. When the game outgrows this, swap `_build` for a real
## TileMapLayer authored in the editor. Nothing else has to change.
##
## Legend
##   #  solid ground          =  one-way platform
##   :  background stone      *  crystal-veined rock (solid)
##   ^  hazard                .  empty
##   @  player spawn          c  crystal pickup
##   x  crawler               w  critter
##   v  descent to next zone

const TILE := 16
const SOURCE_ID := 0

const ATLAS := {
	"#": Vector2i(0, 0),   # grass ledge
	"1": Vector2i(1, 0),   # stone fill
	"=": Vector2i(2, 0),   # one-way platform
	":": Vector2i(3, 0),   # background stone
	"*": Vector2i(4, 0),   # crystal rock
	"^": Vector2i(5, 0),   # hazard rock
}

@export_file("*.txt") var map_file: String = ""
@export var backdrop: Texture2D
## Which tile the '#' ground-top symbol uses. Grass on the surface, bare rock
## once you are underground.
@export var ledge_tile := Vector2i(0, 0)
## Tints both tile layers. Deeper zones get colder and darker.
@export var tint := Color.WHITE
@export_file("*.tscn") var next_zone: String = ""
@export var next_zone_name: String = "Caverns"
@export var zone_title: String = "Surface"

const PlayerScene := preload("res://scenes/actors/player.tscn")
const CrawlerScene := preload("res://scenes/actors/crawler.tscn")
const CritterScene := preload("res://scenes/actors/critter.tscn")
const CrystalScene := preload("res://scenes/pickups/crystal.tscn")
const HazardScene := preload("res://scenes/pickups/hazard.tscn")
const DescentScene := preload("res://scenes/pickups/descent.tscn")

@onready var tiles: TileMapLayer = $Tiles
@onready var background: TileMapLayer = $Background
@onready var entities: Node2D = $Entities
@onready var backdrop_layer: CanvasLayer = $Backdrop
@onready var backdrop_rect: TextureRect = $Backdrop/Texture

var player: Node2D = null

var _camera: Camera2D = null
var _spawn_point := Vector2.ZERO
var _width := 0
var _height := 0


func _ready() -> void:
	if backdrop:
		backdrop_rect.texture = backdrop
	tiles.modulate = tint
	background.modulate = tint
	_build(_read_map())
	_frame_camera()
	Game.zone_name = zone_title
	Ui.set_gameplay_visible(true)
	Ui.announce_zone(zone_title)


func _read_map() -> PackedStringArray:
	if map_file.is_empty() or not FileAccess.file_exists(map_file):
		push_error("Level %s has no map file (%s)" % [name, map_file])
		return PackedStringArray()
	var text := FileAccess.get_file_as_string(map_file)
	var rows := PackedStringArray()
	for line in text.split("\n"):
		if line.begins_with("#!") or line.strip_edges().is_empty():
			continue  # "#!" marks a comment; "#" alone is a tile
		rows.append(line)
	return rows


func _build(rows: PackedStringArray) -> void:
	_height = rows.size()
	for y in _height:
		var row := rows[y]
		_width = maxi(_width, row.length())
		for x in row.length():
			_place(row[x], x, y)


func _place(symbol: String, x: int, y: int) -> void:
	var cell := Vector2i(x, y)
	var world := Vector2(x * TILE + TILE * 0.5, y * TILE + TILE * 0.5)

	match symbol:
		"#":
			tiles.set_cell(cell, SOURCE_ID, ledge_tile)
		"1", "=", "*":
			tiles.set_cell(cell, SOURCE_ID, ATLAS[symbol])
		":":
			background.set_cell(cell, SOURCE_ID, ATLAS[":"])
		"^":
			# Ember rock. Solid, so you can stand next to it, but it burns.
			tiles.set_cell(cell, SOURCE_ID, ATLAS["^"])
			_spawn(HazardScene, world)
		"@":
			_spawn_point = world
			player = _spawn(PlayerScene, world)
		"c":
			_spawn(CrystalScene, world)
		"x":
			_spawn(CrawlerScene, world)
		"w":
			_spawn(CritterScene, world)
		"v":
			var door := _spawn(DescentScene, world)
			door.next_zone = next_zone
			door.next_zone_name = next_zone_name
		".", " ":
			pass
		_:
			push_warning("Unknown map symbol '%s' at %d,%d" % [symbol, x, y])


func _spawn(scene: PackedScene, world_position: Vector2) -> Node2D:
	var node: Node2D = scene.instantiate()
	node.position = world_position
	entities.add_child(node)
	return node


func _frame_camera() -> void:
	# The camera lives on the player. The level only tells it how far the
	# world goes, so it never shows the void past the edge of the map.
	if not player:
		return
	_camera = player.get_node_or_null("Camera") as Camera2D
	if not _camera:
		return
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = maxi(_width * TILE, 320)
	_camera.limit_bottom = maxi(_height * TILE, 180)


func _process(_delta: float) -> void:
	# Cheap parallax: the backdrop drifts at a fraction of the camera speed.
	if _camera and is_instance_valid(_camera):
		var centre := _camera.get_screen_center_position()
		backdrop_layer.offset = -centre * 0.12

	# Fell out of the world. Put the player back and take a heart.
	if player and is_instance_valid(player) and player.global_position.y > (_height + 4) * TILE:
		player.global_position = _spawn_point
		player.velocity = Vector2.ZERO
		Game.damage(1)
