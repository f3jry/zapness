extends Node2D

@export var spawns : Array[Node2D]
var players

func _ready() -> void:
	spawns.append($spawns)
	spawns.append($spawns2)
	var players = get_tree().get_nodes_in_group("player")
	for i in players.size():
		var children = spawns[i].get_children()
		#players[i].choose_spawn(children)
