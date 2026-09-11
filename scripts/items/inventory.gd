class_name Inventory
extends RefCounted
## What the player is carrying.
##
## Flat slots rather than a bag of counts, because stack limits and a hotbar
## both need to know *where* a thing is, not just how much of it there is.
## The first HOTBAR slots are the hotbar; the rest is the backpack.

signal changed

const SLOTS := 30
const HOTBAR := 10

var ids: Array[String] = []
var counts: Array[int] = []
var selected := 0

var _db: ItemDB


func _init() -> void:
	_db = ItemDB.get_db()
	ids.resize(SLOTS)
	counts.resize(SLOTS)
	clear()


func clear() -> void:
	for i in SLOTS:
		ids[i] = ""
		counts[i] = 0
	selected = 0
	changed.emit()


func is_empty_slot(i: int) -> bool:
	return counts[i] <= 0 or ids[i].is_empty()


func count_of(id: String) -> int:
	var total := 0
	for i in SLOTS:
		if ids[i] == id:
			total += counts[i]
	return total


func selected_item() -> String:
	return "" if is_empty_slot(selected) else ids[selected]


func select(index: int) -> void:
	selected = clampi(index, 0, HOTBAR - 1)
	changed.emit()


## Adds what it can and returns what would not fit.
func add(id: String, amount: int) -> int:
	if id.is_empty() or amount <= 0 or not _db.has(id):
		return amount
	var limit := _db.stack_limit(id)
	var left := amount

	# Top up stacks that already exist before opening a new slot, so a
	# backpack does not fill with partial piles of the same thing.
	for i in SLOTS:
		if left <= 0:
			break
		if ids[i] == id and counts[i] < limit:
			var room: int = limit - counts[i]
			var moved: int = mini(room, left)
			counts[i] += moved
			left -= moved

	for i in SLOTS:
		if left <= 0:
			break
		if is_empty_slot(i):
			var moved: int = mini(limit, left)
			ids[i] = id
			counts[i] = moved
			left -= moved

	if left != amount:
		changed.emit()
	return left


## Takes them out. Returns false and changes nothing if there are not enough.
func remove(id: String, amount: int) -> bool:
	if count_of(id) < amount:
		return false
	var left := amount
	for i in SLOTS:
		if left <= 0:
			break
		if ids[i] != id:
			continue
		var taken: int = mini(counts[i], left)
		counts[i] -= taken
		left -= taken
		if counts[i] <= 0:
			ids[i] = ""
			counts[i] = 0
	changed.emit()
	return true


## Everything held, as id -> total. For saving and for the crafting list.
func totals() -> Dictionary:
	var out := {}
	for i in SLOTS:
		if is_empty_slot(i):
			continue
		out[ids[i]] = int(out.get(ids[i], 0)) + counts[i]
	return out


func to_save() -> Array:
	var out: Array = []
	for i in SLOTS:
		out.append([ids[i], counts[i]])
	return out


func from_save(data: Array) -> void:
	for i in mini(SLOTS, data.size()):
		ids[i] = str(data[i][0])
		counts[i] = int(data[i][1])
	changed.emit()
