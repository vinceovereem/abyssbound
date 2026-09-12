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
	print("BocciaBound world test")
	print("---------------------")

	_check_tile_db()
	_check_determinism()
	_check_order_independence()
	_check_surface()
	_check_biomes()
	_check_caves()
	_check_ores_and_caves()
	_check_speed()
	await _check_digging()
	await _check_lighting()
	_check_save_load()
	await _check_traversal()
	await _check_reach()
	await _check_finds()
	await _check_trees()
	await _check_bats()
	_check_art_manifest()
	_check_clock()
	await _check_night()
	await _check_death()
	_check_goals()
	_check_inventory()
	_check_crafting()
	await _check_stations_and_tools()
	_check_armour()

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


## Caves you can explore, which is the whole point of the underground now that
## there is no single chasm to walk down.
func _check_caves() -> void:
	print("\ncaves")
	var store := ChunkStore.new(7)
	var db := TileDB.get_db()

	# Openness, measured where the chambers are meant to be.
	var air := 0
	var solid := 0
	for x in range(400, 800):
		for y in range(WorldGen.CAVERN_TOP, WorldGen.DEEP_TOP, 2):
			if store.get_fg(x, y) == 0:
				air += 1
			else:
				solid += 1
	var openness := 100.0 * float(air) / float(air + solid)
	_ok("the caverns are open enough to walk about in", openness > 22.0,
		"%.1f%% air" % openness)
	_ok("but are still rock, not a void", openness < 55.0, "%.1f%% air" % openness)

	# The thing that makes it explorable rather than a field of pockets: some
	# cave should lead a long way. Flooding from the first hole found measures
	# whichever pocket that happened to be, so take the best of many starts.
	var starts: Array[Vector2i] = []
	for x in range(420, 900, 24):
		for y in range(WorldGen.CAVERN_TOP + 10, WorldGen.DEEP_TOP, 40):
			if store.get_fg(x, y) == 0 and store.get_fg(x, y + 1) != 0:
				starts.append(Vector2i(x, y))
				break
	_ok("there is somewhere underground to stand", starts.size() > 8,
		"%d footholds sampled" % starts.size())

	var biggest := 0
	for from: Vector2i in starts:
		biggest = maxi(biggest, _flood(store, from, 30000))
	_ok("some cave leads a long way", biggest > 2500,
		"largest system %d tiles" % biggest)

	# A way in from the surface, without digging.
	var entrances := 0
	for x in range(300, 1700, 3):
		var h := store.gen.surface_height(x)
		var open_run := 0
		for y in range(h, h + 26):
			if store.get_fg(x, y) == 0:
				open_run += 1
			else:
				open_run = 0
			if open_run >= 6:
				entrances += 1
				break
	_ok("the surface has holes you can walk into", entrances > 10,
		"%d of %d columns" % [entrances, 467])

	# Depth still changes the rock.
	var deep_rock := 0
	var other := 0
	for x in range(300, 900, 13):
		for y in range(WorldGen.DEEP_TOP + 40, 780, 17):
			var t := store.get_fg(x, y)
			if t == db.id("abyss_stone"):
				deep_rock += 1
			elif t != 0:
				other += 1
	_ok("the deep rock is its own stone", other == 0 and deep_rock > 40,
		"%d deep, %d other" % [deep_rock, other])

	# The Abyss came back, but only on the condition that it is a hub and not a
	# corridor. These check the condition, not just that a hole exists.
	var blocked := 0
	# The player's question is not "is anything open" but "how far do I fall".
	# Drop down several lines through the chasm and measure the worst one.
	var worst_fall := 0
	for offset in [-10, -5, 0, 5, 10]:
		var fell := 0
		var y := WorldGen.ABYSS_RIM + 2
		while y < WorldGen.HEIGHT - 2:
			var x: int = store.gen.abyss_centre(y) + offset
			if store.is_solid(x, y):
				fell = 0
			else:
				fell += 1
				worst_fall = maxi(worst_fall, fell)
			y += 1
	_ok("the Abyss is a climb down, not one long fall", worst_fall < 40,
		"worst unbroken drop %d tiles" % worst_fall)

	var shelves := 0
	for y in range(WorldGen.ABYSS_RIM, WorldGen.HEIGHT):
		if store.is_solid(store.gen.abyss_centre(y), y):
			shelves += 1
	_ok("there are shelves to land on", shelves > 40, "%d shelf rows" % shelves)

	# And a way past every one of them, or it is a floor and not a shelf.
	var sealed := 0
	for y in range(WorldGen.ABYSS_RIM, WorldGen.HEIGHT):
		var centre := store.gen.abyss_centre(y)
		var half := store.gen.abyss_half_width(y)
		var open_here := false
		for x in range(centre - half, centre + half + 1):
			if not store.is_solid(x, y):
				open_here = true
				break
		if not open_here:
			sealed += 1
	_ok("no shelf seals the chasm off", sealed == 0, "%d sealed rows" % sealed)

	_ok("it widens as it goes down",
		store.gen.abyss_half_width(WorldGen.HEIGHT - 40)
			> store.gen.abyss_half_width(WorldGen.ABYSS_RIM + 10) * 2,
		"%d at the rim, %d at the bottom" % [
			store.gen.abyss_half_width(WorldGen.ABYSS_RIM + 10),
			store.gen.abyss_half_width(WorldGen.HEIGHT - 40)])

	var walled := 0
	var sampled := 0
	for y in range(WorldGen.ABYSS_RIM + 40, 760, 23):
		sampled += 1
		if store.get_bg(store.gen.abyss_centre(y), y) != 0:
			walled += 1
	_ok("it has rock behind it, not sky", walled == sampled,
		"%d of %d" % [walled, sampled])

	# The reason it is allowed back: caves open onto it, so it is somewhere the
	# underground leads rather than the only way down.
	var openings := 0
	for y in range(WorldGen.ABYSS_RIM + 30, 740, 6):
		var edge: int = store.gen.abyss_centre(y) + store.gen.abyss_half_width(y) + 4
		if not store.is_solid(edge, y):
			openings += 1
	_ok("caves open onto the chasm wall", openings > 20,
		"%d openings down one side" % openings)

	# Somewhere to stand and look down, which is the shot on the concept sheet.
	var rim_centre: int = store.gen.abyss_centre(WorldGen.ABYSS_RIM)
	var rim: int = rim_centre - store.gen.abyss_half_width(WorldGen.ABYSS_RIM) - 3
	var rim_ground := store.gen.surface_height(rim)
	_ok("the rim can be stood on", store.is_solid(rim, rim_ground)
		and not store.is_solid(rim, rim_ground - 1), "x=%d" % rim)
	_ok("and the drop beside it is a drop",
		not store.is_solid(store.gen.abyss_centre(rim_ground + 20), rim_ground + 20))

	_ok("the Abyss has layers to name",
		store.gen.abyss_layer(WorldGen.HEIGHT - 30) > store.gen.abyss_layer(WorldGen.ABYSS_RIM + 5))


