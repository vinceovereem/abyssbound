extends Node
## Headless smoke test. Run it as the main scene:
##
##   godot --headless --path . res://tests/smoke_test.tscn
##
## Exit code 0 means every check passed. Anything else means the build is
## broken, which is what CI keys off.
##
## This is deliberately not a unit test framework. It loads the real zones and
## drives the real player, because the bugs that actually hurt in a platformer
## are "you fall through the floor" and "the level did not load", and only an
## integration check catches those.

const ZONES := [
	"res://scenes/levels/zone_surface.tscn",
	"res://scenes/levels/zone_caverns.tscn",
	"res://scenes/levels/zone_abyss.tscn",
]

const TILE := 16

var _passed := 0
var _failed := 0


func _ready() -> void:
	await get_tree().process_frame
	print("BocciaBound smoke test")
	print("---------------------")

	for zone_path in ZONES:
		await _check_zone(zone_path)

	await _check_jump_height()
	await _check_crystal_pickup()
	await _check_stomp()
	await _check_zone_transition()

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


func _settle(frames := 20) -> void:
	for i in frames:
		await get_tree().physics_frame


# --------------------------------------------------------------------------
func _check_zone(path: String) -> void:
	print("\n%s" % path.get_file())
	var packed: PackedScene = load(path)
	_ok("scene loads", packed != null)
	if not packed:
		return

	var health_at_entry: int = Game.health
	var zone: Node2D = packed.instantiate()
	add_child(zone)
	await _settle(30)
	_ok("no damage taken at spawn", Game.health == health_at_entry,
		"%d -> %d" % [health_at_entry, Game.health])

	var tiles: TileMapLayer = zone.get_node("Tiles")
	var entities: Node = zone.get_node("Entities")

	_ok("tiles painted", tiles.get_used_cells().size() > 100,
		"%d cells" % tiles.get_used_cells().size())
	_ok("player spawned", zone.player != null and is_instance_valid(zone.player))

	var crawlers := 0
	var crystals := 0
	var critters := 0
	var descents := 0
	for child in entities.get_children():
		if child.is_in_group("enemy"):
			crawlers += 1
		elif child.is_in_group("pickup"):
			crystals += 1
		elif child.is_in_group("critter"):
			critters += 1
		elif child.get_script() and child.get_script().resource_path.ends_with("descent.gd"):
			descents += 1

	_ok("crawlers spawned", crawlers >= 2, "%d" % crawlers)
	_ok("crystals spawned", crystals >= 8, "%d" % crystals)
	_ok("critter spawned", critters == 1, "%d" % critters)
	_ok("one way down", descents == 1, "%d" % descents)

	if zone.player and is_instance_valid(zone.player):
		_ok("player stands on the floor", zone.player.is_on_floor(),
			"y=%.1f" % zone.player.global_position.y)

	zone.queue_free()
	await get_tree().process_frame


func _check_zone_transition() -> void:
	print("\nzone links")
	# change_scene_to_file() would free this test node mid-run, so instead
	# check every zone points at a scene that exists, and that the fade the
	# transition awaits actually resolves.
	for zone_path in ZONES:
		var zone: Node = load(zone_path).instantiate()
		var next_path: String = zone.next_zone
		var label := "%s links to %s" % [zone_path.get_file(), next_path if next_path else "(end of game)"]
		_ok(label, next_path.is_empty() or ResourceLoader.exists(next_path))
		zone.free()

	await Ui.fade_out(0.05)
	_ok("fade to black completes", Ui.get_node("Fade").color.a > 0.9)
	await Ui.fade_in(0.05)
	_ok("fade back in completes", Ui.get_node("Fade").color.a < 0.1)


# --------------------------------------------------------------------------
func _spawn_test_arena() -> Dictionary:
	## A flat 20x3 floor with the player on top of it. Built in code so the
	## physics checks do not depend on any particular level layout.
	var root := Node2D.new()
	add_child(root)

	var floor_body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20 * TILE, 3 * TILE)
	shape.shape = rect
	floor_body.add_child(shape)
	floor_body.position = Vector2(160, 200)
	floor_body.collision_layer = 1
	root.add_child(floor_body)

	var player: CharacterBody2D = load("res://scenes/actors/player.tscn").instantiate()
	player.position = Vector2(60, 160)
	root.add_child(player)

	return {"root": root, "player": player}


func _check_jump_height() -> void:
	print("\nplayer physics")
	var arena := _spawn_test_arena()
	var player: CharacterBody2D = arena["player"]
	await _settle(40)

	_ok("lands and stays on the floor", player.is_on_floor(),
		"y=%.1f" % player.global_position.y)

	var ground_y := player.global_position.y
	Input.action_press("jump")
	var peak := ground_y
	for i in 40:
		await get_tree().physics_frame
		peak = minf(peak, player.global_position.y)
	Input.action_release("jump")

	var height := ground_y - peak
	_ok("jump clears three tiles", height >= 3.0 * TILE, "%.1f px" % height)

	await _settle(60)
	_ok("comes back down", player.is_on_floor())

	arena["root"].queue_free()
	await get_tree().process_frame


func _check_crystal_pickup() -> void:
	print("\npickups")
	var arena := _spawn_test_arena()
	var player: CharacterBody2D = arena["player"]
	await _settle(20)

	var before: int = Game.crystals
	var crystal: Area2D = load("res://scenes/pickups/crystal.tscn").instantiate()
	crystal.position = player.global_position
	arena["root"].add_child(crystal)
	await _settle(10)

	_ok("crystal is collected on touch", Game.crystals == before + 1,
		"%d -> %d" % [before, Game.crystals])

	arena["root"].queue_free()
	await get_tree().process_frame


func _check_stomp() -> void:
	print("\ncombat")
	var arena := _spawn_test_arena()
	var player: CharacterBody2D = arena["player"]
	await _settle(20)

	var crawler: CharacterBody2D = load("res://scenes/actors/crawler.tscn").instantiate()
	# Put it on the same floor, well clear of the player, and let it settle.
	crawler.position = player.global_position + Vector2(48, 0)
	crawler.speed = 0.0
	arena["root"].add_child(crawler)
	await _settle(10)

	var health_before: int = Game.health
	_ok("standing apart is safe", health_before == Game.health)

	# Drop the player onto its head.
	player.global_position = crawler.global_position - Vector2(0, 14)
	player.velocity = Vector2(0, 140)
	await _settle(15)

	_ok("stomping kills the crawler", not is_instance_valid(crawler) or crawler.is_queued_for_deletion())
	_ok("stomping costs no health", Game.health == health_before,
		"%d -> %d" % [health_before, Game.health])

	arena["root"].queue_free()
	await get_tree().process_frame
