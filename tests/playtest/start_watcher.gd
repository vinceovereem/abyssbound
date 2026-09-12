extends Node
## Outlives the scene change that starting the game performs, and reports
## whether a playable world actually arrived.

var passed_so_far := 0

var _frames := 0


func _physics_process(_delta: float) -> void:
	_frames += 1
	var world := get_tree().get_first_node_in_group("world")
	var arrived: bool = world != null and is_instance_valid(world) \
		and world.player != null and is_instance_valid(world.player)

	if arrived:
		var tile: Vector2i = world.player_tile()
		print("  PASS  the world loads and the player is in it (tile %s)" % tile)
		print("---------------------")
		print("%d passed, 0 failed" % (passed_so_far + 1))
		get_tree().quit(0)
	elif _frames > 300:
		print("  FAIL  the world never loaded after pressing the key")
		print("---------------------")
		print("%d passed, 1 failed" % passed_so_far)
		get_tree().quit(1)