## How many air tiles connect to this one. Bounded so a runaway cannot hang.
func _flood(store: ChunkStore, from: Vector2i, limit: int) -> int:
	if from.x < 0:
		return 0
	var seen := {}
	var queue: Array[Vector2i] = [from]
	seen[from] = true
	var count := 0
	while not queue.is_empty() and count < limit:
		var at: Vector2i = queue.pop_back()
		count += 1
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := at + d
			if seen.has(next):
				continue
			if next.y < 40 or next.y >= WorldGen.HEIGHT - 2:
				continue
			if next.x < 2 or next.x >= WorldGen.WIDTH - 2:
				continue
			if store.get_fg(next.x, next.y) != 0:
				continue
			seen[next] = true
			queue.append(next)
	return count


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

	# What you were carrying comes back too.
	Game.inventory.clear()
	Game.inventory.add("iron_bar", 7)
	Game.inventory.add("copper_pick", 1)
	WorldSave.save_world(store, Vector2.ZERO)
	Game.inventory.clear()
	_ok("the bag is empty before loading", Game.amount_of("iron_bar") == 0)
	WorldSave.load_world()
	_ok("what you were carrying comes back", Game.amount_of("iron_bar") == 7,
		"%d bars" % Game.amount_of("iron_bar"))
	_ok("and so does the pickaxe", Game.amount_of("copper_pick") == 1)
	Game.inventory.clear()

	var fresh_size := FileAccess.open(WorldSave.PATH, FileAccess.READ).get_length()
	_ok("a save is small because it stores changes, not the world",
		fresh_size < 8192, "%d bytes" % fresh_size)

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


# ---------------------------------------------------------------------------
## Digging is aimed with the movement keys and reaches exactly one tile. You
## can break what you are standing on and what is beside or above you, and
## nothing else: no reaching across a room at a block you could not touch.
func _check_reach() -> void:
	print("\nreach")
	var world: Node2D = load("res://scenes/world.tscn").instantiate()
	world.seed_override = 20260910
	world.spawn_override_x = 300
	add_child(world)
	for i in 40:
		await get_tree().physics_frame

	var mining = world.mining
	var db := TileDB.get_db()
	var here: Vector2i = world.player_tile()

	for action in ["move_down", "move_up", "move_left", "move_right", "mine", "place"]:
		Input.action_release(action)

	var forward: Vector2i = mining.target_tile()
	_ok("with no direction held, the aim is the tile you face",
		forward == here + Vector2i(world.player.facing(), 0), "%s" % forward)

	Input.action_press("move_down")
	await get_tree().physics_frame
	_ok("holding down aims at the block underfoot",
		mining.target_tile() == here + Vector2i(0, 1))
	Input.action_release("move_down")

	Input.action_press("move_up")
	await get_tree().physics_frame
	_ok("holding up aims overhead", mining.target_tile() == here + Vector2i(0, -1))
	Input.action_release("move_up")
	await get_tree().physics_frame

	# All eight, so a staircase can be cut rather than only a shaft.
	Input.action_press("move_down")
	Input.action_press("move_right")
	await get_tree().physics_frame
	_ok("down and right aims at the corner",
		mining.target_tile() == here + Vector2i(1, 1), "%s" % mining.target_tile())
	Input.action_release("move_right")
	Input.action_press("move_left")
	await get_tree().physics_frame
	_ok("down and left aims at the other corner",
		mining.target_tile() == here + Vector2i(-1, 1))
	Input.action_release("move_down")
	Input.action_press("move_up")
	await get_tree().physics_frame
	_ok("up and left aims above and behind",
		mining.target_tile() == here + Vector2i(-1, -1))
	Input.action_release("move_up")
	Input.action_release("move_left")
	await get_tree().physics_frame

	# Whatever is held, the aim never leaves the tiles you could touch.
	var far := 0
	for combo in [[], ["move_down"], ["move_up"], ["move_left"], ["move_right"]]:
		for a: String in combo:
			Input.action_press(a)
		await get_tree().physics_frame
		var t: Vector2i = mining.target_tile()
		var d: Vector2i = t - world.player_tile()
		if absi(d.x) > 1 or absi(d.y) > 1:
			far += 1
		for a: String in combo:
			Input.action_release(a)
	_ok("nothing further than one tile can ever be aimed at", far == 0)

	# Breaking pays out, and grass gives dirt rather than grass.
	var grass_id := db.id("grass")
	var spot := Vector2i(here.x + 4, here.y)
	while not store_solid(world, spot) and spot.y < here.y + 6:
		spot.y += 1
	world.store.set_fg(spot.x, spot.y, grass_id)
	var before: int = Game.amount_of("dirt")
	Game.collect(db.drop_of(grass_id), 1)
	_ok("grass gives dirt, not grass", db.drop_of(grass_id) == "dirt")
	_ok("collecting adds to what you are carrying", Game.amount_of("dirt") == before + 1,
		"%d -> %d" % [before, Game.amount_of("dirt")])
	_ok("stone gives stone", db.drop_of(db.id("stone")) == "stone")
	_ok("leaves give nothing", db.drop_of(db.id("leaves")).is_empty())

	world.queue_free()
	await get_tree().process_frame


