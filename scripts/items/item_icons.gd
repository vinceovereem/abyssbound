class_name ItemIcons
extends RefCounted
## One place that knows what an item looks like.
##
## Blocks draw the tile they become, so a stack of stone in the hotbar is the
## stone you will place. Everything else draws from the item sheet.

const TILE_SHEET := preload("res://assets/tiles/tiles.png")
const ITEM_SHEET := preload("res://assets/sprites/items.png")


static func texture_for(id: String) -> Texture2D:
	if id.is_empty():
		return null
	var items := ItemDB.get_db()
	var tex := AtlasTexture.new()

	var tile := items.tile_of(id)
	if not tile.is_empty():
		tex.atlas = TILE_SHEET
		tex.region = Rect2(TileDB.get_db().id(tile) * 16, 0, 16, 16)
		return tex

	if items.of(id).has("icon"):
		tex.atlas = ITEM_SHEET
		tex.region = Rect2(int(items.of(id)["icon"]) * 16, 0, 16, 16)
		return tex
	return null
