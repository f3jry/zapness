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
@onready var buttons_container: VBoxContainer = $MarginContainer/Control/buttons

# Discord dynamic lobby list
var lobby_poll_timer: Timer = null
var lobby_list_container: VBoxContainer = null
var active_lobbies: Array = []
var avatar_cache: Dictionary = {} # url -> ImageTexture

func _ready() -> void:
	visible = false
	
	# Hook into network events
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	
	# Setup lobby list container and polling timer
	_setup_discord_lobby_ui()
	
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

func _setup_discord_lobby_ui() -> void:
	lobby_list_container = VBoxContainer.new()
	lobby_list_container.name = "DiscordLobbyList"
	lobby_list_container.add_theme_constant_override("separation", 12)
	# Insert right after status label
	buttons_container.add_child(lobby_list_container)
	buttons_container.move_child(lobby_list_container, 1)
	
	lobby_poll_timer = Timer.new()
	lobby_poll_timer.name = "LobbyPollTimer"
	lobby_poll_timer.wait_time = 1.5
	lobby_poll_timer.autostart = false
	lobby_poll_timer.timeout.connect(_on_lobby_poll_timer_timeout)
	add_child(lobby_poll_timer)

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
		if not has_started_match and _is_in_discord() and not is_hosting_online and not is_connecting_online:
			_poll_discord_lobbies()
			lobby_poll_timer.start()
		else:
			lobby_poll_timer.stop()
			_clear_lobby_cards()
			
		var new_tween = get_tree().create_tween()
		new_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		new_tween.set_trans(Tween.TRANS_QUINT)
		cont_tex.scale = Vector2(1, 0.8)
		gradient.modulate = Color.TRANSPARENT
		new_tween.parallel().tween_property(cont_tex, "scale", Vector2.ONE, anim_speed)
		new_tween.parallel().tween_property(gradient, "modulate", Color.WHITE, anim_speed)
	else:
		lobby_poll_timer.stop()
	
	pause_cooldown.start()

func _is_in_discord() -> bool:
	var dm = get_node_or_null("/root/DiscordManager")
	if dm != null and dm.is_in_discord_call():
		return true
	if OS.has_feature("web"):
		var cid = str(JavaScriptBridge.eval("""
			(function() {
				if (window.GodotDiscord && window.GodotDiscord.channelId) return window.GodotDiscord.channelId;
				try { return new URLSearchParams(window.location.search).get('channel_id') || ''; } catch(e) { return ''; }
			})()
		""", true))
		if not cid.is_empty():
			if dm:
				dm.channel_id = cid
				dm.is_ready = true
			return true
	return false

func _on_lobby_poll_timer_timeout() -> void:
	if is_paused and not has_started_match and _is_in_discord() and not is_hosting_online and not is_connecting_online:
		_poll_discord_lobbies()

func _poll_discord_lobbies() -> void:
	var dm = get_node_or_null("/root/DiscordManager")
	if not dm:
		return
	var lobbies: Array = dm.fetch_lobbies()
	active_lobbies = lobbies
	_update_menu_buttons()

func _clear_lobby_cards() -> void:
	if not lobby_list_container:
		return
	for child in lobby_list_container.get_children():
		child.queue_free()

