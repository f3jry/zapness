extends Control

var viewports : Array
var default_pos = []
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	viewports = get_tree().get_nodes_in_group("viewport")
	for i in viewports.size():
		default_pos.append(viewports[i].global_position)
