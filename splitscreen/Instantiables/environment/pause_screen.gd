extends Control

var is_paused := false
var has_started_match := false
var is_hosting_online := false
var is_connecting_online := false

@export var cont_tex: Control
@export var gradient: Control
var anim_speed := 0.15

@onready var status_label: Label = $MarginContainer/Control/buttons/Label
@onready var btn_resume: Button = $MarginContainer/Control/buttons/Resume
@onready var btn_online: Button = $MarginContainer/Control/buttons/online
@onready var btn_rate: Button = $MarginContainer/Control/buttons/Rate
@onready var btn_quit: Button = $MarginContainer/Control/buttons/Quit
@onready var pause_cooldown: Timer = $pause_cooldown
@onready var buttons_container: VBoxContainer = $MarginContainer/Control/buttons

# Dynamic lobby list & discovery
var lobby_poll_timer: Timer = null
var lobby_list_container: VBoxContainer = null
var active_lobbies: Array = []
var avatar_cache: Dictionary = {} # url -> ImageTexture
var discovery_ws: WebSocketPeer = null
var discovery_reconnect_timer: float = 0.0
var http_poll_req: HTTPRequest = null
var _last_rendered_lobbies: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	# Ensure button signals are connected
	if not btn_resume.pressed.is_connected(_on_resume_pressed):
		btn_resume.pressed.connect(_on_resume_pressed)
	if not btn_online.pressed.is_connected(_on_online_pressed):
		btn_online.pressed.connect(_on_online_pressed)
	if not btn_rate.pressed.is_connected(_on_rate_pressed):
		btn_rate.pressed.connect(_on_rate_pressed)
	if not btn_quit.pressed.is_connected(quit):
		btn_quit.pressed.connect(quit)

	# Hook into network events
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.lobby_created.connect(_on_lobby_created)
	NetworkManager.lobby_joined.connect(_on_lobby_joined)

	_setup_discord_lobby_ui()
	_connect_discovery_ws()

	# Initial boot into menu
	if GameManager.rounds_played < 1 and GameManager.new_game == false:
		is_paused = true
		has_started_match = false
		_update_menu_buttons()
		await get_tree().create_timer(0.05, true).timeout
		call_deferred("update_pause")

func _process(delta: float) -> void:
	if discovery_ws != null:
		discovery_ws.poll()
		var state = discovery_ws.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			while discovery_ws.get_available_packet_count() > 0:
				var packet = discovery_ws.get_packet()
				var text = packet.get_string_from_utf8()
				var json = JSON.new()
				if json.parse(text) == OK and json.get_data() is Dictionary:
					var data: Dictionary = json.get_data()
					if data.get("type") == "lobbies" and data.get("lobbies") is Array:
						_update_active_lobbies(data["lobbies"])
		elif state == WebSocketPeer.STATE_CLOSED:
			discovery_reconnect_timer += delta
			if discovery_reconnect_timer > 2.5:
				discovery_reconnect_timer = 0.0
				_connect_discovery_ws()

func _setup_discord_lobby_ui() -> void:
	lobby_list_container = VBoxContainer.new()
	lobby_list_container.name = "DiscordLobbyList"
	lobby_list_container.process_mode = Node.PROCESS_MODE_ALWAYS
	lobby_list_container.add_theme_constant_override("separation", 12)
	# Insert right below btn_resume ("Create Game")
	buttons_container.add_child(lobby_list_container)
	var resume_idx = buttons_container.get_children().find(btn_resume)
	if resume_idx >= 0:
		buttons_container.move_child(lobby_list_container, resume_idx + 1)

	# Fallback HTTP polling timer
	lobby_poll_timer = Timer.new()
	lobby_poll_timer.name = "LobbyPollTimer"
	lobby_poll_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	lobby_poll_timer.wait_time = 2.0
	lobby_poll_timer.autostart = false
	lobby_poll_timer.timeout.connect(_on_lobby_poll_timeout)
	add_child(lobby_poll_timer)

	http_poll_req = HTTPRequest.new()
	http_poll_req.name = "LobbyHttpPoll"
	http_poll_req.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http_poll_req)
	http_poll_req.request_completed.connect(_on_http_poll_completed)

func _connect_discovery_ws() -> void:
	var relay_ws_url = NetworkManager._get_relay_url()
	var channel_id = NetworkManager.get_discord_channel_id()
	var url = "%s?role=lobbies" % relay_ws_url
	if not channel_id.is_empty():
		url += "&channel=" + channel_id.uri_encode()

	discovery_ws = WebSocketPeer.new()
	var err = discovery_ws.connect_to_url(url)
	if err != OK:
		print("pause_screen: discovery WS connect failed: ", err)
		discovery_ws = null

