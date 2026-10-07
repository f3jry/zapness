extends Node

func get_input_for_index(index):
	var move_x = 0
	var move_y = 0
	var look_x = 0
	var look_y = 0
	var is_shooting = false
	var is_ability = false
	# index should be -1 index -=1 TODO
	move_x = Input.get_axis(str(index) + "_left",str(index) + "_right")
	move_y = Input.get_axis(str(index) + "_up",str(index) + "_down")
	look_x = Input.get_axis(str(index) + "_l_left",str(index) + "_l_right")
	if InputMap.has_action(str(index) + "_l_up") and InputMap.has_action(str(index) + "_l_down"):
		look_y = Input.get_axis(str(index) + "_l_up",str(index) + "_l_down")
	if Input.is_action_pressed(str(index) + "_shoot"): is_shooting = true
	if Input.is_action_just_pressed(str(index) + "_ability"): is_ability = true
	return [Vector2(move_x,move_y),is_shooting,is_ability,Vector2(look_x,look_y)]
