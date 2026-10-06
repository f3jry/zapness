extends Marker2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	$cant.global_position = global_position.snapped(Vector2.ONE * 8)
	$cant.global_rotation = 0
func show_cant(duration = 0.7):
	$cant.modulate = Color.WHITE
	var tw = get_tree().create_tween()
	tw.tween_property($cant,"modulate",Color8(255,255,255,0),duration)
	
