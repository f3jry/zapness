extends Sprite2D
func _physics_process(delta: float) -> void:
	global_position = get_parent().global_position.snapped(Vector2.ONE * 8)