func _on_lobby_poll_timeout() -> void:
	if not is_paused or has_started_match or is_hosting_online or is_connecting_online:
		return
	_poll_http_lobbies()

func _poll_http_lobbies() -> void:
	if http_poll_req == null or http_poll_req.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	var channel_id = NetworkManager.get_discord_channel_id()
	var base_url = NetworkManager.get_relay_http_url("/lobbies")
	if not channel_id.is_empty():
		base_url += "?channel=" + channel_id.uri_encode()
	http_poll_req.request(base_url)

func _on_http_poll_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK and json.get_data() is Array:
			_update_active_lobbies(json.get_data())

func _update_active_lobbies(lobbies: Array) -> void:
	active_lobbies = lobbies
	if is_paused and not has_started_match and not is_hosting_online and not is_connecting_online:
		_update_menu_buttons()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if not pause_cooldown.is_stopped():
			return
		if not has_started_match:
			return
		is_paused = not is_paused
		update_pause()

func update_pause() -> void:
	visible = is_paused
	get_tree().paused = is_paused

	if is_paused:
		_update_menu_buttons()
		if not has_started_match and not is_hosting_online and not is_connecting_online:
			lobby_poll_timer.start()
		else:
			lobby_poll_timer.stop()
			_clear_lobby_cards()

		var new_tween = get_tree().create_tween()
		new_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		new_tween.set_trans(Tween.TRANS_QUINT)
		if cont_tex:
			cont_tex.scale = Vector2(1, 0.8)
			new_tween.parallel().tween_property(cont_tex, "scale", Vector2.ONE, anim_speed)
		if gradient:
			gradient.modulate = Color.TRANSPARENT
			new_tween.parallel().tween_property(gradient, "modulate", Color.WHITE, anim_speed)
	else:
		lobby_poll_timer.stop()

	pause_cooldown.start()

func _on_lobby_created(_lobby_id: String) -> void:
	if is_hosting_online:
		status_label.visible = true
		status_label.text = "Hosting match! Waiting for friend in call..."
		status_label.modulate = Color(1.0, 0.85, 0.3)

func _on_lobby_joined(_lobby_id: String) -> void:
	if is_connecting_online:
		status_label.visible = true
		status_label.text = "Connected! Starting match..."
		status_label.modulate = Color(0.4, 1.0, 0.5)

func _clear_lobby_cards() -> void:
	if not lobby_list_container:
		return
	for child in lobby_list_container.get_children():
		child.queue_free()

func _are_lobbies_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		var la = a[i]
		var lb = b[i]
		if not (la is Dictionary and lb is Dictionary):
			return false
		if la.get("roomCode", "") != lb.get("roomCode", ""):
			return false
		if la.get("hostName", "") != lb.get("hostName", ""):
			return false
	return true

func _refresh_lobby_list_display() -> void:
	if has_started_match or is_hosting_online or is_connecting_online:
		_clear_lobby_cards()
		_last_rendered_lobbies.clear()
		return

	if _are_lobbies_equal(active_lobbies, _last_rendered_lobbies):
		return

	_last_rendered_lobbies = active_lobbies.duplicate(true)
	_clear_lobby_cards()

	for lobby in active_lobbies:
		var room_code: String = lobby.get("roomCode", "")
		var host_name: String = lobby.get("hostName", "Host")
		var avatar_url: String = lobby.get("avatar", "")
		if room_code.is_empty():
			continue

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

		var default_icon = load("res://Textures/Player/enemy_tex_color.png")
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
		join_btn.process_mode = Node.PROCESS_MODE_ALWAYS
		join_btn.add_theme_font_size_override("font_size", 44)
		join_btn.custom_minimum_size = Vector2(140, 48)
		join_btn.pressed.connect(func(): _join_selected_lobby(room_code, host_name))
		hbox.add_child(join_btn)

		lobby_list_container.add_child(card)

func _load_avatar_texture(avatar_url: String, target_rect: TextureRect) -> void:
	if avatar_url.is_empty():
		return
	if avatar_cache.has(avatar_url):
		target_rect.texture = avatar_cache[avatar_url]
		return

	var http = HTTPRequest.new()
	http.process_mode = Node.PROCESS_MODE_ALWAYS
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

