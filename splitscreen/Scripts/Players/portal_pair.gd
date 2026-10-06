extends Node2D

@export var portals : Array[Node2D]
@export var port_viewports : Array[SubViewportContainer]
@export var entrances : Array[Node2D]
var player
var shoot_speed = 3000
@export var laser_info : Node2D
var last_dir = Vector2.ZERO
var last_shot_portal = 0
var normals = [Vector2.ZERO,Vector2.ZERO]
var last_port_pos = Vector2.ZERO
@export var cams : Array[Camera2D]
var last_rays = [Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO]
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for i in portals:
		i.position = Vector2.ZERO
func use(pos,normal):
	if last_shot_portal == 0: last_shot_portal = 1
	elif last_shot_portal == 1: last_shot_portal = 0
	var B = 0
	var A = last_shot_portal
	if A == 0: B = 1
	var old_transforms = [portals[A].global_transform,[port_viewports[A].position,port_viewports[A].rotation],portals[A].get_node("dir_hole").global_transform,entrances[A].global_transform,portals[B].get_node("dir_hole").global_transform,cams[B].global_transform]
	portals[A].global_position = pos
	portals[A].get_node("RayCast2D").target_position = normal * 100
	normals[A] = normal 
	portals[A].get_node("dir_hole").position = normal.normalized() * 128
	
	port_viewports[A].position = -normal.normalized() * 128 - Vector2.ONE * 128
	# rotate viewport along wall normal
	port_viewports[A].rotation = normal.angle()
	# Cam is B
	cams[B].rotation = normal.angle() + PI
	entrances[A].rotation = normal.angle() - PI /2
	align_portal(portals[A],normal,old_transforms)
	cams[A].offset = (cams[A].to_local(portals[B].get_node("dir_hole").global_position)).rotated(cams[A].rotation)
	cams[B].offset = (cams[B].to_local(portals[A].get_node("dir_hole").global_position)).rotated(cams[B].rotation)
func align_portal(portal,normal,old_pos):
	var axis = normal
	var A = portals.find(portal)
	var iterations = 32
	for i in iterations:
		var dir = get_dir(portal)
		if dir == null: 
			#reset portal.
			reset_portal(A,old_pos,portal)
			break
		if dir == Vector2.ZERO: 
			break
	
		portal.global_position += dir.normalized() * 2
	#portal.global_position = portal.global_position.snapped(Vector2.ONE * 8)
	var dir = get_dir(portal)
	if dir == null or dir != Vector2.ZERO: 
		#reset portal for the last time
		reset_portal(A,old_pos,portal)
func get_dir(portal):
	var rayroot = portal.get_node("portal_enter")
	var right_ray_node = portal.get_node("portal_enter/right_al")
	var left_ray_node = portal.get_node("portal_enter/left_al")
	# update rays and we're good
	right_ray_node.force_raycast_update()
	left_ray_node.force_raycast_update()
	
	# isnt in wall and is collidingf
	var right = right_ray_node.is_colliding() and right_ray_node.get_collision_point() != right_ray_node.global_position
	var left = left_ray_node.is_colliding() and left_ray_node.get_collision_point() != left_ray_node.global_position
	var dir = Vector2.ZERO
	if right and !left:
		right_ray_node.position.y -= 1
		dir = rayroot.global_position.direction_to(right_ray_node.global_position)
		right_ray_node.position.y += 1
	elif !right and left:
		left_ray_node.position.y -= 1
		dir = rayroot.global_position.direction_to(left_ray_node.global_position)
		left_ray_node.position.y += 1
	elif !right and !left:
		dir = null
	return dir
func reset_portal(A,old_pos,portal):
	var B = 0
	if A == 0:
		B = 1
	portal.global_transform = old_pos[0]
	var view_trn = old_pos[1]
	port_viewports[A].position = view_trn[0]
	port_viewports[A].rotation = view_trn[1]
	portal.get_node("dir_hole").global_transform = old_pos[2]
	entrances[A].global_transform = old_pos[3]
	portals[B].get_node("dir_hole").global_transform = old_pos[4]
	cams[B].global_transform = old_pos[5]
	laser_info.show_cant()
## @tutorial: gets the direction of the portal
func first_portal_enter(body: Node2D) -> void:
	if !$teleport_timer.is_stopped(): return
	use_portal(portals[1],normals[1],body)
func second_portal_enter(body: Node2D) -> void:
	if !$teleport_timer.is_stopped(): return
	use_portal(portals[0],normals[0],body)
func use_portal(portto,normal,body):
	var pos = portto.global_position
	if portals[0].global_position == Vector2.ZERO or portals[1].global_position == Vector2.ZERO:
		return
	var from_port = port_viewports[0]
	var to_port = port_viewports[1]
	if portto == portals[0]:
		to_port = port_viewports[0]
		from_port = port_viewports[1]
	if body.is_in_group('player'):
		$teleport_timer.start()
		body.global_position = pos
		body.global_rotation -= from_port.rotation - to_port.rotation + PI
		body.cam.reset_smoothing()
	last_dir = Vector2.ZERO
func warp_laser(portal,dir,pos):
	var to_local_offset = portal.to_local(pos)
	var A = portals.find(portal)
	var B = 0
	if A == 0: B = 1
	var ang_diff = port_viewports[A].rotation
	pos = portals[B].get_node("portal_enter").to_local(pos)
	# mirror offset with the rotated func
	var pos_offset = to_local_offset.rotated(PI)
	return [dir.rotated(port_viewports[B].rotation + PI - ang_diff) * 10000, portals[B].get_node("portal_enter").global_position,pos_offset]
func _draw() -> void:
	for i in last_rays.size():
		var mark = Marker2D.new()
		get_parent().add_child(mark)
		mark.global_position = last_rays[i]
