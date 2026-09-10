extends Node
## Headless checks for world generation.
##
##   godot --headless --path . res://tests/world_test.tscn
##
## The determinism checks are the important ones. Everything else in the game
## can be re-tuned; a generator that quietly stops being reproducible breaks
## saves, breaks bug reports and breaks every other test that seeds a world.

var _passed := 0
var _failed := 0


func _ready() -> void:
	await get_tree().process_frame
	print("Abyssbound world test")
	print("---------------------")

	_check_tile_db()
	_check_determinism()
	_check_order_independence()
	_check_surface()
	_check_biomes()
	_check_shaft()
	_check_ores_and_caves()
	_check_speed()
	await _check_digging()
	await _check_lighting()
	_check_save_load()
	await _check_traversal()

	print("---------------------")
	print("%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _ok(label: String, condition: bool, detail := "") -> void:
	if condition:
		_passed += 1
		print("  PASS  %s%s" % [label, (" (%s)" % detail) if detail else ""])
	else:
		_failed += 1
		print("  FAIL  %s%s" % [label, (" (%s)" % detail) if detail else ""])


func _check_tile_db() -> void:
	print("\ntile data")
	var db := TileDB.get_db()
	_ok("tiles.json loads", db.max_id > 0, "max id %d" % db.max_id)
	_ok("air is not solid", not db.is_solid(0))
	_ok("stone is solid", db.is_solid(db.id("stone")))
	_ok("torch emits light", db.emit[db.id("torch")] > 0)
	_ok("walls are flagged", db.wall[db.id("stone_wall")] == 1)
	_ok("stone is harder than dirt", db.hardness[db.id("stone")] > db.hardness[db.id("dirt")])


func _check_determinism() -> void:
	print("\ndeterminism")
	var a := ChunkStore.new(1234)
	var b := ChunkStore.new(1234)
	var c := ChunkStore.new(9999)

	var same := true
	for coord in [Vector2i(10, 4), Vector2i(31, 12), Vector2i(0, 0), Vector2i(62, 24)]:
		var ca := a.generate_detached(coord.x, coord.y)
		var cb := b.generate_detached(coord.x, coord.y)
		if ca.fg != cb.fg or ca.bg != cb.bg or ca.water != cb.water:
			same = false
	_ok("same seed gives identical chunks", same)

	var ca2 := a.generate_detached(10, 4)
	var cc := c.generate_detached(10, 4)
	_ok("a different seed gives a different world", ca2.fg != cc.fg)


func _check_order_independence() -> void:
	print("\ngeneration order")
	# One store asks for the target first. The other walks its neighbours
	# before asking. A generator carrying state between chunks fails here.
	var first := ChunkStore.new(4242)
	var target_first := first.get_chunk(20, 5).fg.duplicate()

	var later := ChunkStore.new(4242)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			later.get_chunk(20 + dx, 5 + dy)
	var target_later := later.get_chunk(20, 5).fg

	_ok("a chunk does not depend on its neighbours being made first",
		target_first == target_later)


func _check_surface() -> void:
	print("\nsurface")
	var store := ChunkStore.new(7)
	var worst := 0
	var worst_x := 0
	for x in range(1, WorldGen.WIDTH):
		var step: int = absi(store.gen.surface_height(x) - store.gen.surface_height(x - 1))
		if step > worst:
			worst = step
			worst_x = x
	_ok("the surface has no cliff between biomes", worst <= 6,
		"biggest step %d tiles at x=%d" % [worst, worst_x])

	# Somewhere to stand: ground solid, head clear.
	var standable := 0
	for x in range(200, 1900, 37):
		var h := store.gen.surface_height(x)
		if store.is_solid(x, h) and not store.is_solid(x, h - 1) and not store.is_solid(x, h - 2):
			standable += 1
	_ok("the surface is stood on, not buried", standable >= 40, "%d of 46 columns" % standable)


func _check_biomes() -> void:
	print("\nbiomes")
	var store := ChunkStore.new(7)
	var seen := {}
	for x in range(0, WorldGen.WIDTH, 5):
		seen[store.gen.biome_name(x)] = true
	for wanted in ["ocean", "plains", "forest", "desert", "mountains"]:
		_ok("%s exists" % wanted, seen.has(wanted))

	var db := TileDB.get_db()
	_ok("the ocean holds water", store.get_water(40, WorldGen.SEA_LEVEL + 10) > 0)
	_ok("the desert is sand",
		store.get_fg(800, store.gen.surface_height(800)) == db.id("sand"))
	_ok("the mountains carry snow",
		store.get_fg(1300, store.gen.surface_height(1300)) == db.id("snow"),
		"y=%d" % store.gen.surface_height(1300))


func _check_shaft() -> void:
	print("\nthe Abyss")
	var store := ChunkStore.new(7)

	# Open all the way down, and open at the top so it can be walked into.
	var blocked := 0
	var deepest := 0
	for y in range(140, WorldGen.HEIGHT, 3):
		var cx := store.gen.shaft_center(y)
		if store.is_solid(cx, y):
			blocked += 1
		else:
			deepest = y
	_ok("the shaft is open from the surface to the bottom", blocked == 0,
		"%d blocked samples, deepest open y=%d" % [blocked, deepest])

	var mouth := store.gen.surface_height(WorldGen.ABYSS_CENTER_X)
	_ok("the shaft mouth is at the surface, not sealed",
		not store.is_solid(store.gen.shaft_center(mouth + 2), mouth + 2))

	# Sampled, not spot-checked: any single deep tile may land inside a cavern,
	# so the claim is about what the rock down there is made of.
	var db := TileDB.get_db()
	var abyss_rock := 0
	var other_rock := 0
	for x in range(200, 900, 11):
		for y in range(WorldGen.ABYSS_TOP + 40, 780, 13):
			var t := store.get_fg(x, y)
			if t == db.id("abyss_stone"):
				abyss_rock += 1
			elif t != 0:
				other_rock += 1
	_ok("the deep layers are their own rock", other_rock == 0 and abyss_rock > 100,
		"%d abyss, %d other" % [abyss_rock, other_rock])

	_ok("the shaft is wider deep than shallow",
		store.gen.shaft_half_width(700) > store.gen.shaft_half_width(100))

	# Without a wall behind it the sky backdrop shows through and the mouth
	# reads as a cliff over open air rather than a hole in the ground.
	var walled := 0
	var sampled := 0
	for y in range(220, 760, 17):
		var cx := store.gen.shaft_center(y)
		sampled += 1
		if store.get_bg(cx, y) != 0:
			walled += 1
	_ok("the shaft has rock behind it, not sky", walled == sampled,
		"%d of %d samples walled" % [walled, sampled])


func _check_ores_and_caves() -> void:
	print("\nunderground")
	var store := ChunkStore.new(7)
	var db := TileDB.get_db()
	var copper := 0
	var iron := 0
	var air := 0
	var solid := 0
	for x in range(300, 700):
		for y in range(160, 500, 2):
			var t := store.get_fg(x, y)
			if t == db.id("copper_ore"):
				copper += 1
			elif t == db.id("iron_ore"):
				iron += 1
			elif t == 0:
				air += 1
			else:
				solid += 1
	_ok("copper is underground", copper > 0, "%d tiles" % copper)
	_ok("iron is deeper down", iron > 0, "%d tiles" % iron)
	_ok("caves exist", air > 0, "%d air tiles" % air)
	_ok("the underground is mostly rock, not hollow",
		float(air) / float(air + solid) < 0.5,
		"%.1f%% air" % (100.0 * float(air) / float(air + solid)))


func _check_speed() -> void:
	print("\nspeed")
	var store := ChunkStore.new(31337)
	var start := Time.get_ticks_usec()
	var n := 0
	for cx in range(20, 30):
		for cy in range(3, 8):
			store.generate_detached(cx, cy)
			n += 1
	var us := Time.get_ticks_usec() - start
	var per := float(us) / float(n) / 1000.0
	_ok("a chunk generates fast enough to stream", per < 8.0,
		"%.2f ms per chunk over %d chunks" % [per, n])


# ---------------------------------------------------------------------------
func _check_digging() -> void:
	print("\ndigging")
	var world: Node2D = load("res://scenes/world.tscn").instantiate()
	world.seed_override = 20260910
	world.spawn_override_x = 300
	add_child(world)
	for i in 40:
		await get_tree().physics_frame

	var store: ChunkStore = world.store
	var mining = world.mining
	var db := TileDB.get_db()

	_ok("the player lands on the generated ground", world.player.is_on_floor(),
		"tile %s" % world.player_tile())

	# Dig the ground out from under the player and it should stop being solid,
	# stop being drawn, and stop holding the player up.
	var under: Vector2i = world.player_tile() + Vector2i(0, 1)
	while not store.is_solid(under.x, under.y) and under.y < 200:
		under.y += 1
	var before := store.get_fg(under.x, under.y)
	_ok("there is rock under the player", before != 0, db.name_of.get(before, "?"))

	var y_before: float = world.player.global_position.y
	mining._set_tile(under.x, under.y, 0)
	_ok("a dug tile is gone from the data", store.get_fg(under.x, under.y) == 0)
	_ok("a dug tile is gone from the tilemap",
		world.renderer.fg_layer.get_cell_source_id(under) == -1)

	for i in 30:
		await get_tree().physics_frame
	_ok("digging drops the player through the hole",
		world.player.global_position.y > y_before + 4.0,
		"y %.1f -> %.1f" % [y_before, world.player.global_position.y])

	# Placing rules.
	_ok("nothing can be placed in open sky", not mining._has_support(300, 20))
	_ok("rock can be placed against rock", mining._has_support(under.x, under.y))

	var here: Vector2i = world.player_tile()
	_ok("a solid tile cannot be placed inside the player", mining._overlaps_player(here))
	_ok("a tile far away does not overlap the player",
		not mining._overlaps_player(here + Vector2i(6, 0)))

	# Put it back, and it comes back.
	mining._set_tile(under.x, under.y, db.id("stone"))
	_ok("a placed tile is solid again", store.is_solid(under.x, under.y))
	_ok("a placed tile is drawn",
		world.renderer.fg_layer.get_cell_source_id(under) == 0)

	_ok("harder rock takes longer to break",
		db.hardness[db.id("abyss_stone")] > db.hardness[db.id("dirt")] * 2)

	world.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
func _check_lighting() -> void:
	print("\nlighting")
	var world: Node2D = load("res://scenes/world.tscn").instantiate()
	world.seed_override = 20260910
	world.spawn_override_x = 300
	add_child(world)
	for i in 30:
		await get_tree().physics_frame

	var store: ChunkStore = world.store
	var lighting = world.lighting
	var db := TileDB.get_db()

	var surface := store.gen.surface_height(300)
	lighting.update_now(Vector2i(300, surface))

	_ok("open sky is fully lit", lighting.light_at(300, surface - 3) >= 250,
		"%d" % lighting.light_at(300, surface - 3))
	_ok("sunlight dies inside rock",
		lighting.light_at(300, surface + 12) < 120,
		"%d at 12 tiles down" % lighting.light_at(300, surface + 12))

	# Deep underground with nothing burning: dark, but never so dark the screen
	# is blank. That reads as a bug, not as a cave.
	lighting.update_now(Vector2i(300, 400))
	var deep: int = lighting.light_at(300, 400)
	_ok("deep rock is dark", deep < 90, "%d" % deep)
	_ok("deep rock is never pitch black", deep >= Lighting.AMBIENT, "%d" % deep)

	# A torch has to actually change something.
	var room := Vector2i(300, 400)
	for dx in range(-4, 5):
		for dy in range(-3, 3):
			store.set_fg(room.x + dx, room.y + dy, 0)
	lighting.mark_dirty()
	lighting.update_now(room)
	var unlit: int = lighting.light_at(room.x + 2, room.y)

	store.set_fg(room.x, room.y, db.id("torch"))
	lighting.mark_dirty()
	lighting.update_now(room)
	var lit: int = lighting.light_at(room.x + 2, room.y)
	_ok("a torch lights the room around it", lit > unlit + 60,
		"%d -> %d" % [unlit, lit])
	_ok("torch light falls off with distance",
		lighting.light_at(room.x + 1, room.y) > lighting.light_at(room.x + 4, room.y))

	_ok("a whole light pass fits in a frame budget", lighting.last_ms < 16.0,
		"%.2f ms" % lighting.last_ms)

	# The pass is split over two frames, because compiled to wasm the whole
	# thing costs about 26 ms. Two incremental calls must land on exactly the
	# same light as doing it in one go, or the split is a rendering bug.
	var probe := Vector2i(300, 400)
	lighting.update_now(probe)
	var expected: Array[int] = []
	for dx in [-20, -8, 0, 7, 19]:
		expected.append(lighting.light_at(probe.x + dx, probe.y))

	var split: Node = load("res://scripts/world/lighting.gd").new()
	world.add_child(split)
	split.setup(store)
	split.update(probe)
	var worst: float = split.last_phase_ms
	for i in 8:
		if split.is_idle():
			break
		split.update(probe)
		worst = maxf(worst, split.last_phase_ms)
	var got: Array[int] = []
	for dx in [-20, -8, 0, 7, 19]:
		got.append(split.light_at(probe.x + dx, probe.y))

	_ok("splitting the pass over two frames gives the same light",
		got == expected, "%s vs %s" % [got, expected])
	_ok("no single step of a split pass is close to a frame",
		worst < lighting.last_ms * 0.55,
		"worst step %.2f ms of a %.2f ms pass" % [worst, lighting.last_ms])
	split.queue_free()

	world.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
func _check_save_load() -> void:
	print("\nsave and load")
	WorldSave.clear()

	var store := ChunkStore.new(5150)
	var db := TileDB.get_db()

	# Find rock, dig it, and put something else somewhere else.
	var x := 400
	var y := store.gen.surface_height(x) + 6
	var original := store.get_fg(x, y)
	_ok("there is something to dig", original != 0, db.name_of.get(original, "?"))

	store.set_fg(x, y, 0)
	store.set_fg(x + 1, y - 1, db.id("torch"))
	var untouched_before := store.get_fg(x + 8, y)

	_ok("saving writes a file", WorldSave.save_world(store, Vector2(x * 16, y * 16)))

	var loaded := WorldSave.load_world()
	_ok("a save can be loaded", not loaded.is_empty())
	var reloaded: ChunkStore = loaded["store"]

	_ok("the seed survives", reloaded.world_seed() == 5150)
	_ok("a dug tile is still dug after save and load",
		reloaded.get_fg(x, y) == 0, db.name_of.get(reloaded.get_fg(x, y), "?"))
	_ok("a placed tile is still there after save and load",
		reloaded.get_fg(x + 1, y - 1) == db.id("torch"))
	_ok("untouched tiles come back from the seed, not the file",
		reloaded.get_fg(x + 8, y) == untouched_before)

	# The chunk holding the edit was never generated in the loaded store until
	# the line above asked for it. Prove the far side of the world still works.
	var far_y := 300
	_ok("a chunk generated after loading still matches a fresh world",
		reloaded.get_fg(1200, far_y) == ChunkStore.new(5150).get_fg(1200, far_y))

	# Round trip twice: edits must survive being re-saved from a loaded world.
	WorldSave.save_world(reloaded, Vector2.ZERO)
	var again: ChunkStore = WorldSave.load_world()["store"]
	_ok("edits survive a second save and load", again.get_fg(x, y) == 0)

	var fresh_size := FileAccess.open(WorldSave.PATH, FileAccess.READ).get_length()
	_ok("a save is small because it stores changes, not the world",
		fresh_size < 4096, "%d bytes for 2 edits" % fresh_size)

	WorldSave.clear()


# ---------------------------------------------------------------------------
## Both of these come from playing the game, not from reading it. The first
## run walked two tiles east and stopped: the spawn was beside a tree and tree
## trunks were solid, so the tree was a wall. The fix made trunks walkable, the
## way they are in the game this borrows from. Then it still needed six jumps
## to cross ten tiles, because natural ground is all single tile steps.
func _check_traversal() -> void:
	print("\ntraversal")
	var db := TileDB.get_db()
	_ok("a tree trunk is walked through, not into", not db.is_solid(db.id("tree_trunk")))
	_ok("wood the building block is still solid", db.is_solid(db.id("wood")))

	# No column of forest should be a wall at head height.
	var store := ChunkStore.new(20260910)
	var blocked := 0
	var trunks := 0
	for x in range(500, 700):
		var h := store.gen.surface_height(x)
		if store.get_fg(x, h - 1) == db.id("tree_trunk"):
			trunks += 1
			if store.is_solid(x, h - 1) or store.is_solid(x, h - 2):
				blocked += 1
	_ok("a forest can be walked through", blocked == 0,
		"%d trunks, %d blocking" % [trunks, blocked])

	# A single tile step is walked over, not jumped over.
	var root := Node2D.new()
	add_child(root)
	var ground := StaticBody2D.new()
	var gshape := CollisionShape2D.new()
	var grect := RectangleShape2D.new()
	grect.size = Vector2(400, 48)
	gshape.shape = grect
	ground.add_child(gshape)
	ground.position = Vector2(200, 224)
	ground.collision_layer = 1
	root.add_child(ground)

	var step := StaticBody2D.new()
	var sshape := CollisionShape2D.new()
	var srect := RectangleShape2D.new()
	srect.size = Vector2(64, 16)
	sshape.shape = srect
	step.add_child(sshape)
	step.position = Vector2(260, 192)
	step.collision_layer = 1
	root.add_child(step)

	var player: CharacterBody2D = load("res://scenes/actors/player.tscn").instantiate()
	player.position = Vector2(150, 180)
	root.add_child(player)
	for i in 40:
		await get_tree().physics_frame

	var x_before: float = player.global_position.x
	Input.action_press("move_right")
	for i in 90:
		await get_tree().physics_frame
	Input.action_release("move_right")

	var travelled: float = player.global_position.x - x_before
	_ok("a one tile step does not need a jump", travelled > 80.0,
		"%.0f px travelled without pressing jump" % travelled)
	_ok("stepping up puts the player on top of the step",
		player.global_position.y < 190.0, "y=%.1f" % player.global_position.y)

	root.queue_free()
	await get_tree().process_frame
