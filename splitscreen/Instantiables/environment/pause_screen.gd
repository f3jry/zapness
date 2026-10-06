extends Control

var is_paused := false
var has_started_match := false
var is_hosting_online := false
var is_connecting_online := false
var is_custom_code_mode := false

@export var cont_tex: Control
@export var gradient: Control
var anim_speed := 0.15

@onready var status_label: Label = $MarginContainer/Control/buttons/Label
@onready var code_input: LineEdit = $MarginContainer/Control/buttons/LobbyCodeInput
@onready var btn_resume: Button = $MarginContainer/Control/buttons/Resume
@onready var btn_online: Button = $MarginContainer/Control/buttons/online
@onready var btn_rate: Button = $MarginContainer/Control/buttons/Rate
@onready var btn_quit: Button = $MarginContainer/Control/buttons/Quit
@onready var pause_cooldown: Timer = $pause_cooldown

func _ready() -> void:
	visible = false
	
	# Hook into network events
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	
	if has_node("/root/DiscordManager"):
		var dm = get_node("/root/DiscordManager")
		if dm.has_signal("sdk_ready"):
			dm.sdk_ready.connect(func(_u): _update_menu_buttons())
	
	# Initial boot into menu
	if GameManager.rounds_played < 1 and GameManager.new_game == false:
		is_paused = true
		has_started_match = false
		_update_menu_buttons()
		await get_tree().create_timer(0.1).timeout
		call_deferred("update_pause")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if not pause_cooldown.is_stopped():
			return
		
		# If on initial main menu, ignore Escape so players don't accidentally close the menu
		if not has_started_match:
			return
		
		is_paused = not is_paused
		update_pause()

func update_pause() -> void:
	visible = is_paused
	get_tree().paused = is_paused
	
	if is_paused:
		_update_menu_buttons()
		var new_tween = get_tree().create_tween()
		new_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		new_tween.set_trans(Tween.TRANS_QUINT)
		cont_tex.scale = Vector2(1, 0.8)
		gradient.modulate = Color.TRANSPARENT
		new_tween.parallel().tween_property(cont_tex, "scale", Vector2.ONE, anim_speed)
		new_tween.parallel().tween_property(gradient, "modulate", Color.WHITE, anim_speed)
	
	pause_cooldown.start()

func _is_in_discord() -> bool:
	var dm = get_node_or_null("/root/DiscordManager")
	return dm != null and dm.is_in_discord_call()

func _get_call_room_id() -> String:
	var dm = get_node_or_null("/root/DiscordManager")
	return dm.get_call_room_id() if dm != null else ""

func _update_menu_buttons() -> void:
	# Active Match Pause state
	if has_started_match:
		status_label.visible = true
		status_label.text = "Game is paused"
		status_label.modulate = Color.WHITE
		code_input.visible = false
		btn_resume.visible = true
		btn_resume.text = "Resume"
		
		if NetworkManager.is_online():
			btn_online.visible = true
			btn_online.text = "Leave Match"
			btn_rate.visible = false
			btn_quit.visible = false
		else:
			btn_online.visible = true
			btn_online.text = "Restart"
			btn_rate.visible = true
			btn_rate.text = "Main Menu"
			btn_quit.visible = not OS.has_feature("web")
		return

	# Main Menu — Waiting for opponent state
	if is_hosting_online:
		status_label.visible = true
		if _is_in_discord():
			status_label.text = "Hosting match! Waiting for friend in call..."
		else:
			status_label.text = "Hosting! Code: " + NetworkManager.current_lobby_id
		status_label.modulate = Color(1.0, 0.85, 0.3)
		code_input.visible = false
		btn_resume.visible = true
		btn_resume.text = "Cancel"
		btn_online.visible = false
		btn_rate.visible = false
		btn_quit.visible = false
		return

	if is_connecting_online:
		status_label.visible = true
		status_label.text = "Connecting to match..."
		status_label.modulate = Color(1.0, 0.85, 0.3)
		code_input.visible = false
		btn_resume.visible = true
		btn_resume.text = "Cancel"
		btn_online.visible = false
		btn_rate.visible = false
		btn_quit.visible = false
		return

	# Main Menu — Idle Discord Activity state
	if _is_in_discord():
		status_label.visible = true
		status_label.text = "Discord Voice Match Ready"
		status_label.modulate = Color(0.4, 1.0, 0.5)
		code_input.visible = false
		
		btn_resume.visible = true
		btn_resume.text = "Join Call Match"
		btn_online.visible = true
		btn_online.text = "Host Call Match"
		btn_rate.visible = true
		btn_rate.text = "Practice / Local"
		btn_quit.visible = false
		return

	# Main Menu — Custom code mode (outside Discord)
	if is_custom_code_mode:
		status_label.visible = true
		status_label.text = "Online Multiplayer"
		status_label.modulate = Color.WHITE
		code_input.visible = true
		btn_online.visible = true
		btn_online.text = "Connect"
		btn_resume.visible = true
		btn_resume.text = "Host New Game"
		btn_rate.visible = true
		btn_rate.text = "Back"
		btn_quit.visible = false
		return

	# Main Menu — Standard non-Discord idle state
	status_label.visible = false
	code_input.visible = false
	btn_resume.visible = true
	btn_resume.text = "Local Play"
	btn_online.visible = true
	btn_online.text = "Online Match"
	btn_rate.visible = OS.has_feature("web")
	btn_rate.text = "Rate"
	btn_quit.visible = not OS.has_feature("web")
	btn_quit.text = "Quit"

