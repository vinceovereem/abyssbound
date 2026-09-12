class_name WorldGlows
extends Node2D
## Soft coloured light around anything that gives light off.
##
## Drawn additively over the darkness, one sprite per source, rebuilt only when
## the set of sources changes — which happens when a chunk streams in or a tile
## is placed, not every frame.
##
## This is deliberately **not** coloured light propagation. Carrying three
## channels through the flood fill would triple the cost of the one system that
## has ever missed frame budget here. A glow around the source buys the look
## that matters: a torch is warm, a crystal is cold, and the dark around them
## takes that colour.

const TILE := 16
const GLOW := preload("res://assets/generated/fx/glow.png")

var renderer: ChunkRenderer

var _db: TileDB
var _material: CanvasItemMaterial


func setup(chunk_renderer: ChunkRenderer) -> void:
	renderer = chunk_renderer
	_db = TileDB.get_db()
	z_index = 21   # over the darkness, under the floating text

	_material = CanvasItemMaterial.new()
	_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD


func _process(_delta: float) -> void:
	if renderer == null or not renderer.emitters_changed:
		return
	renderer.emitters_changed = false
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()

	for cell: Vector2i in renderer.emitters.keys():
		var id: int = renderer.emitters[cell]
		var strength := float(_db.emit[id]) / 255.0

		var sprite := Sprite2D.new()
		sprite.texture = GLOW
		sprite.material = _material
		sprite.position = Vector2(cell.x * TILE + TILE * 0.5, cell.y * TILE + TILE * 0.5)
		# Brighter sources reach further, which is what makes a furnace read as
		# bigger than a torch without needing a second sprite.
		sprite.scale = Vector2.ONE * lerpf(0.55, 1.35, strength)
		var colour := _db.colour_of_light(id)
		sprite.modulate = Color(colour.r, colour.g, colour.b, lerpf(0.30, 0.62, strength))
		add_child(sprite)
