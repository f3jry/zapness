extends Sprite2D
func _physics_process(delta: float) -> void:
	var rot = get_parent().global_rotation
	global_rotation = snapped(rot,PI /4)
	global_position = get_parent().global_position.snapped(Vector2.ONE * 8)