func _on_resume_pressed() -> void:
	if not pause_cooldown.is_stopped():
		return
	
	# Cancel waiting state
	if is_hosting_online or is_connecting_online:
		NetworkManager.disconnect_game()
		is_hosting_online = false
		is_connecting_online = false
		_update_menu_buttons()
		return
	
	# In-game resume
	if has_started_match:
		is_paused = false
		update_pause()
		return
	
	# Main menu in Discord -> "Join Call Match"
	if _is_in_discord():
		var room_id = _get_call_room_id()
		is_connecting_online = true
		_update_menu_buttons()
		var err = NetworkManager.join_game(room_id)
		if err != OK:
			is_connecting_online = false
			status_label.text = "Failed to connect!"
			status_label.modulate = Color(1.0, 0.3, 0.3)
			_update_menu_buttons()
		return
	
	# Main menu outside Discord in custom code mode -> "Host New Game"
	if is_custom_code_mode:
		is_hosting_online = true
		_update_menu_buttons()
		var err = NetworkManager.host_game("")
		if err != OK:
			is_hosting_online = false
			status_label.text = "Failed to start host!"
			status_label.modulate = Color(1.0, 0.3, 0.3)
			_update_menu_buttons()
		return
	
	# Main menu standard -> "Local Play"
	has_started_match = true
	is_paused = false
	update_pause()

func _on_online_pressed() -> void:
	if not pause_cooldown.is_stopped():
		return
	
	# In-game -> "Leave Match"
	if has_started_match and NetworkManager.is_online():
		NetworkManager.disconnect_game()
		has_started_match = false
		is_paused = true
		_update_menu_buttons()
		return
	
	# In-game -> "Restart"
	if has_started_match:
		get_tree().reload_current_scene()
		return
	
	# Main menu in Discord -> "Host Call Match"
	if _is_in_discord():
		var room_id = _get_call_room_id()
		is_hosting_online = true
		_update_menu_buttons()
		var err = NetworkManager.host_game(room_id)
		if err != OK:
			is_hosting_online = false
			status_label.text = "Failed to start host!"
			status_label.modulate = Color(1.0, 0.3, 0.3)
			_update_menu_buttons()
		return
	
	# Custom code mode -> "Connect"
	if is_custom_code_mode:
		var code = code_input.text.strip_edges()
		if code.is_empty():
			status_label.text = "Enter a room code first!"
			status_label.modulate = Color(1.0, 0.4, 0.4)
			return
		is_connecting_online = true
		_update_menu_buttons()
		var err = NetworkManager.join_game(code)
		if err != OK:
			is_connecting_online = false
			status_label.text = "Failed to join: " + str(err)
			status_label.modulate = Color(1.0, 0.3, 0.3)
			_update_menu_buttons()
		return
	
	# Standard outside Discord -> switch to custom code mode
	is_custom_code_mode = true
	_update_menu_buttons()
	code_input.grab_focus()

func _on_rate_pressed() -> void:
	if not pause_cooldown.is_stopped():
		return
	
	# In Discord main menu -> "Practice / Local"
	if not has_started_match and _is_in_discord():
		has_started_match = true
		is_paused = false
		update_pause()
		return
	
	# Custom code mode -> "Back"
	if is_custom_code_mode:
		is_custom_code_mode = false
		_update_menu_buttons()
		return
	
	# In-game local pause -> "Main Menu"
	if has_started_match:
		has_started_match = false
		_update_menu_buttons()
		return
	
	# Standard main menu -> "Rate"
	OS.shell_open("https://ironinblood.itch.io/zapness/rate")

func quit() -> void:
	get_tree().quit()

# ---------------------------------------------------------------------------
# Network Callbacks
# ---------------------------------------------------------------------------

func _on_player_connected(_peer_id: int) -> void:
	is_hosting_online = false
	is_connecting_online = false
	status_label.visible = true
	status_label.text = "Player connected! Starting match..."
	status_label.modulate = Color(0.3, 1.0, 0.4)
	
	await get_tree().create_timer(0.7).timeout
	has_started_match = true
	is_paused = false
	update_pause()

func _on_connection_failed() -> void:
	is_hosting_online = false
	is_connecting_online = false
	status_label.visible = true
	status_label.text = "Connection failed! Check room code."
	status_label.modulate = Color(1.0, 0.3, 0.3)
	_update_menu_buttons()

func _on_player_disconnected(_peer_id: int) -> void:
	if has_started_match and NetworkManager.is_online():
		has_started_match = false
		is_hosting_online = false
		is_connecting_online = false
		is_paused = true
		update_pause()
		status_label.visible = true
		status_label.text = "Opponent disconnected"
		status_label.modulate = Color(1.0, 0.3, 0.3)
