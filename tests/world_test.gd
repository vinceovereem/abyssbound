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
