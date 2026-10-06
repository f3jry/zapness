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
	viewport.material = mat.duplicate()
	viewport2.material = mat.duplicate()
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	global_rotation = 0
	for i in $/root/PlayerManager.players:
		var index = i.player_index
		var pos = i.global_position
		var ray = make_a_ray(pos)
		var viewport_to_animate = null
		if index == 1: viewport_to_animate = viewport
		if index == 2: viewport_to_animate = viewport2
		var is_player = ray.has("collider") and ray["collider"] == i
		var old_value = viewport_to_animate.material.get_shader_parameter("transparency")
		if is_player: viewport_to_animate.material.set_shader_parameter("transparency",clamp(old_value + delta * 10,0,1))
		else:viewport_to_animate.material.set_shader_parameter("transparency",clamp(old_value - delta * 10,0,1))
		if ray.has("collider"):latest_col = ray["collider"]
func make_a_ray(pos):
	var space_state = get_world_2d().direct_space_state
	# use global coordinates, not local to node
	var exclude : Array[RID]
	exclude.append(collision_exclude)
	var query = PhysicsRayQueryParameters2D.create(global_position,pos,-1,exclude)
	query.hit_from_inside = true
	return space_state.intersect_ray(query)
	
