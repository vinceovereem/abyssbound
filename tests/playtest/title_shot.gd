extends Node
## One picture of the title screen, which is the first thing anyone sees.
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://look")
	DisplayServer.window_move_to_foreground()
	add_child(load("res://scenes/main.tscn").instantiate())
	for i in 45:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://look/title.png")
	print("title -> %s" % ProjectSettings.globalize_path("user://look/title.png"))
	get_tree().quit(0)