func _join_selected_lobby(room_code: String, host_name: String) -> void:
	print("pause_screen: JOIN selected lobby ", room_code, " hosted by ", host_name)
	is_connecting_online = true
	status_label.visible = true
	status_label.text = "Joining " + host_name + "..."
	status_label.modulate = Color(1.0, 0.85, 0.3)
	_update_menu_buttons()

	var err = NetworkManager.join_game(room_code)
	if err != OK:
		is_connecting_online = false
		status_label.text = "Failed to join: " + str(err)
		status_label.modulate = Color(1.0, 0.3, 0.3)
		_update_menu_buttons()

func _update_menu_buttons() -> void:
	# Active Match Pause state (during gameplay)
	if has_started_match:
		_clear_lobby_cards()
		status_label.visible = true
		status_label.text = "Game is paused"
		status_label.modulate = Color.WHITE
		btn_resume.visible = true
		btn_resume.text = "Resume"

		if NetworkManager.is_online():
			btn_online.visible = true
			btn_online.text = "Leave Match"
		else:
			btn_online.visible = true
			btn_online.text = "Restart"
		btn_rate.visible = false
		btn_quit.visible = false
		return

	# Main Menu — Waiting for opponent state (Hosting)
	if is_hosting_online:
		_clear_lobby_cards()
		_last_rendered_lobbies.clear()
		status_label.visible = true
		status_label.text = "Hosting match! Waiting for friend in call..."
		status_label.modulate = Color(1.0, 0.85, 0.3)
		btn_resume.visible = true
		btn_resume.text = "Cancel"
		btn_online.visible = false
		btn_rate.visible = false
		btn_quit.visible = false
		return

	# Main Menu — Joining state
	if is_connecting_online:
		_clear_lobby_cards()
		_last_rendered_lobbies.clear()
		status_label.visible = true
		status_label.text = "Connecting to match..."
		status_label.modulate = Color(1.0, 0.85, 0.3)
		btn_resume.visible = true
		btn_resume.text = "Cancel"
		btn_online.visible = false
		btn_rate.visible = false
		btn_quit.visible = false
		return

	# Main Menu — Idle Discord version menu
	# "in the discord version there should be create game, lobbies would show up if there are any in the call and that's all."
	if status_label.text.is_empty():
		status_label.visible = false
	else:
		status_label.visible = true

	btn_resume.visible = true
	btn_resume.text = "Create Game"

	# Hide all extraneous buttons
	btn_online.visible = false
	btn_rate.visible = false
	btn_quit.visible = false

	if not active_lobbies.is_empty():
		_refresh_lobby_list_display()
	else:
		_clear_lobby_cards()
		_last_rendered_lobbies.clear()

func _on_resume_pressed() -> void:
	print("pause_screen: _on_resume_pressed (hosting=", is_hosting_online, " connecting=", is_connecting_online, " has_started=", has_started_match, ")")
	# Cancel hosting or connecting
	if is_hosting_online or is_connecting_online:
		NetworkManager.disconnect_game()
		is_hosting_online = false
		is_connecting_online = false
		status_label.text = ""
		status_label.visible = false
		_clear_lobby_cards()
		_last_rendered_lobbies.clear()
		_update_menu_buttons()
		return

	# In-game resume
	if has_started_match:
		is_paused = false
		update_pause()
		return

	# Main menu -> "Create Game"
	is_hosting_online = true
	status_label.visible = true
	status_label.text = "Creating game..."
	status_label.modulate = Color(1.0, 0.85, 0.3)
	_update_menu_buttons()
	var err = NetworkManager.host_game()
	if err != OK:
		is_hosting_online = false
		status_label.visible = true
		status_label.text = "Failed to create game: " + str(err)
		status_label.modulate = Color(1.0, 0.3, 0.3)
		_update_menu_buttons()

func _on_online_pressed() -> void:
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

func _on_rate_pressed() -> void:
	pass

func quit() -> void:
	get_tree().quit()

# ---------------------------------------------------------------------------
# Network Callbacks
# ---------------------------------------------------------------------------

func _on_player_connected(_peer_id: int) -> void:
	print("pause_screen: player connected! starting match...")
	is_hosting_online = false
	is_connecting_online = false
	status_label.visible = true
	status_label.text = "Player connected! Starting match..."
	status_label.modulate = Color(0.3, 1.0, 0.4)
	_clear_lobby_cards()

	await get_tree().create_timer(0.5, true).timeout
	has_started_match = true
	is_paused = false
	update_pause()

func _on_connection_failed() -> void:
	print("pause_screen: connection failed!")
	is_hosting_online = false
	is_connecting_online = false
	status_label.visible = true
	status_label.text = "Connection failed! Check relay connection."
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
