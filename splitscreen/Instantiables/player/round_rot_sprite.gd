extends Sprite2D
var default_font : Font = ThemeDB.fallback_font;
@export var texture_90 : Texture2D
@export var texture_45 : Texture2D
@export var y_coord_leg = 0
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$AnimationPlayer.play("walk")


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var rot_to_round = get_parent().global_rotation
	var degrees = rad_to_deg(rot_to_round)
	var rounded_rot = snappedi(degrees,45)
	$Player_legs.frame_coords.y = y_coord_leg
	global_position = get_parent().global_position.snapped(Vector2.ONE * 8)
	
	# Maty licensed code 2024 
	match rounded_rot:
		-360:
			global_rotation = deg_to_rad(-360)
			texture = texture_90
		-315:
			global_rotation = deg_to_rad(-360)
			texture = texture_45
		-270:
			global_rotation = deg_to_rad(-270)
			texture = texture_90
		-225:
			global_rotation = deg_to_rad(-360)
			texture = texture_45
		-180:
			global_rotation = deg_to_rad(-180)
			texture = texture_90
		-135:
			global_rotation = deg_to_rad(-180)
			texture = texture_45
		-90:
			global_rotation = deg_to_rad(-90)
			texture = texture_90
		-45:
			global_rotation = deg_to_rad(-90)
			texture = texture_45
		0:
			global_rotation = deg_to_rad(0)
			texture = texture_90
		45:
			global_rotation = deg_to_rad(0)
			texture = texture_45
		90:
			global_rotation = deg_to_rad(90)
			texture = texture_90
		135:
			global_rotation = deg_to_rad(90)
			texture = texture_45
		180:
			global_rotation = deg_to_rad(180)
			texture = texture_90
		225:
			global_rotation = deg_to_rad(180)
			texture = texture_45
		270:
			global_rotation = deg_to_rad(180)
			texture = texture_90
		315:
			global_rotation = deg_to_rad(270)
			texture = texture_45
		360:
			global_rotation = deg_to_rad(360)
			texture = texture_90
	if texture == texture_90: $Player_legs.frame_coords.x = 0
	if texture == texture_45: $Player_legs.frame_coords.x = 1