func store_solid(world: Node2D, at: Vector2i) -> bool:
	var store: ChunkStore = world.store
	return store.is_solid(at.x, at.y)


# ---------------------------------------------------------------------------
func _check_clock() -> void:
	print("\nthe day")
	DayClock.paused = true

	DayClock.set_time(0.5)
	_ok("noon is daytime", not DayClock.is_night())
	_ok("noon is full daylight", is_equal_approx(DayClock.daylight(), 1.0))

	DayClock.set_time(0.95)
	_ok("late is night", DayClock.is_night())
	_ok("night has no sun", is_equal_approx(DayClock.daylight(), 0.0))

	DayClock.set_time(DayClock.DUSK + DayClock.TWILIGHT * 0.5)
	var dusk := DayClock.daylight()
	_ok("dusk is halfway, not a switch", dusk > 0.05 and dusk < 0.95, "%.2f" % dusk)

	DayClock.set_time(0.99)
	var was: int = DayClock.day
	DayClock.advance(DayClock.DAY_SECONDS * 0.02)
	_ok("the day rolls over", DayClock.day == was + 1, "%d -> %d" % [was, DayClock.day])

	DayClock.set_time(0.5)
	_ok("clock text reads as a time", DayClock.clock_text() == "12:00",
		DayClock.clock_text())


# ---------------------------------------------------------------------------
## Night is the point of this milestone: things come out, light keeps them off,
## and morning clears them away.
func _check_night() -> void:
	print("\nnight")
	var world: Node2D = load("res://scenes/world.tscn").instantiate()
	world.seed_override = 20260910
	world.spawn_override_x = 560
	add_child(world)
	for i in 30:
		await get_tree().physics_frame

	var spawner = world.spawner
	var here: Vector2i = world.player_tile()

	# Daylight on the surface: wildlife, nothing hostile.
	DayClock.paused = true
	DayClock.set_time(0.5)
	world.lighting.sky_light = Lighting.SKY
	world.lighting.mark_dirty()
	world.lighting.update_now(here)
	_clear_creatures()
	for i in 40:
		spawner._try_spawn()
	await get_tree().process_frame
	var day_hostiles := get_tree().get_nodes_in_group("hostile").size()
	var day_wildlife := get_tree().get_nodes_in_group("critter").size()
	_ok("nothing hostile comes out in daylight", day_hostiles == 0, "%d" % day_hostiles)
	_ok("wildlife is about in the day", day_wildlife > 0, "%d" % day_wildlife)

	# Night on the surface, unlit: hostiles.
	DayClock.set_time(0.92)
	world.lighting.sky_light = 28
	world.lighting.mark_dirty()
	world.lighting.update_now(here)
	_clear_creatures()
	for i in 40:
		spawner._try_spawn()
	await get_tree().process_frame
	var night_hostiles := get_tree().get_nodes_in_group("hostile").size()
	_ok("things come out at night", night_hostiles > 0, "%d" % night_hostiles)

	# Night, but lit: shelter works.
	_clear_creatures()
	var lit_before := night_hostiles
	world.lighting.sky_light = Lighting.SKY   # stand in for a well lit place
	world.lighting.mark_dirty()
	world.lighting.update_now(here)
	for i in 40:
		spawner._try_spawn()
	await get_tree().process_frame
	var lit_hostiles := get_tree().get_nodes_in_group("hostile").size()
	_ok("a lit place keeps them off", lit_hostiles < lit_before,
		"%d lit vs %d dark" % [lit_hostiles, lit_before])

	# Dawn clears the night off the surface.
	_clear_creatures()
	world.lighting.sky_light = 28
	world.lighting.mark_dirty()
	world.lighting.update_now(here)
	for i in 40:
		spawner._try_spawn()
	await get_tree().process_frame
	var before_dawn := get_tree().get_nodes_in_group("hostile").size()
	spawner._on_day_broke(2)
	await get_tree().process_frame
	await get_tree().process_frame
	var after_dawn := 0
	for node in get_tree().get_nodes_in_group("hostile"):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			after_dawn += 1
	_ok("dawn clears the night away", before_dawn > 0 and after_dawn == 0,
		"%d -> %d" % [before_dawn, after_dawn])

	# You can fight back.
	_clear_creatures()
	var crawler: CharacterBody2D = load("res://scenes/actors/crawler.tscn").instantiate()
	crawler.speed = 0.0
	crawler.hunts = false
	crawler.position = world.player.global_position + Vector2(12, 0)
	world.entities.add_child(crawler)
	await get_tree().process_frame

	var health_before: int = crawler.health
	world.combat._swing()
	_ok("a swing hurts what is in front of you", crawler.health < health_before,
		"%d -> %d" % [health_before, crawler.health])
	world.combat._cooldown = 0.0
	world.combat._swing()
	_ok("two swings take it to nothing", crawler.health <= 0, "%d" % crawler.health)
	# Dying plays out over a short tween before the node goes, so give it that.
	for i in 20:
		await get_tree().physics_frame
	_ok("two swings finish a crawler",
		not is_instance_valid(crawler) or crawler.is_queued_for_deletion())

	_clear_creatures()
	world.queue_free()
	await get_tree().process_frame


