extends Control
@export var world_parent : SubViewport
var players = []
@export var p_ : Array[Node2D] = []
var switch_players = false
# Called when the node enters the scene tree for the first time.c
func _enter_tree():
	if GameManager.switch_players == false:
		print("screenarea2")
		var index_1 = p_[0].player_index
		if index_1 == 1: p_[0].player_index = 2
		else: p_[0].player_index = 1
		var index_2 = p_[1].player_index
		if index_2 == 1: p_[1].player_index = 2
		else: p_[1].player_index = 1
		var saved = p_[0].get_parent().get_parent()
		var saved_parent = saved.get_parent()
		var saved2 = p_[1].get_parent().get_parent()
		
		saved_parent.get_parent().remove_child(saved) 
		saved_parent.get_parent().remove_child(saved2) 
		saved_parent.call_deferred("add_child",saved2)
		saved_parent.call_deferred("add_child",saved)
func _ready() -> void:
	var world = %worldport
	players = get_tree().get_nodes_in_group("player")
	players[0].other_player = players[1]
	players[1].other_player = players[0]
	var viewports = get_tree().get_nodes_in_group("viewport")
	for i in viewports.size():
		viewports[i].get_child(0).world_2d = %worldport.get_world_2d()