func _refresh_lobby_list_display() -> void:
	_clear_lobby_cards()
	if not _is_in_discord() or has_started_match or is_hosting_online or is_connecting_online:
		return

	for lobby in active_lobbies:
		var host_id: String = lobby.get("host_peer_id", "")
		var host_name: String = lobby.get("username", "Host")
		var avatar_url: String = lobby.get("avatar", "")
		if host_id.is_empty():
			continue
		
		# Create retro lobby card
		var card = PanelContainer.new()
		var card_style = StyleBoxFlat.new()
		card_style.bg_color = Color(0.12, 0.12, 0.18, 0.95)
		card_style.border_color = Color(0.35, 0.7, 1.0, 0.8)
		card_style.set_border_width_all(2)
		card_style.set_corner_radius_all(6)
		card_style.content_margin_left = 16
		card_style.content_margin_right = 16
		card_style.content_margin_top = 8
		card_style.content_margin_bottom = 8
		card.add_theme_stylebox_override("panel", card_style)
		
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 16)
		card.add_child(hbox)
		
		# Avatar icon
		var avatar_rect = TextureRect.new()
		avatar_rect.custom_minimum_size = Vector2(48, 48)
		avatar_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
		# Default fallback texture (player sprite)
		var default_icon = load("res://Textures/Player/player_tex_color.png")
		avatar_rect.texture = default_icon
		hbox.add_child(avatar_rect)
		
		_load_avatar_texture(avatar_url, avatar_rect)
		
		# Host name label
		var name_label = Label.new()
		name_label.text = host_name + "'s Game"
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 44)
		name_label.modulate = Color(1.0, 1.0, 1.0)
		hbox.add_child(name_label)
		
		# Join button
		var join_btn = Button.new()
		join_btn.text = "JOIN"
		join_btn.add_theme_font_size_override("font_size", 44)
		join_btn.custom_minimum_size = Vector2(140, 48)
		join_btn.pressed.connect(func(): _join_selected_lobby(host_id, host_name))
		hbox.add_child(join_btn)
		
		lobby_list_container.add_child(card)

func _load_avatar_texture(avatar_url: String, target_rect: TextureRect) -> void:
	if avatar_url.is_empty():
		return
	if avatar_cache.has(avatar_url):
		target_rect.texture = avatar_cache[avatar_url]
		return
	
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var img = Image.new()
			var err = img.load_png_from_buffer(body)
			if err != OK:
				err = img.load_jpg_from_buffer(body)
			if err == OK:
				var tex = ImageTexture.create_from_image(img)
				avatar_cache[avatar_url] = tex
				if is_instance_valid(target_rect):
					target_rect.texture = tex
	)
	http.request(avatar_url)

func _join_selected_lobby(host_id: String, host_name: String) -> void:
	if not pause_cooldown.is_stopped():
		return
	is_connecting_online = true
	status_label.text = "Joining " + host_name + "..."
	status_label.modulate = Color(1.0, 0.85, 0.3)
	_update_menu_buttons()
	
	var err = NetworkManager.join_game(host_id)
	if err != OK:
		is_connecting_online = false
		status_label.text = "Failed to join: " + str(err)
		status_label.modulate = Color(1.0, 0.3, 0.3)
		_update_menu_buttons()

func _update_menu_buttons() -> void:
	# Active Match Pause state
	if has_started_match:
		_clear_lobby_cards()
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
		_clear_lobby_cards()
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
		_clear_lobby_cards()
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

	# Main Menu — Discord Activity flow
	if _is_in_discord():
		code_input.visible = false
		btn_quit.visible = false
		
		if active_lobbies.is_empty():
			# No active lobbies: status, "Create Game", and "Practice" at the bottom
			status_label.visible = true
			status_label.text = "No active games in call"
			status_label.modulate = Color(0.7, 0.7, 0.8)
			
			btn_resume.visible = true
			btn_resume.text = "Create Game"
			
			btn_online.visible = false
			
			btn_rate.visible = true
			btn_rate.text = "Practice"
		else:
			# Active lobbies exist: show list, "Create Game", and "Practice" at bottom
			status_label.visible = true
			status_label.text = "Games in Call (" + str(active_lobbies.size()) + ")"
			status_label.modulate = Color(0.4, 1.0, 0.5)
			_refresh_lobby_list_display()
			
			btn_resume.visible = true
			btn_resume.text = "Create Game"
			
			btn_online.visible = false
			
			btn_rate.visible = true
			btn_rate.text = "Practice"
		return

	# Main Menu — Custom code mode (outside Discord)
	if is_custom_code_mode:
		_clear_lobby_cards()
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
	_clear_lobby_cards()
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
	
	# Main menu in Discord -> "Create Game"
	if _is_in_discord():
		is_hosting_online = true
		_update_menu_buttons()
		var err = NetworkManager.host_game("")
		if err != OK:
			is_hosting_online = false
			status_label.text = "Failed to create game!"
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
	
	# In Discord main menu -> "Practice"
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
	_clear_lobby_cards()
	
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
