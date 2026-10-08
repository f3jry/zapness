extends Control
@export var world_parent : SubViewport
var players = []
@export var p_ : Array[Node2D] = []
var switch_players = false

func _enter_tree():
	if GameManager.switch_players == false and p_.size() >= 2:
		print("screenarea2")
		var index_1 = p_[0].player_index
		if index_1 == 1: p_[0].player_index = 2
		else: p_[0].player_index = 1
		var index_2 = p_[1].player_index
		if index_2 == 1: p_[1].player_index = 2
		else: p_[1].player_index = 1
		var saved = p_[0].get_parent().get_parent()
		var saved_parent = saved.get_parent() if saved else null
		var saved2 = p_[1].get_parent().get_parent()
		if saved_parent and saved and saved2:
			var idx1 = saved_parent.get_children().find(saved)
			var idx2 = saved_parent.get_children().find(saved2)
			if idx1 != -1 and idx2 != -1:
				saved_parent.move_child(saved, idx2)

func _ready() -> void:
	players = get_tree().get_nodes_in_group("player")
	if players.size() >= 2:
		players[0].other_player = players[1]
		players[1].other_player = players[0]
	var viewports = get_tree().get_nodes_in_group("viewport")
	var world = %worldport
	if world:
		for i in viewports.size():
			if viewports[i].get_child_count() > 0:
				viewports[i].get_child(0).world_2d = world.get_world_2d()
