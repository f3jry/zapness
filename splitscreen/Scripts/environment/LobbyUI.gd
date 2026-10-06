extends Control
## Simple Lobby UI for WebRTC multiplayer with PeerJS signaling
## Works with NetworkManager for web exports

signal game_started()
signal back_pressed()

@onready var host_button: Button = $VBoxContainer/HostButton
@onready var join_button: Button = $VBoxContainer/JoinButton
@onready var back_button: Button = $VBoxContainer/BackButton
@onready var lobby_code_input: LineEdit = $VBoxContainer/LobbyCodeInput
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var lobby_code_display: Label = $VBoxContainer/LobbyCodeDisplay

var is_hosting: bool = false
var current_lobby_code: String = ""

func _ready() -> void:
	print("LobbyUI: _ready() called")
	
	# Debug: Check if nodes are found
	if host_button:
		print("LobbyUI: host_button found")
		host_button.pressed.connect(_on_host_pressed)
		print("LobbyUI: host_button.pressed connected")
	else:
		push_error("LobbyUI: host_button NOT FOUND!")
	
	if join_button:
		print("LobbyUI: join_button found")
		join_button.pressed.connect(_on_join_pressed)
		print("LobbyUI: join_button.pressed connected")
	else:
		push_error("LobbyUI: join_button NOT FOUND!")
	
	if back_button:
		print("LobbyUI: back_button found")
		back_button.pressed.connect(_on_back_pressed)
		print("LobbyUI: back_button.pressed connected")
	else:
		push_error("LobbyUI: back_button NOT FOUND!")
	
	NetworkManager.server_started.connect(_on_server_started)
	NetworkManager.lobby_created.connect(_on_lobby_created)
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.connected_to_server.connect(_on_connected_to_server)
	NetworkManager.lobby_joined.connect(_on_lobby_joined)
	
	if has_node("/root/DiscordManager"):
		var dm = get_node("/root/DiscordManager")
		if dm.has_signal("sdk_ready"):
			dm.sdk_ready.connect(func(_user): _reset_ui())
	
	_reset_ui()
	print("LobbyUI: _ready() completed")

func _is_in_discord_call() -> bool:
	var dm = get_node_or_null("/root/DiscordManager")
	return dm != null and dm.is_in_discord_call()

func _get_call_room_id() -> String:
	var dm = get_node_or_null("/root/DiscordManager")
	return dm.get_call_room_id() if dm != null else ""

func _reset_ui() -> void:
	if _is_in_discord_call():
		status_label.text = "In Discord Call"
		join_button.text = "Join Call Match"
	else:
		status_label.text = "Choose an option"
		join_button.text = "Join Game"
	
	lobby_code_display.text = ""
	lobby_code_input.visible = false
	lobby_code_input.text = ""
	host_button.disabled = false
	join_button.disabled = false
	is_hosting = false
	current_lobby_code = ""

func _on_host_pressed() -> void:
	print("LobbyUI: Host button pressed")
	status_label.text = "Starting host..."
	host_button.disabled = true
	join_button.disabled = true
	
	var custom_room := ""
	if _is_in_discord_call():
		custom_room = _get_call_room_id()
	
	var error = NetworkManager.host_game(custom_room)
	if error != OK:
		status_label.text = "Failed to start host: " + str(error)
		_reset_ui()

func _on_join_pressed() -> void:
	print("LobbyUI: Join button pressed")
	if lobby_code_input.visible:
		# Actually join with the entered code
		var lobby_id = lobby_code_input.text.strip_edges()
		if lobby_id.length() < 1:
			status_label.text = "Please enter a valid lobby code"
			return
		
		status_label.text = "Connecting to: " + lobby_id
		host_button.disabled = true
		join_button.disabled = true
		
		var error = NetworkManager.join_game(lobby_id)
		if error != OK:
			status_label.text = "Failed to join: " + str(error)
			_reset_ui()
	elif _is_in_discord_call():
		# Direct one-click join for players in the same Discord voice call
		var call_room = _get_call_room_id()
		status_label.text = "Connecting to call match..."
		host_button.disabled = true
		join_button.disabled = true
		
		var error = NetworkManager.join_game(call_room)
		if error != OK:
			status_label.text = "Failed to join: " + str(error)
			_reset_ui()
	else:
		# Show the lobby code input
		lobby_code_input.visible = true
		lobby_code_input.grab_focus()
		status_label.text = "Enter the host's lobby code"
		join_button.text = "Connect"

func _on_back_pressed() -> void:
	print("LobbyUI: Back button pressed")
	if lobby_code_input.visible:
		_reset_ui()
	elif is_hosting:
		NetworkManager.disconnect_game()
		_reset_ui()
	else:
		NetworkManager.disconnect_game()
		visible = false
		back_pressed.emit()

func _on_server_started() -> void:
	is_hosting = true
	if _is_in_discord_call():
		status_label.text = "Hosting! Waiting for call peer to join..."
	else:
		status_label.text = "Waiting for player to join..."

func _on_lobby_created(lobby_id: String) -> void:
	current_lobby_code = lobby_id
	lobby_code_display.text = "Code: " + lobby_id
	
	if _is_in_discord_call():
		status_label.text = "Call match hosted! Tell friend in call to click Join"
	elif OS.has_feature("web"):
		status_label.text = "Share this code! (Click to copy)"
		lobby_code_display.mouse_filter = Control.MOUSE_FILTER_STOP
		if not lobby_code_display.gui_input.is_connected(_on_lobby_code_clicked):
			lobby_code_display.gui_input.connect(_on_lobby_code_clicked)
	else:
		status_label.text = "Share this code with your opponent!"

func _on_lobby_code_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_copy_lobby_code_to_clipboard()

func _copy_lobby_code_to_clipboard() -> void:
	if current_lobby_code.is_empty():
		return
	
	DisplayServer.clipboard_set(current_lobby_code)
	status_label.text = "Code copied to clipboard!"
	
	# Reset status after a moment
	await get_tree().create_timer(1.5).timeout
	if is_hosting and current_lobby_code != "":
		status_label.text = "Waiting for player to join..."

func _on_lobby_joined(lobby_id: String) -> void:
	status_label.text = "Connecting to lobby..."

func _on_player_connected(peer_id: int) -> void:
	if is_hosting:
		status_label.text = "Player connected! Starting game..."
		await get_tree().create_timer(1.0).timeout
		visible = false
		get_tree().paused = false
		game_started.emit()
	else:
		status_label.text = "Connected! Starting game..."
		await get_tree().create_timer(1.0).timeout
		visible = false
		get_tree().paused = false
		game_started.emit()

func _on_connection_failed() -> void:
	status_label.text = "Connection failed!"
	_reset_ui()

func _on_connected_to_server() -> void:
	status_label.text = "Connected! Waiting for game to start..."

