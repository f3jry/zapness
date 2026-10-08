extends Node2D

@export var viewport : SubViewportContainer
@export var viewport2 : SubViewportContainer
var default_font : Font = ThemeDB.fallback_font;
var latest_col 
@export var mat : ShaderMaterial
@export var collision_exclude : Node2D
@onready var postproc_parent = $"../../../portal2/portal_viewport/portal_sub/CanvasLayer"
@onready var battle_pass
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if viewport and mat:
		viewport.material = mat.duplicate()
	if viewport2 and mat:
		viewport2.material = mat.duplicate()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	global_rotation = 0
	var pm = get_node_or_null("/root/PlayerManager")
	if not pm or not ("players" in pm):
		return
	for i in pm.players:
		if not is_instance_valid(i):
			continue
		var index = i.get("player_index")
		var pos = i.global_position
		var ray = make_a_ray(pos)
		var viewport_to_animate: SubViewportContainer = null
		if index == 1: viewport_to_animate = viewport
		elif index == 2: viewport_to_animate = viewport2
		if not viewport_to_animate or not viewport_to_animate.material:
			continue
		var is_player = ray.has("collider") and ray["collider"] == i
		var old_value = viewport_to_animate.material.get_shader_parameter("transparency")
		if old_value == null:
			old_value = 0.0
		var new_val: float
		if is_player:
			new_val = clampf(float(old_value) + delta * 10.0, 0.0, 1.0)
		else:
			new_val = clampf(float(old_value) - delta * 10.0, 0.0, 1.0)
		viewport_to_animate.material.set_shader_parameter("transparency", new_val)
		if ray.has("collider"):
			latest_col = ray["collider"]
func make_a_ray(pos):
	var space_state = get_world_2d().direct_space_state
	# use global coordinates, not local to node
	var exclude : Array[RID] = []
	if collision_exclude and collision_exclude.has_method("get_rid"):
		exclude.append(collision_exclude.get_rid())
	var query = PhysicsRayQueryParameters2D.create(global_position,pos,-1,exclude)
	query.hit_from_inside = true
	return space_state.intersect_ray(query)
	
