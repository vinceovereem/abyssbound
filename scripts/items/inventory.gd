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
## What is worn. Kept apart from the slots so armour cannot be accidentally
## placed, dropped or stacked while it is on.
var equipped := { "head": "", "body": "", "legs": "" }

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
	for slot: String in equipped.keys():
		equipped[slot] = ""
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


## Puts a piece on, swapping whatever was there back into the bag. Refuses if
## the bag has no room for the swap, so nothing is destroyed by equipping.
func equip(id: String) -> bool:
	if not _db.has(id) or _db.kind(id) != "armour":
		return false
	var slot := str(_db.of(id).get("slot", ""))
	if slot.is_empty() or not equipped.has(slot):
		return false
	if count_of(id) <= 0:
		return false

	var previous: String = equipped[slot]
	if not remove(id, 1):
		return false
	equipped[slot] = id
	if not previous.is_empty() and add(previous, 1) > 0:
		# Nowhere to put the old piece. Undo rather than lose it.
		equipped[slot] = previous
		add(id, 1)
		return false
	changed.emit()
	return true


func unequip(slot: String) -> bool:
	var worn: String = str(equipped.get(slot, ""))
	if worn.is_empty():
		return false
	if add(worn, 1) > 0:
		return false   # no room; leave it on
	equipped[slot] = ""
	changed.emit()
	return true


## How much a hit is softened by what is worn.
func defence() -> int:
	var total := 0
	for slot: String in equipped.keys():
		var worn: String = equipped[slot]
		if not worn.is_empty():
			total += int(_db.of(worn).get("defence", 0))
	return total


## Swap two slots. How something gets from the backpack into your hand.
func swap(a: int, b: int) -> void:
	if a == b or a < 0 or b < 0 or a >= SLOTS or b >= SLOTS:
		return
	var id := ids[a]
	var count := counts[a]
	ids[a] = ids[b]
	counts[a] = counts[b]
	ids[b] = id
	counts[b] = count
	changed.emit()


## Everything held, as id -> total. For saving and for the crafting list.
func totals() -> Dictionary:
	var out := {}
	for i in SLOTS:
		if is_empty_slot(i):
			continue
		out[ids[i]] = int(out.get(ids[i], 0)) + counts[i]
	return out


func to_save() -> Dictionary:
	var slots: Array = []
	for i in SLOTS:
		slots.append([ids[i], counts[i]])
	return { "slots": slots, "equipped": equipped.duplicate() }


func from_save(data: Variant) -> void:
	# Older saves were a bare array of slots, with nothing worn.
	var slots: Array = data if data is Array else data.get("slots", [])
	for i in mini(SLOTS, slots.size()):
		ids[i] = str(slots[i][0])
		counts[i] = int(slots[i][1])
	if data is Dictionary:
		for slot: String in data.get("equipped", {}).keys():
			if equipped.has(slot):
				equipped[slot] = str(data["equipped"][slot])
	changed.emit()
