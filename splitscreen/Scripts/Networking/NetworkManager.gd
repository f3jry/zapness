extends Node
## NetworkManager - Central multiplayer manager for splitscreen and online play

signal connection_status_changed(status: String)
signal player_connected(peer_id: int, player_info: Dictionary)
signal player_disconnected(peer_id: int)
signal match_ready()
signal match_ended()

enum NetworkMode {
	OFFLINE_SPLITSCREEN,
	HOST,
	CLIENT
}

const DEFAULT_PORT: int = 8080
const DEFAULT_HOST: String = "127.0.0.1"

var network_mode: NetworkMode = NetworkMode.OFFLINE_SPLITSCREEN
var peer: MultiplayerPeer = null
var players: Dictionary = {}
var local_peer_id: int = 1
var is_online: bool = false

# WebRTC Bridge reference (for HTML5 browser exports)
@onready var webrtc_bridge = get_node_or_null("/root/PeerJSBridge")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	if OS.has_feature("web") and webrtc_bridge:
		webrtc_bridge.code_ready.connect(_on_webrtc_code_ready)
		webrtc_bridge.connection_opened.connect(_on_webrtc_connected)
		webrtc_bridge.data_received.connect(_on_webrtc_data_received)
		webrtc_bridge.error_occurred.connect(_on_webrtc_error)
		print("[NetworkManager] WebRTC bridge connected.")

# ── Hosting ───────────────────────────────────────────────────────────────────
func host_game(port: int = DEFAULT_PORT) -> Error:
	disconnect_game()
	
	if OS.has_feature("web"):
		return _host_webrtc()
	else:
		return _host_websocket(port)

func _host_websocket(port: int) -> Error:
	var ws_peer = WebSocketMultiplayerPeer.new()
	var error = ws_peer.create_server(port)
	if error != OK:
		connection_status_changed.emit("Failed to create server on port " + str(port))
		return error
	
	peer = ws_peer
	multiplayer.multiplayer_peer = peer
	network_mode = NetworkMode.HOST
	is_online = true
	local_peer_id = 1
	
	players[1] = {
		"peer_id": 1,
		"name": "Host (Player 1)",
		"player_index": 0
	}
	
	connection_status_changed.emit("Server started on port " + str(port) + ". Waiting for players...")
	return OK

func _host_webrtc() -> Error:
	network_mode = NetworkMode.HOST
	is_online = true
	local_peer_id = 1
	
	if webrtc_bridge:
		webrtc_bridge.host_room()
	
	connection_status_changed.emit("Registering room code...")
	return OK

# ── Joining ────────────────────────────────────────────────────────────────────
func join_game(address_or_code: String = DEFAULT_HOST, port: int = DEFAULT_PORT) -> Error:
	disconnect_game()
	
	if OS.has_feature("web"):
		return _join_webrtc(address_or_code)
	else:
		return _join_websocket(address_or_code, port)

func _join_websocket(address: String, port: int) -> Error:
	var target_url = address.strip_edges()
	if not target_url.begins_with("ws://") and not target_url.begins_with("wss://"):
		if not target_url.contains(":"):
			target_url = "ws://" + target_url + ":" + str(port)
		else:
			target_url = "ws://" + target_url
	
	var ws_peer = WebSocketMultiplayerPeer.new()
	var error = ws_peer.create_client(target_url)
	if error != OK:
		connection_status_changed.emit("Failed to connect to " + target_url)
		return error
	
	peer = ws_peer
	multiplayer.multiplayer_peer = peer
	network_mode = NetworkMode.CLIENT
	is_online = true
	
	connection_status_changed.emit("Connecting to " + target_url + "...")
	return OK

func _join_webrtc(room_code: String) -> Error:
	network_mode = NetworkMode.CLIENT
	is_online = true
	local_peer_id = 2
	
	if webrtc_bridge:
		webrtc_bridge.join_room(room_code)
	
	connection_status_changed.emit("Connecting to room '" + room_code.to_upper() + "'...")
	return OK

# ── Disconnect ─────────────────────────────────────────────────────────────────
func disconnect_game() -> void:
	if peer:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null
	network_mode = NetworkMode.OFFLINE_SPLITSCREEN
	is_online = false
	players.clear()
	
	if OS.has_feature("web") and webrtc_bridge:
		webrtc_bridge.disconnect_room()
	
	connection_status_changed.emit("Disconnected")