func _clear_creatures() -> void:
	for group in ["enemy", "critter", "hostile"]:
		for node in get_tree().get_nodes_in_group(group):
			if is_instance_valid(node):
				node.free()


# ---------------------------------------------------------------------------
## Dying used to reload the scene, which built a brand new world from a fresh
## seed and threw away everything that had been dug. In a game about digging
## that is not a death penalty, it is losing the save.
func _check_death() -> void:
	print("\ndying")
	var world: Node2D = load("res://scenes/world.tscn").instantiate()
	world.seed_override = 20260910
	world.spawn_override_x = 560
	add_child(world)
	for i in 30:
		await get_tree().physics_frame

	var store: ChunkStore = world.store
	var seed_before: int = store.world_seed()

	# Dig something memorable, then die a long way from it.
	var hole := Vector2i(600, store.gen.surface_height(600) + 2)
	world.mining._set_tile(hole.x, hole.y, 0)
	_ok("there is a hole to lose", store.get_fg(hole.x, hole.y) == 0)

	world.teleport(700, store.gen.surface_height(700) - 3)
	for i in 10:
		await get_tree().physics_frame

	Game.health = 1
	Game.damage(1)
	_ok("running out of health kills you", Game.health == 0)

	# Fading out and back takes about a second.
	for i in 90:
		await get_tree().physics_frame

	_ok("you come back with your health", Game.health == Game.max_health,
		"%d" % Game.health)
	_ok("you come back in the same world", world.store.world_seed() == seed_before)
	_ok("the hole you dug is still there", world.store.get_fg(hole.x, hole.y) == 0)
	_ok("you come back where you started",
		absi(world.player_tile().x - 560) <= 3, "x=%d" % world.player_tile().x)
	_ok("the death message is cleared", not Ui.get_node("Root/Message").visible)

	world.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
## The list of things worth doing. Nudges rather than quests: nothing gates on
## them, so the checks are about the counting being right and the data loading.
func _check_goals() -> void:
	print("\nstages")
	Goals.reset()

	_ok("objectives.json loads as stages", Goals.stages.size() >= 3,
		"%d stages" % Goals.stages.size())
	_ok("it starts on the first one", Goals.stage == 0, Goals.stage_name())
	_ok("a stage has a handful of things to do",
		Goals.active().size() >= 3 and Goals.active().size() <= 6,
		"%d objectives" % Goals.active().size())

	# Gathering counts toward this stage and nothing else.
	Game.collect("wood", 4)
	_ok("gathering counts toward its objective", Goals.have("wood") == 4,
		"%d" % Goals.have("wood"))
	_ok("it does not count toward a different material", Goals.have("copper") == 0)

	Game.collect("wood", 40)
	_ok("finishing one marks it done", Goals.is_done("wood"))
	_ok("progress does not run past the target",
		Goals.have("wood") == Goals.need(Goals.active()[0]), "%d" % Goals.have("wood"))
	_ok("a finished one stays on the list, ticked",
		Goals.active().any(func(o: Dictionary) -> bool: return o["id"] == "wood"))

	# Finishing the lot moves the stage on.
	var was: int = Goals.stage
	Goals.note_crafted("torch", 1)
	Goals.note_crafted("workbench", 1)
	Goals.note_crafted("wood_pick", 1)
	_ok("the stage does not move on early", Goals.stage == was)
	Goals._on_dawn(2)
	_ok("finishing every objective moves the stage on", Goals.stage == was + 1,
		"now on %s" % Goals.stage_name())
	_ok("the new stage brings new objectives",
		not Goals.active().any(func(o: Dictionary) -> bool: return o["id"] == "wood"))

	# Things only count while their stage is current.
	Goals.note_chest()
	_ok("a chest counts in the cave stage", Goals.have("chest") == 1)

	Goals.reset()
	_ok("resetting goes back to the first stage",
		Goals.stage == 0 and Goals.have("wood") == 0)

	# Depth and hearts are reached, not accumulated.
	Goals.note_depth(40, 1)
	Goals.note_depth(10, 1)
	Goals.stage = 1
	Goals.note_depth(40, 1)
	Goals.note_depth(10, 1)
	_ok("depth remembers the deepest, not the total", Goals.have("down") == 40,
		"%d" % Goals.have("down"))
	Goals.reset()


