extends Sprite2D

var last_string = "aaaaaaa"
var is_sleeping = false
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if is_sleeping:
		global_rotation += 1 * delta
		global_position += global_position.direction_to(get_parent().global_position) * 100 * delta
		visible = true
	else:
		visible = false
func _input(event):
	if event is InputEventKey:
		if !last_string.ends_with(event.as_text_key_label()):
			last_string += event.as_text_key_label()
			last_string = last_string.substr(1)
			if last_string.contains("SLEPICE"): 
				is_sleeping = true
				visible = true
				$"../slejbl".modulate = Color.WHITE
				$"../slejbl".visible = true
				var tree = get_tree().create_tween()
				tree.tween_property($"../slejbl","modulate",Color.TRANSPARENT,5)
		
