extends SubViewportContainer

@export var player : Node2D
@export var viewport : SubViewport
var is_touching = false
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	print("screenarea")
	if player.player_index == 2:
		viewport.set_canvas_cull_mask_bit(2,false)
	else:
		viewport.set_canvas_cull_mask_bit(3,false)
func _process(delta: float) -> void:
	var res = DisplayServer.window_get_size()
	res.x *= 0.5
	#$sub2.size = res 

func _on_area_2d_area_entered(area: Area2D) -> void:
	if area.is_in_group("screenarea"):is_touching = true
func _on_area_2d_area_exited(area: Area2D) -> void:
	if area.is_in_group("screenarea"):is_touching = false