func _check_inventory() -> void:
	print("\ncarrying things")
	var db := ItemDB.get_db()
	_ok("items.json loads", db.order.size() > 0, "%d items" % db.order.size())
	_ok("a block knows what tile it becomes", db.tile_of("stone") == "stone")
	_ok("a pickaxe has dig power", db.power_of("iron_pick") > db.power_of("wood_pick"))
	_ok("a workbench provides its station", db.station_of("workbench") == "workbench")

	var inv := Inventory.new()
	_ok("a new bag is empty", inv.count_of("stone") == 0)

	inv.add("stone", 30)
	_ok("things go in", inv.count_of("stone") == 30)

	# Stacks fill up rather than spreading into partial piles.
	inv.add("stone", 200)
	var limit := db.stack_limit("stone")
	var used := 0
	for i in Inventory.SLOTS:
		if inv.ids[i] == "stone":
			used += 1
	_ok("a big pile fills whole stacks", inv.count_of("stone") == 230,
		"%d in %d slots of %d" % [inv.count_of("stone"), used, limit])

	_ok("taking out works", inv.remove("stone", 200) and inv.count_of("stone") == 30)
	_ok("taking out more than you have fails", not inv.remove("stone", 999))
	_ok("and changes nothing when it fails", inv.count_of("stone") == 30)

	# A tool stacks to one, so a full bag of them is thirty tools.
	var tools := Inventory.new()
	var left := tools.add("iron_pick", 40)
	_ok("single stack items take a slot each",
		tools.count_of("iron_pick") == Inventory.SLOTS and left == 40 - Inventory.SLOTS,
		"%d held, %d left over" % [tools.count_of("iron_pick"), left])

	_ok("a full bag reports what would not fit", tools.add("stone", 5) == 5)
	_ok("unknown things are refused", inv.add("not_a_thing", 3) == 3)

	inv.select(4)
	_ok("the hotbar selection sticks", inv.selected == 4)
	inv.select(99)
	_ok("selection cannot leave the hotbar", inv.selected == Inventory.HOTBAR - 1)


# ---------------------------------------------------------------------------
func _check_crafting() -> void:
	print("\ncrafting")
	var book := RecipeBook.get_book()
	_ok("recipes.json loads", book.recipes.size() > 0, "%d recipes" % book.recipes.size())

	var inv := Inventory.new()
	var nowhere := {}
	var bench := { "workbench": true }

	# By hand, with nothing, nothing is possible.
	_ok("with nothing you can make nothing", book.available(inv, nowhere).is_empty())

	inv.add("wood", 10)
	var by_hand := book.available(inv, nowhere)
	_ok("wood alone makes a torch and a workbench", by_hand.size() == 2,
		"%d recipes" % by_hand.size())

	var pick_index := -1
	for i in book.recipes.size():
		if book.recipes[i]["out"] == "wood_pick":
			pick_index = i
	_ok("a pickaxe needs a workbench, not bare hands",
		not book.can_make(pick_index, inv, nowhere))
	inv.add("wood", 10)
	_ok("and can be made once one is standing there",
		book.can_make(pick_index, inv, bench))

	var wood_before := inv.count_of("wood")
	_ok("making it works", book.make(pick_index, inv, bench))
	_ok("making it spends the wood", inv.count_of("wood") == wood_before - 8,
		"%d -> %d" % [wood_before, inv.count_of("wood")])
	_ok("and hands over the pickaxe", inv.count_of("wood_pick") == 1)

	# Smelting needs the furnace, and ore.
	var bar := -1
	for i in book.recipes.size():
		if book.recipes[i]["out"] == "copper_bar":
			bar = i
	var forge := { "furnace": true }
	inv.add("copper_ore", 3)
	_ok("ore does not become a bar over a workbench", not book.can_make(bar, inv, bench))
	_ok("but it does over a furnace", book.can_make(bar, inv, forge))
	_ok("smelting consumes the ore",
		book.make(bar, inv, forge) and inv.count_of("copper_ore") == 0
			and inv.count_of("copper_bar") == 1)


