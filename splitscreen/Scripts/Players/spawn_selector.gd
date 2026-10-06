extends Control

@export var player : Node2D
@export var progress_bar : ProgressBar
var chosen_spawn : Node2D
var spawns_ = []
func setup_choose(spawns):
	for i in spawns:
		create_spawn_icon(i)
	spawns_ = spawns
func create_spawn_icon(spawn):
		var new_spawn = $"../spawn".duplicate()
		new_spawn.position = spawn.global_position.normalized() * 50
		new_spawn.visible = true
		add_child(new_spawn)
func choose_spawn():
	
	var dir = player.last_dir.angle()
	var last_dif = 1000
	var last_spawn
	for i in spawns_:
		var angle 
		var difference = abs(i.global_position.normalized().angle() - dir)
		if difference < last_dif:
			last_dif = difference
			last_spawn = i 
	var pos = last_spawn.global_position
	spawn_player(pos)
	for i in get_child_count():
		get_child(i).queue_free()
	create_spawn_icon(last_spawn)
	await get_tree().create_timer(2.0).timeout
	for i in get_child_count():
		get_child(i).queue_free()
	for i in $"../hiden".get_child_count():
		$"../hiden".get_child(i).queue_free()
func spawn_player(pos):
	player.velocity = Vector2.ZERO
	player.global_position = pos
