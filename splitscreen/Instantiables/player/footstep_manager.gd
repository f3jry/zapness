extends AudioStreamPlayer2D

@export var footsteps : AudioStreamRandomizer
@export var diff_curve : Curve
@export var anim_curve : Curve
@export var walk_anim : Sprite2D
var is_moving = false
var lastpos = Vector2.ZERO
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	var diff = (global_position - lastpos).length()
	is_moving = diff != 0
	# subdivide for the curve
	diff = diff * 0.1
	var sample = diff_curve.sample(diff)
	var anim_sample = anim_curve.sample(diff)
	sample = snapped(sample,0.1)
	anim_sample = snapped(anim_sample,0.1)
	
	$"../Sprite2D/AnimationPlayer".speed_scale = anim_sample
	if sample != $Timer.wait_time:
		$Timer.wait_time = sample
		$Timer.start(sample)
	lastpos = global_position
func _on_timer_timeout() -> void:
	if $Timer.wait_time != 1:
		play()
		walk_anim.visible = true
	else:
		walk_anim.visible = false