# ---------------------------------------------------------------------------
## Crafting and digging as the player actually meets them: a station standing
## in the world, and a pickaxe in the hotbar.
func _check_stations_and_tools() -> void:
	print("\nstations and tools")
	var world: Node2D = load("res://scenes/world.tscn").instantiate()
	world.seed_override = 20260910
	world.spawn_override_x = 560
	add_child(world)
	for i in 30:
		await get_tree().physics_frame

	var mining = world.mining
	var tiles := TileDB.get_db()
	var here: Vector2i = world.player_tile()
	Game.inventory.clear()

	_ok("standing in an empty field, no station is in reach",
		mining.stations_in_reach().is_empty())

	world.store.set_fg(here.x + 3, here.y, tiles.id("workbench"))
	var near: Dictionary = mining.stations_in_reach()
	_ok("a workbench put down nearby counts", near.has("workbench"), "%s" % near.keys())

	world.store.set_fg(here.x + 3, here.y, 0)
	world.store.set_fg(here.x + 40, here.y, tiles.id("workbench"))
	_ok("one across the map does not", not mining.stations_in_reach().has("workbench"))

	# A pickaxe digs faster than hands, which is the whole reason to make one.
	var by_hand: float = mining.dig_power()
	Game.inventory.add("iron_pick", 1)
	Game.inventory.select(0)
	var with_pick: float = mining.dig_power()
	_ok("bare hands are the slow way", by_hand == Mining.HAND_POWER, "%.0f" % by_hand)
	_ok("a pickaxe digs faster than hands", with_pick > by_hand,
		"%.0f vs %.0f" % [with_pick, by_hand])

	# Placing spends what you are carrying. Find somewhere it is actually
	# allowed first: empty, with rock beside it, or the earlier failure is the
	# support rule refusing rather than the inventory misbehaving.
	var spot := here
	var found := false
	for dx in range(-3, 4):
		for dy in range(-2, 3):
			var c := here + Vector2i(dx, dy)
			if world.store.get_fg(c.x, c.y) == 0 and mining._has_support(c.x, c.y):
				spot = c
				found = true
				break
		if found:
			break
	_ok("there is somewhere a block is allowed", found, "%s" % spot)

	Game.inventory.clear()
	Game.inventory.add("torch", 2)
	Game.inventory.select(0)
	mining._target = spot
	mining._place()
	_ok("placing puts the tile down",
		world.store.get_fg(spot.x, spot.y) == tiles.id("torch"))
	_ok("placing spends one from the stack", Game.inventory.count_of("torch") == 1,
		"%d left" % Game.inventory.count_of("torch"))

	world.store.set_fg(spot.x, spot.y, 0)
	Game.inventory.clear()
	Game.inventory.add("wood_pick", 1)
	Game.inventory.select(0)
	mining._target = spot
	mining._place()
	_ok("a pickaxe is not a block and does not get placed",
		world.store.get_fg(spot.x, spot.y) == 0)
	_ok("and is still in the bag", Game.inventory.count_of("wood_pick") == 1)

	# Pillar jumping: a block under your own feet while off the ground. Refused
	# while standing, because sealing yourself inside one is not the same move.
	Game.inventory.clear()
	Game.inventory.add("stone", 5)
	Game.inventory.select(0)
	var under: Vector2i = world.player_tile() + Vector2i(0, 1)
	world.store.set_fg(under.x, under.y, 0)

	mining._target = under
	mining._place()
	var while_standing: int = world.store.get_fg(under.x, under.y)

	world.player.velocity.y = -180.0
	for i in 3:
		await get_tree().physics_frame
	var airborne: bool = not world.player.is_on_floor()
	mining._target = world.player_tile() + Vector2i(0, 1)
	world.store.set_fg(mining._target.x, mining._target.y, 0)
	mining._place()
	var while_jumping: int = world.store.get_fg(mining._target.x, mining._target.y)

	_ok("the player really did leave the ground", airborne)
	_ok("a block goes down under you while jumping", while_jumping != 0,
		tiles.name_of.get(while_jumping, "nothing"))
	_ok("but not while you are stood on that very tile", while_standing == 0,
		tiles.name_of.get(while_standing, "nothing"))

	# Breaking leaves the material on the ground rather than teleporting it in.
	Game.inventory.clear()
	var dug := here + Vector2i(0, 2)
	while not world.store.is_solid(dug.x, dug.y) and dug.y < here.y + 8:
		dug.y += 1
	var was: int = world.store.get_fg(dug.x, dug.y)
	mining._target = dug
	mining._progress = 9999.0
	mining._dig(0.001)
	await get_tree().process_frame

	var drops := 0
	for node in world.entities.get_children():
		if node is ItemDrop:
			drops += 1
	_ok("breaking a block leaves it on the ground", drops == 1, "%d drops" % drops)
	_ok("and it is what the tile drops",
		drops == 1 and _first_drop(world).item_id == tiles.drop_of(was),
		tiles.drop_of(was))
	_ok("the bag is still empty until it is picked up",
		Game.inventory.count_of(tiles.drop_of(was)) == 0)

	# Walking over it takes it.
	var loose := _first_drop(world)
	loose.global_position = world.player.global_position
	for i in 20:
		await get_tree().physics_frame
	_ok("walking into it picks it up",
		Game.inventory.count_of(tiles.drop_of(was)) == 1,
		"%d" % Game.inventory.count_of(tiles.drop_of(was)))

	# A full bag leaves it lying there rather than destroying it.
	Game.inventory.clear()
	for i in Inventory.SLOTS:
		Game.inventory.add("iron_pick", 1)
	world.spawn_drop(world.player.global_position, "stone", 1)
	for i in 20:
		await get_tree().physics_frame
	var still := 0
	for node in world.entities.get_children():
		if node is ItemDrop and not node.is_queued_for_deletion():
			still += 1
	_ok("a full bag leaves it on the ground rather than eating it", still >= 1,
		"%d still there" % still)

	Game.inventory.clear()
	world.queue_free()
	await get_tree().process_frame


func _first_drop(world: Node2D) -> ItemDrop:
	for node in world.entities.get_children():
		if node is ItemDrop:
			return node
	return null


