extends Area2D
@export var randomizer : AudioStreamRandomizer
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

func p_enter(body: Node2D) -> void:
	if body.is_in_group("player"):body.footstep_manager.stream = randomizer
func p_exit(body: Node2D) -> void:
	if body.is_in_group("player"):body.footstep_manager.stream = AudioStreamRandomizer.new()