# ── State Synchronization Over WebRTC / DataChannel ───────────────────────────
func send_player_state(p_idx: int, pos: Vector2, rot: float, vel: Vector2, shoot: bool, ability: bool) -> void:
	if not is_online:
		return
	var pkt = {
		"type": "p_state",
		"idx": p_idx,
		"px": pos.x,
		"py": pos.y,
		"r": rot,
		"vx": vel.x,
		"vy": vel.y,
		"s": shoot,
		"a": ability
	}
	if OS.has_feature("web") and webrtc_bridge:
		webrtc_bridge.send_data(pkt)
	elif peer:
		rpc("rpc_sync_state", pkt)

@rpc("any_peer", "unreliable")
func rpc_sync_state(pkt: Dictionary) -> void:
	_handle_state_packet(pkt)

func _handle_state_packet(data: Dictionary) -> void:
	var p_idx = int(data.get("idx", 0))
	var p_nodes = get_tree().get_nodes_in_group("player")
	for p in p_nodes:
		if p.player_index == p_idx and p.has_method("apply_remote_state"):
			p.apply_remote_state(
				Vector2(data.get("px", 0.0), data.get("py", 0.0)),
				float(data.get("r", 0.0)),
				Vector2(data.get("vx", 0.0), data.get("vy", 0.0)),
				bool(data.get("s", false)),
				bool(data.get("a", false))
			)

# ── WebRTC Signaling & Data Callbacks ─────────────────────────────────────────
func _on_webrtc_code_ready(code: String) -> void:
	print("[NetworkManager] WebRTC room code generated: ", code)
	connection_status_changed.emit("Your code: " + code + "\nShare it with your friend!")

func _on_webrtc_connected(role: String) -> void:
	print("[NetworkManager] WebRTC DataChannel connected with role: ", role)
	if role == "host":
		local_peer_id = 1
		is_online = true
		players[1] = { "peer_id": 1, "name": "Host (Player 1)", "player_index": 1 }
		players[2] = { "peer_id": 2, "name": "Client (Player 2)", "player_index": 2 }
		if webrtc_bridge:
			webrtc_bridge.send_data({
				"type": "start_match",
				"players": players
			})
		connection_status_changed.emit("Opponent connected! Starting match...")
		start_online_match()

func _on_webrtc_data_received(data: Dictionary) -> void:
	var type = data.get("type", "")
	match type:
		"start_match":
			print("[NetworkManager] Client received start_match over WebRTC!")
			local_peer_id = 2
			is_online = true
			if data.has("players"):
				players = data.get("players")
			connection_status_changed.emit("Connected! Starting match...")
			start_online_match()
		"p_state":
			_handle_state_packet(data)

func _on_webrtc_error(message: String) -> void:
	print("[NetworkManager] WebRTC error: ", message)
	connection_status_changed.emit("Connection error: " + message)

# ── General Multiplayer Callbacks ─────────────────────────────────────────────
func _on_peer_connected(id: int) -> void:
	print("[NetworkManager] WebSocket Peer connected: ", id)
	if multiplayer.is_server():
		players[id] = {
			"peer_id": id,
			"name": "Client (Player 2)",
			"player_index": 2
		}
		rpc("sync_players", players)
		connection_status_changed.emit("Player 2 connected! Starting match...")
		rpc("start_online_match")

func _on_peer_disconnected(id: int) -> void:
	print("[NetworkManager] Peer disconnected: ", id)
	players.erase(id)
	player_disconnected.emit(id)
	connection_status_changed.emit("Opponent disconnected.")

func _on_connected_to_server() -> void:
	local_peer_id = multiplayer.get_unique_id()
	print("[NetworkManager] Connected to server as peer: ", local_peer_id)
	connection_status_changed.emit("Connected! Waiting for host to start...")

func _on_connection_failed() -> void:
	print("[NetworkManager] Connection failed.")
	connection_status_changed.emit("Connection failed. Check room code.")
	disconnect_game()

func _on_server_disconnected() -> void:
	print("[NetworkManager] Server disconnected.")
	connection_status_changed.emit("Server disconnected.")
	disconnect_game()
	match_ended.emit()

@rpc("authority", "call_local", "reliable")
func sync_players(p_data: Dictionary) -> void:
	players = p_data

@rpc("authority", "call_local", "reliable")
func start_online_match() -> void:
	print("[NetworkManager] START ONLINE MATCH TRIGGERED!")
	connection_status_changed.emit("Match starting!")
	match_ready.emit()
	if get_tree().current_scene and get_tree().current_scene.scene_file_path != "res://Instantiables/environment/main.tscn":
		get_tree().change_scene_to_file("res://Instantiables/environment/main.tscn")
	else:
		GameManager.reset_params()
