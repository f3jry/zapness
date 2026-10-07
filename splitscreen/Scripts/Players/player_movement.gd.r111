extends CharacterBody2D
var speed = 7500
var speed_sideways = 5250
var health = 1
@export var player_index = 0
@export var cam: Camera2D
@export var portal_pair: Node2D
@export var footstep_manager: AudioStreamPlayer2D
var last_dir = Vector2.UP
var ability = 0
var last_ray = Vector2.ZERO
var laser_has_portal = false
@export var laser_info: Node2D
var latest_rotation_offset = 0
var proc_dist = 48
var other_player = null
@export var portal_particle: CPUParticles2D

## Multiplayer: tracks if this player is controlled locally
var is_local_player: bool = true
## Multiplayer: network peer ID that owns this player
var network_peer_id: int = 1

func _ready() -> void:
	$Line2D.points = [Vector2.ZERO, Vector2.ZERO]
	$Line2D.modulate = Color.TRANSPARENT
	
	# Setup multiplayer authority if in online mode
	if NetworkManager.is_online():
		is_local_player = _is_owned_by_local_peer()
		if is_local_player:
			set_multiplayer_authority(multiplayer.get_unique_id())

func _is_owned_by_local_peer() -> bool:
	# In online mode, player_index 1 belongs to host, player_index 2 to client
	if NetworkManager.is_host():
		return player_index == 1
	else:
		return player_index == 2

func _physics_process(delta: float) -> void:
	# Only process input for local players (or in local mode)
	if NetworkManager.is_online() and not is_local_player:
		# Still run move_and_slide for physics, but don't process input
		move_and_slide()
		return
	
	var inputs = InputManager.get_input_for_index(player_index)
	var is_shooting = inputs[1]
	var laser = $laser_cast
	if is_shooting:
		shoot()
	if inputs[2]: use_ability()
	if inputs[3] != Vector2.ZERO:
		last_dir = inputs[3]
	velocity *= 0.80
	
	# newly rotated by angle
	global_rotation += inputs[3].x * delta * 4
	var what_speed = speed
	if inputs[0].x != 0 or inputs[0].y == 1: what_speed = speed_sideways
	velocity += inputs[0].rotated(global_rotation) * delta * what_speed
	%proc_marker.position = Vector2.UP * 125
	$portal_cast.target_position = Vector2.UP * 2560
	laser.target_position = $portal_cast.target_position
	%shoot_progress.value = $shoot_timer.time_left
	%shoot_progress.modulate.a = $shoot_timer.time_left
	move_and_slide()
	
	# Sync position/rotation to remote peers in online mode
	if NetworkManager.is_online() and is_local_player:
		_sync_transform.rpc(global_position, global_rotation, velocity)
	
	# warp laser through portals
	if laser.is_colliding() and laser.get_collider().is_in_group("portal"):
		var pair
		var col = laser.get_collider()
		var portal = col.get_parent().get_parent()
		var offset = laser.get_collision_point()
		pair = col.get_parent().get_parent().get_parent().warp_laser(portal, laser.target_position.normalized(), offset)
		if pair:
			$portal_laser.global_position = pair[1] + pair[2]
			$portal_laser.target_position = pair[0]
			laser_has_portal = true
	else:
		laser_has_portal = false
	$portal_laser.visible = laser_has_portal

## RPC to sync transform to remote peers
@rpc("any_peer", "unreliable_ordered")
func _sync_transform(pos: Vector2, rot: float, vel: Vector2) -> void:
	if not is_local_player:
		global_position = pos
		global_rotation = rot
		velocity = vel

func damage(dmg = 0):
	health -= dmg
	modulate = Color.RED
	var tween = get_tree().create_tween()
	tween.tween_property(self, "modulate", Color.PALE_VIOLET_RED, 0.3)
	if health <= 0:
		die()
		
func die():
	if NetworkManager.is_online():
		_sync_death.rpc()
	GameManager.die(player_index)
	print(name + " died")
	process_mode = PROCESS_MODE_DISABLED

## RPC to sync death to all peers
@rpc("any_peer", "call_local", "reliable")
func _sync_death() -> void:
	process_mode = PROCESS_MODE_DISABLED
	
func shoot():
	if $shoot_timer.is_stopped() and last_dir != Vector2.ZERO:
		last_dir = last_dir.normalized()
		var laser_cast = $laser_cast
		var ported_laser = $laser_cast/laser_cast2
		$shoot_timer.start()
		$laser_sound.play()
		
		# Sync shoot effect to remote peers
		if NetworkManager.is_online() and is_local_player:
			_sync_shoot.rpc()
		
		# Warping laser in portal
		if laser_cast.is_colliding():
			if laser_cast.get_collider().is_in_group("player"):
				laser_cast.get_collider().damage(10)
			if $portal_laser.is_colliding() and $portal_laser.get_collider().is_in_group("player"):
				$portal_laser.get_collider().damage(10)
			var local_pos = laser_cast.get_collision_point()
			$AnimationPlayer.play("laser_flash")
		
			# laser effect
			var laser_offset = Vector2.UP.rotated(global_rotation) * 80
			$Line2D.points = [(global_position + laser_offset).snapped(Vector2.ONE * 8), local_pos.snapped(Vector2.ONE * 8)]
			$Line2D.modulate = Color.WHITE
			
			$Line2D/laser_blast.global_position = global_position + laser_offset
			$Line2D/laser_blast2.global_position = local_pos.snapped(Vector2.ONE * 8)
			if laser_has_portal:
				$portal_laser_line.points = [$portal_laser.global_position.snapped(Vector2.ONE * 8), $portal_laser.get_collision_point().snapped(Vector2.ONE * 8)]
				$Line2D/laser_blast2.global_position = $portal_laser.get_collision_point()
				$portal_laser_line.modulate = Color.WHITE
			var tween = get_tree().create_tween()
			tween.parallel().tween_property($Line2D, "modulate", Color8(255, 0, 0, 0), 0.3)
			tween.parallel().tween_property($portal_laser_line, "modulate", Color8(255, 0, 0, 0), 0.3)
		last_dir = last_dir.rotated(randf_range(-TAU, TAU) / 180).normalized()

## RPC to sync shoot visual/audio effects
@rpc("any_peer", "call_local", "reliable")
func _sync_shoot() -> void:
	if not is_local_player:
		$shoot_timer.start()
		$laser_sound.play()
		$AnimationPlayer.play("laser_flash")

func use_ability():
	if $ability_timer.is_stopped():
		$ability_timer.start()
		var sel_ability = %abilities.get_child(ability)
		if sel_ability and !$portal_cast.get_collider().is_in_group("player") and !$portal_cast.get_collider().is_in_group("portal"):
			var collision_point = $portal_cast.get_collision_point()
			var collision_normal = $portal_cast.get_collision_normal()
			sel_ability.use(collision_point, collision_normal)
			portal_particle.emitting = true
			$portal_sound.play()
			
			# Sync ability use to remote peers
			if NetworkManager.is_online() and is_local_player:
				_sync_ability.rpc(collision_point, collision_normal)
		else:
			laser_info.show_cant()

## RPC to sync ability use
@rpc("any_peer", "call_local", "reliable")
func _sync_ability(collision_point: Vector2, collision_normal: Vector2) -> void:
	if not is_local_player:
		var sel_ability = %abilities.get_child(ability)
		if sel_ability:
			sel_ability.use(collision_point, collision_normal)
			portal_particle.emitting = true
			$portal_sound.play()
		
func choose_spawn(spawns):
	%spawns.setup_choose(spawns)
	%choose_spawn_timer.start()