# ---------------------------------------------------------------------------
func _check_armour() -> void:
	print("\narmour")
	var inv := Inventory.new()
	var db := ItemDB.get_db()

	_ok("armour knows where it goes", str(db.of("iron_mail").get("slot", "")) == "body")
	_ok("nothing worn is no defence", inv.defence() == 0)

	inv.add("copper_helm", 1)
	_ok("you cannot wear what you are not carrying", not inv.equip("iron_helm"))
	_ok("putting it on works", inv.equip("copper_helm"))
	_ok("it leaves the bag when worn", inv.count_of("copper_helm") == 0)
	_ok("and counts toward defence", inv.defence() == 1, "%d" % inv.defence())

	inv.add("copper_mail", 1)
	inv.add("copper_greaves", 1)
	inv.equip("copper_mail")
	inv.equip("copper_greaves")
	_ok("a full set adds up", inv.defence() == 4, "%d" % inv.defence())

	# Swapping a piece puts the old one back rather than losing it.
	inv.add("iron_helm", 1)
	_ok("swapping a piece works", inv.equip("iron_helm"))
	_ok("the old piece comes back to the bag", inv.count_of("copper_helm") == 1)
	_ok("and defence follows the better piece", inv.defence() == 5, "%d" % inv.defence())

	_ok("taking it off returns it", inv.unequip("head") and inv.count_of("iron_helm") == 1)
	_ok("and drops the defence", inv.defence() == 3, "%d" % inv.defence())

	# Armour softens a hit but never removes it.
	Game.inventory.clear()
	Game.health = Game.max_health
	Game.damage(2)
	var bare: int = Game.max_health - Game.health
	Game.health = Game.max_health

	for piece in ["iron_helm", "iron_mail", "iron_greaves"]:
		Game.inventory.add(piece, 1)
		Game.inventory.equip(piece)
	_ok("a full iron set is worth something", Game.inventory.defence() == 7,
		"%d" % Game.inventory.defence())
	Game.damage(2)
	var armoured: int = Game.max_health - Game.health
	_ok("armour softens a hit", armoured < bare, "%d vs %d" % [armoured, bare])
	_ok("but never removes it", armoured >= 1)

	# It survives a save.
	WorldSave.clear()
	var store := ChunkStore.new(99)
	WorldSave.save_world(store, Vector2.ZERO)
	Game.inventory.clear()
	_ok("nothing is worn after clearing", Game.inventory.defence() == 0)
	WorldSave.load_world()
	_ok("what you were wearing comes back", Game.inventory.defence() == 7,
		"%d" % Game.inventory.defence())
	WorldSave.clear()

	Game.inventory.clear()
	Game.health = Game.max_health


# ---------------------------------------------------------------------------
## Chests and life crystals: the Terraria way of getting things, where you go
## and find them rather than grind blocks for them.
func _check_finds() -> void:
	print("\nwhat is in the caves")
	var store := ChunkStore.new(20260910)
	var db := TileDB.get_db()

	# They exist, underground, standing on something.
	var chests: Array[Vector2i] = []
	var crystals := 0
	var floating := 0
	for x in range(400, 1000):
		for y in range(WorldGen.CAVERN_TOP - 60, 760):
			var t := store.get_fg(x, y)
			if t != db.id("chest") and t != db.id("life_crystal"):
				continue
			if not store.is_solid(x, y + 1):
				floating += 1
			if t == db.id("chest"):
				chests.append(Vector2i(x, y))
			else:
				crystals += 1
	_ok("there are chests to find", chests.size() > 4, "%d" % chests.size())
	_ok("there are life crystals to find", crystals > 2, "%d" % crystals)
	_ok("nothing is floating in mid air", floating == 0, "%d floating" % floating)

	# The same seed puts the same chest in the same cave.
	var again := ChunkStore.new(20260910)
	_ok("the same seed puts them in the same places",
		again.get_fg(chests[0].x, chests[0].y) == db.id("chest"))

	# What is inside is worth the walk, and deterministic.
	var loot: Array = store.gen.chest_loot(chests[0].x, chests[0].y)
	var again_loot: Array = again.gen.chest_loot(chests[0].x, chests[0].y)
	_ok("a chest holds several things", loot.size() >= 3, "%d kinds" % loot.size())
	_ok("its contents do not change between visits", str(loot) == str(again_loot))
	var names: Array = []
	for entry: Array in loot:
		names.append(str(entry[0]))
	_ok("it holds something worth having",
		names.any(func(n: String) -> bool: return ItemDB.get_db().kind(n) == "tool"),
		", ".join(names))

	# Deeper chests hold better tools.
	var shallow: Array = store.gen.chest_loot(500, WorldGen.CAVERN_TOP)
	var deep: Array = store.gen.chest_loot(500, WorldGen.HEIGHT - 40)
	var items := ItemDB.get_db()
	var shallow_power := 0
	var deep_power := 0
	for entry: Array in shallow:
		shallow_power = maxi(shallow_power, items.power_of(str(entry[0])))
	for entry: Array in deep:
		deep_power = maxi(deep_power, items.power_of(str(entry[0])))
	_ok("a deep chest beats a shallow one", deep_power > shallow_power,
		"%d vs %d" % [deep_power, shallow_power])

	# Hearts grow, and stop growing.
	Game.max_health = Game.STARTING_HEALTH
	var before := Game.max_health
	_ok("a crystal gives a heart", Game.gain_heart() and Game.max_health == before + 1)
	while Game.gain_heart():
		pass
	_ok("hearts stop at a limit", Game.max_health == Game.MOST_HEALTH,
		"%d" % Game.max_health)
	Game.max_health = Game.STARTING_HEALTH
	Game.health = Game.max_health


