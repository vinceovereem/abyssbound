extends Area2D
## The way down. Walk in, and the next zone loads.

@export_file("*.tscn") var next_zone: String = ""
@export var next_zone_name: String = "Caverns"

@onready var label: Label = $Label

var _used := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	label.visible = false


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	label.visible = true
	if _used:
		return
	_used = true
	if next_zone.is_empty():
		Ui.show_message("The floor gives way to nothing.",
			"That is as deep as the placeholder goes. Press R to start over.")
		return
	Game.change_zone(next_zone, next_zone_name)


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		label.visible = false
