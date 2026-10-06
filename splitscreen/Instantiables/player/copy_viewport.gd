extends SubViewportContainer

@export var viewport_to_copy : SubViewportContainer
@export var cam_to_copy : Camera2D
@export var own_cam : Camera2D
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	position = viewport_to_copy.position
	rotation = viewport_to_copy.rotation
	own_cam.position = cam_to_copy.position
	own_cam.rotation = cam_to_copy.rotation
	own_cam.offset = cam_to_copy.offset
