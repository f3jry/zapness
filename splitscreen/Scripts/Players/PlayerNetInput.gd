extends BaseNetInput
class_name PlayerNetInput

@export var player: CharacterBody2D

var movement: Vector2 = Vector2.ZERO
var turning: float = 0.0
var is_shooting: bool = false
var is_ability: bool = false

func _ready() -> void:
	super._ready()
	if not player:
		player = get_parent() as CharacterBody2D

func _gather() -> void:
	if not NetworkManager.is_online:
		# Local splitscreen mode
		var idx = 1
		if player and "player_index" in player:
			idx = player.player_index
		var inp = InputManager.get_input_for_index(idx)
		movement = inp[0]
		is_shooting = inp[1]
		is_ability = inp[2]
		turning = inp[3].x
		return

	# Online multiplayer mode - local authority gathers input
	var move_x = Input.get_axis("1_left", "1_right")
	var move_y = Input.get_axis("1_up", "1_down")
	movement = Vector2(move_x, move_y)
	
	turning = Input.get_axis("1_l_left", "1_l_right")
	is_shooting = Input.is_action_pressed("1_shoot")
	is_ability = Input.is_action_just_pressed("1_ability")