# ---------------------------------------------------------------------------
## A tree comes down whole, the way it does in the game this borrows from.
## Chopping one trunk tile at a time is the other game.
func _check_trees() -> void:
	print("\nfelling a tree")
	var world: Node2D = load("res://scenes/world.tscn").instantiate()
	world.seed_override = 20260910
	world.spawn_override_x = 560
	add_child(world)
	for i in 30:
		await get_tree().physics_frame

	var store: ChunkStore = world.store
	var db := TileDB.get_db()
	var trunk := db.id("tree_trunk")

	# Find a tree near spawn and remember how big it is.
	var found := Vector2i(-1, -1)
	for x in range(520, 640):
		var h := store.gen.surface_height(x)
		for y in range(h - 12, h):
			if store.get_fg(x, y) == trunk:
				found = Vector2i(x, y)
				break
		if found.x >= 0:
			break
	_ok("there is a tree to fell", found.x >= 0, "%s" % found)

	var trunks := 0
	for y in range(found.y - 12, found.y + 12):
		if store.get_fg(found.x, y) == trunk:
			trunks += 1
	var leaves_before := 0
	for dy in range(-12, 6):
		for dx in range(-4, 5):
			if store.get_fg(found.x + dx, found.y + dy) == db.id("leaves"):
				leaves_before += 1
	_ok("it is more than one tile tall", trunks > 2, "%d trunk tiles" % trunks)

	Game.inventory.clear()
	world.mining._target = found
	world.mining._progress = 9999.0
	world.mining._dig(0.001)
	await get_tree().process_frame

	var left := 0
	for y in range(found.y - 12, found.y + 12):
		if store.get_fg(found.x, y) == trunk:
			left += 1
	_ok("one chop takes the whole trunk", left == 0, "%d tiles left" % left)

	var leaves_after := 0
	for dy in range(-12, 6):
		for dx in range(-4, 5):
			if store.get_fg(found.x + dx, found.y + dy) == db.id("leaves"):
				leaves_after += 1
	_ok("the canopy goes with it", leaves_after < leaves_before / 2,
		"%d -> %d leaves" % [leaves_before, leaves_after])

	# The wood is on the ground in a few piles.
	var wood_waiting := 0
	for node in world.entities.get_children():
		if node is ItemDrop and node.item_id == "wood":
			wood_waiting += node.amount
	_ok("a whole tree is worth a proper pile of wood", wood_waiting >= trunks * 2,
		"%d wood from %d trunk tiles" % [wood_waiting, trunks])
	_ok("more than a single block would give", wood_waiting >= 4)

	Game.inventory.clear()
	world.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
## The manifest is what lets art be replaced without touching code, so the
## thing worth checking is that it really is the source of what gets drawn.
func _check_art_manifest() -> void:
	print("\nart manifest")
	ArtManifest.reset()

	_ok("art.json loads", ArtManifest.has("player"))
	_ok("it knows the creatures too",
		ArtManifest.has("crawler") and ArtManifest.has("critter"))

	var frames := ArtManifest.frames_for("player")
	_ok("it builds frames for the player", frames != null)
	if frames == null:
		return

	for animation in ["idle", "run", "jump", "fall"]:
		_ok("the player has a %s animation" % animation, frames.has_animation(animation))
	_ok("run is more than one frame", frames.get_frame_count("run") > 1,
		"%d frames" % frames.get_frame_count("run"))

	# Frame size comes from the manifest, not from the code.
	var first: AtlasTexture = frames.get_frame_texture("idle", 0)
	_ok("frames are cut to the size the manifest gives",
		first.region.size == Vector2(20, 30), "%s" % first.region.size)

	_ok("the same frames are shared, not rebuilt per actor",
		ArtManifest.frames_for("player") == frames)
	_ok("asking for something not in the manifest gives nothing back",
		ArtManifest.frames_for("not_a_sprite") == null)

	# The point of the whole thing: a scene keeps working when the manifest
	# has nothing to say, rather than going invisible.
	var player: CharacterBody2D = load("res://scenes/actors/player.tscn").instantiate()
	var sprite: AnimatedSprite2D = player.get_node("Sprite")
	var before := sprite.sprite_frames
	ArtManifest.dress(sprite, "not_a_sprite")
	_ok("an unknown name leaves the scene's own art alone",
		sprite.sprite_frames == before)
	ArtManifest.dress(sprite, "player")
	_ok("a known name replaces it", sprite.sprite_frames == frames)
	player.free()


# ---------------------------------------------------------------------------
## Everything else in the world walks. A thing that does not asks a different
## question of the player, which is the whole reason it exists.
func _check_bats() -> void:
	print("\nsomething that flies")
	var world: Node2D = load("res://scenes/world.tscn").instantiate()
	world.seed_override = 20260910
	world.spawn_override_x = 560
	add_child(world)
	for i in 25:
		await get_tree().physics_frame

	var bat := Bat.new()
	bat.position = world.player.global_position + Vector2(0, -90)
	world.entities.add_child(bat)
	var started: float = bat.global_position.y
	for i in 40:
		await get_tree().physics_frame

	_ok("it does not fall out of the air", bat.global_position.y < started + 80.0,
		"dropped %.0f px" % (bat.global_position.y - started))
	_ok("it does not hover perfectly still",
		bat.global_position.distance_to(Vector2(world.player.global_position.x,
			started)) > 1.0)
	_ok("it counts as something to fight", bat.is_in_group("enemy"))
	_ok("and as something that comes out at night", bat.is_in_group("hostile"))

	# It comes at you rather than wandering off.
	var gap_before: float = bat.global_position.distance_to(world.player.global_position)
	for i in 60:
		await get_tree().physics_frame
	var gap_after: float = bat.global_position.distance_to(world.player.global_position)
	_ok("it hunts rather than drifts", gap_after < gap_before + 40.0,
		"%.0f px -> %.0f px" % [gap_before, gap_after])

	var killed: bool = bat.hurt(5, 1)
	_ok("a swing kills it", killed)
	for i in 20:
		await get_tree().physics_frame
	_ok("and it leaves something behind",
		world.entities.get_children().any(func(n: Node) -> bool:
			return n is ItemDrop and n.item_id == "hide"))

	world.queue_free()
	await get_tree().process_frame
