extends Node
var player_scores = [0, 0]
var announcer
var rounds_played = 0
var latest_win_index = 0
var switch_players = false
var new_game = false

func reset_params():
	player_scores = [0, 0]
	rounds_played = 0
	latest_win_index = 0
	switch_players = false
	new_game = true
	
	# Sync reset to all peers
	if NetworkManager.is_online() and NetworkManager.is_host():
		_sync_reset.rpc()

## RPC to sync game reset
@rpc("authority", "call_local", "reliable")
func _sync_reset() -> void:
	player_scores = [0, 0]
	rounds_played = 0
	latest_win_index = 0
	switch_players = false
	new_game = true

func die(index):
	# In online mode, only host handles scoring logic
	if NetworkManager.is_online() and not NetworkManager.is_host():
		# Client just reports the death to host
		# NOTE: the game host is a normal client over the WebSocket relay - the
		# relay itself is transport-level peer 1. Target the game host instead.
		_report_death.rpc_id(NetworkManager.game_host_peer_id(), index)
		return
	
	_handle_death(index)

## RPC for client to report death to host
@rpc("any_peer", "reliable")
func _report_death(index: int) -> void:
	if NetworkManager.is_host():
		_handle_death(index)

func _handle_death(index: int) -> void:
	var win_index = 1
	if index == 1:
		win_index = 0
	player_scores[win_index] += 1
	latest_win_index = win_index
	rounds_played += 1
	print("scores: " + str(player_scores))
	
	# Sync scores to all peers if online
	if NetworkManager.is_online():
		_sync_scores.rpc(player_scores, rounds_played, latest_win_index)
	
	if player_scores.find(4) >= 0:
		print("player " + str(latest_win_index + 1) + " wins")
		announcer.announcement("player " + str(latest_win_index + 1) + " wins")
		reset_params()
		dramatic_pause(0.5, false)
		await get_tree().create_timer(3.0).timeout
		if NetworkManager.is_online():
			_sync_reload_scene.rpc()
		get_tree().reload_current_scene()
		await get_tree().create_timer(0.1).timeout
		announcer.announcement("score 0 - 0")
		return
	dramatic_pause()
	await get_tree().create_timer(2.0).timeout
	if NetworkManager.is_online():
		_sync_reload_scene.rpc()
	get_tree().reload_current_scene()
	if floor(rounds_played / 3) % 2 != 0:
		print("swiching sides" + str(rounds_played % 3))
		switch_players = true
		await get_tree().create_timer(0.1).timeout
		if rounds_played % 3 == 0: announcer.announcement("Switching sides")
	else:
		switch_players = false
		await get_tree().create_timer(0.1).timeout
		if rounds_played % 3 == 0: announcer.announcement("Switching sides")

## RPC to sync scores to all peers
@rpc("authority", "call_local", "reliable")
func _sync_scores(scores: Array, rounds: int, win_idx: int) -> void:
	player_scores = scores
	rounds_played = rounds
	latest_win_index = win_idx

## Round reset reloads the scene; the client must follow the host, or the
## two simulations diverge permanently (dead avatar stays disabled client-side).
## Called by the host right before its own reload (host owns authority).
@rpc("authority", "call_remote", "reliable")
func _sync_reload_scene() -> void:
	get_tree().reload_current_scene()

func dramatic_pause(time = 0.35, announce = true):
	get_tree().paused = true
	var timer = get_tree().create_timer(time)
	await timer.timeout
	get_tree().paused = false
	var score = str(player_scores[1]) + " - " + str(player_scores[0])
	if announce: announcer.announcement("Player " + str(latest_win_index + 1) + " wins" + "\n" + score)
