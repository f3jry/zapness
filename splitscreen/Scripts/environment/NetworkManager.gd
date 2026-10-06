extends Node
## NetworkManager - Handles WebRTC multiplayer networking
## Uses PeerJS for signaling on web platforms
## Add to autoloads in project.godot

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_failed()
signal server_started()
signal connected_to_server()
signal lobby_created(lobby_id: String)
signal lobby_joined(lobby_id: String)

const MAX_PLAYERS := 2
const HOST_PEER_ID := 1

var rtc_peer: WebRTCMultiplayerPeer = null
var is_online_mode: bool = false
var current_lobby_id: String = ""

## Maps PeerJS string IDs to WebRTC integer peer IDs
var peerjs_to_rtc_id: Dictionary = {}
var rtc_to_peerjs_id: Dictionary = {}
var next_peer_id: int = 2

## ICE candidates queue (store until connection is ready)
var pending_ice_candidates: Dictionary = {} # peer_id -> Array of candidates

## Reference to PeerJSBridge autoload
var peerjs_bridge: Node = null

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	# Get PeerJSBridge reference (will be set up after autoloads are ready)
	call_deferred("_setup_peerjs_bridge")

func _setup_peerjs_bridge() -> void:
	if _is_web_platform():
		peerjs_bridge = get_node_or_null("/root/PeerJSBridge")
		if peerjs_bridge:
			peerjs_bridge.peer_opened.connect(_on_peerjs_opened)
			peerjs_bridge.peer_connected.connect(_on_peerjs_peer_connected)
			peerjs_bridge.data_received.connect(_on_peerjs_data_received)
			peerjs_bridge.peer_disconnected.connect(_on_peerjs_peer_disconnected)
			peerjs_bridge.error_occurred.connect(_on_peerjs_error)
			print("NetworkManager: PeerJS bridge connected")
		else:
			push_warning("NetworkManager: PeerJSBridge not found")

func _is_web_platform() -> bool:
	return OS.has_feature("web")

## Create a new WebRTC multiplayer lobby as host
func host_game(custom_lobby_id: String = "") -> Error:
	# Initialize WebRTC mesh
	rtc_peer = WebRTCMultiplayerPeer.new()
	var error = rtc_peer.create_mesh(HOST_PEER_ID)
	if error != OK:
		push_error("Failed to create WebRTC mesh: " + str(error))
		return error
	
	multiplayer.multiplayer_peer = rtc_peer
	is_online_mode = true
	
	# On web, use PeerJS for signaling
	if _is_web_platform() and peerjs_bridge:
		if not peerjs_bridge.host_lobby(custom_lobby_id):
			push_error("Failed to start PeerJS host")
			disconnect_game()
			return ERR_CANT_CREATE
		# lobby_created will be emitted when PeerJS opens
	else:
		# Fallback for non-web: generate local lobby ID
		current_lobby_id = custom_lobby_id if not custom_lobby_id.is_empty() else _generate_lobby_id()
		print("WebRTC host started. Lobby ID: " + current_lobby_id)
		server_started.emit()
		lobby_created.emit(current_lobby_id)
	
	return OK

## Join an existing WebRTC lobby
func join_game(lobby_id: String) -> Error:
	# Initialize WebRTC mesh with random peer ID
	rtc_peer = WebRTCMultiplayerPeer.new()
	var my_rtc_id = randi_range(2, 999999)
	var error = rtc_peer.create_mesh(my_rtc_id)
	if error != OK:
		push_error("Failed to create WebRTC mesh for client: " + str(error))
		return error
	
	multiplayer.multiplayer_peer = rtc_peer
	is_online_mode = true
	current_lobby_id = lobby_id
	
	# On web, use PeerJS to connect to host
	if _is_web_platform() and peerjs_bridge:
		# join_lobby is async - it will initialize PeerJS first if needed
		peerjs_bridge.join_lobby(lobby_id)
		print("Joining lobby via PeerJS: " + lobby_id)
	else:
		print("Joining lobby: " + lobby_id)
		lobby_joined.emit(lobby_id)
	
	return OK

## Add a WebRTC peer connection for another player
func _add_webrtc_peer(rtc_peer_id: int) -> WebRTCPeerConnection:
	var peer_connection = WebRTCPeerConnection.new()
	
	# Configure ICE servers (STUN for NAT traversal)
	var config = {
		"iceServers": [
			{"urls": ["stun:stun.l.google.com:19302"]},
			{"urls": ["stun:stun1.l.google.com:19302"]}
		]
	}
	peer_connection.initialize(config)
	
	# Connect ICE candidate signal
	peer_connection.ice_candidate_created.connect(
		func(media: String, index: int, candidate_name: String):
			_on_ice_candidate_created(rtc_peer_id, media, index, candidate_name)
	)
	
	# Connect session description signal
	peer_connection.session_description_created.connect(
		func(type: String, sdp: String):
			_on_session_description_created(rtc_peer_id, type, sdp)
	)
	
	rtc_peer.add_peer(peer_connection, rtc_peer_id)
	pending_ice_candidates[rtc_peer_id] = []
	
	return peer_connection

## Called when a local ICE candidate is generated
func _on_ice_candidate_created(rtc_peer_id: int, media: String, index: int, candidate: String) -> void:
	if not _is_web_platform() or not peerjs_bridge:
		return
	
	var peerjs_id = rtc_to_peerjs_id.get(rtc_peer_id, "")
	if peerjs_id.is_empty():
		return
	
	# Send ICE candidate via PeerJS
	var ice_data = {
		"type": "ice",
		"media": media,
		"index": index,
		"candidate": candidate
	}
	peerjs_bridge.send_to_peer(peerjs_id, ice_data)

## Called when a local session description (offer/answer) is created
func _on_session_description_created(rtc_peer_id: int, type: String, sdp: String) -> void:
	if not _is_web_platform() or not peerjs_bridge:
		return
	
	# Set local description
	if rtc_peer.has_peer(rtc_peer_id):
		var conn = rtc_peer.get_peer(rtc_peer_id).connection
		conn.set_local_description(type, sdp)
	
	var peerjs_id = rtc_to_peerjs_id.get(rtc_peer_id, "")
	if peerjs_id.is_empty():
		return
	
	# Send SDP via PeerJS
	var sdp_data = {
		"type": type,
		"sdp": sdp
	}
	peerjs_bridge.send_to_peer(peerjs_id, sdp_data)
	print("Sent " + type + " to peer " + peerjs_id)

## PeerJS Callbacks

func _on_peerjs_opened(my_peer_id: String) -> void:
	current_lobby_id = my_peer_id
	print("PeerJS opened. Lobby ID: " + my_peer_id)
	
	if peerjs_bridge and peerjs_bridge.is_host:
		var dm = get_node_or_null("/root/DiscordManager")
		if dm and dm.is_in_discord_call():
			dm.start_hosting_announcement(my_peer_id)
		server_started.emit()
		lobby_created.emit(my_peer_id)
	else:
		lobby_joined.emit(current_lobby_id)

func _on_peerjs_peer_connected(remote_peerjs_id: String) -> void:
	print("PeerJS peer connected: " + remote_peerjs_id)
	
	# Assign or get WebRTC peer ID
	var rtc_id: int
	if peerjs_bridge and peerjs_bridge.is_host:
		# Host assigns peer IDs
		rtc_id = next_peer_id
		next_peer_id += 1
	else:
		# Client connects to host (ID 1)
		rtc_id = HOST_PEER_ID
	
	peerjs_to_rtc_id[remote_peerjs_id] = rtc_id
	rtc_to_peerjs_id[rtc_id] = remote_peerjs_id
	
	# Create WebRTC peer connection
	var peer_conn = _add_webrtc_peer(rtc_id)
	
	# Host creates offer, client waits for offer
	if peerjs_bridge and peerjs_bridge.is_host:
		# Send our RTC ID to the client so they know what ID to use
		peerjs_bridge.send_to_peer(remote_peerjs_id, {
			"type": "rtc_id_assignment",
			"your_rtc_id": rtc_id,
			"host_rtc_id": HOST_PEER_ID
		})
		# Create and send offer
		peer_conn.create_offer()

func _on_peerjs_data_received(from_peerjs_id: String, data: Dictionary) -> void:
	var type = data.get("type", "")
	
	match type:
		"rtc_id_assignment":
			# Client receives their assigned RTC ID from host
			var my_rtc_id = data.get("your_rtc_id", 2)
			var host_rtc_id = data.get("host_rtc_id", HOST_PEER_ID)
			print("Received RTC ID assignment: my_id=" + str(my_rtc_id) + ", host_id=" + str(host_rtc_id))
			
			# Update our mesh with correct ID if different
			# Note: For simplicity, we keep the initial random ID
			
		"offer":
			# Received SDP offer - set remote description and create answer
			var rtc_id = peerjs_to_rtc_id.get(from_peerjs_id, HOST_PEER_ID)
			if rtc_peer.has_peer(rtc_id):
				var conn = rtc_peer.get_peer(rtc_id).connection
				conn.set_remote_description("offer", data.get("sdp", ""))
				# This will trigger session_description_created with answer
			else:
				# Create peer first, then set offer
				var peer_conn = _add_webrtc_peer(rtc_id)
				peerjs_to_rtc_id[from_peerjs_id] = rtc_id
				rtc_to_peerjs_id[rtc_id] = from_peerjs_id
				peer_conn.set_remote_description("offer", data.get("sdp", ""))
			print("Received and processed offer from " + from_peerjs_id)
			
		"answer":
			# Received SDP answer
			var rtc_id = peerjs_to_rtc_id.get(from_peerjs_id, 0)
			if rtc_id > 0 and rtc_peer.has_peer(rtc_id):
				var conn = rtc_peer.get_peer(rtc_id).connection
				conn.set_remote_description("answer", data.get("sdp", ""))
				print("Received and processed answer from " + from_peerjs_id)
				
				# Process any pending ICE candidates
				_process_pending_ice_candidates(rtc_id)
			
		"ice":
			# Received ICE candidate
			var rtc_id = peerjs_to_rtc_id.get(from_peerjs_id, 0)
			var media = data.get("media", "")
			var index = int(data.get("index", 0))
			var candidate = data.get("candidate", "")
			
			if rtc_id > 0 and rtc_peer.has_peer(rtc_id):
				var conn = rtc_peer.get_peer(rtc_id).connection
				# Only add if we have remote description set
				if conn.get_connection_state() != WebRTCPeerConnection.STATE_NEW:
					conn.add_ice_candidate(media, index, candidate)
				else:
					# Queue for later
					if not pending_ice_candidates.has(rtc_id):
						pending_ice_candidates[rtc_id] = []
					pending_ice_candidates[rtc_id].append({
						"media": media,
						"index": index,
						"candidate": candidate
					})

func _process_pending_ice_candidates(rtc_id: int) -> void:
	if not pending_ice_candidates.has(rtc_id):
		return
	
	if not rtc_peer.has_peer(rtc_id):
		return
	
	var conn = rtc_peer.get_peer(rtc_id).connection
	for ice in pending_ice_candidates[rtc_id]:
		conn.add_ice_candidate(ice.media, ice.index, ice.candidate)
	
	pending_ice_candidates[rtc_id].clear()

func _on_peerjs_peer_disconnected(remote_peerjs_id: String) -> void:
	var rtc_id = peerjs_to_rtc_id.get(remote_peerjs_id, 0)
	if rtc_id > 0:
		peerjs_to_rtc_id.erase(remote_peerjs_id)
		rtc_to_peerjs_id.erase(rtc_id)
		pending_ice_candidates.erase(rtc_id)
	print("PeerJS peer disconnected: " + remote_peerjs_id)

func _on_peerjs_error(error_message: String) -> void:
	push_error("PeerJS error: " + error_message)
	connection_failed.emit()

## Disconnect from the current game
func disconnect_game() -> void:
	var dm = get_node_or_null("/root/DiscordManager")
	if dm:
		dm.stop_hosting_announcement()
	if rtc_peer:
		rtc_peer.close()
		rtc_peer = null
	multiplayer.multiplayer_peer = null
	is_online_mode = false
	current_lobby_id = ""
	peerjs_to_rtc_id.clear()
	rtc_to_peerjs_id.clear()
	pending_ice_candidates.clear()
	next_peer_id = 2
	
	# Disconnect PeerJS
	if _is_web_platform() and peerjs_bridge:
		peerjs_bridge.disconnect_all()

## Check if this instance is the host/server
func is_host() -> bool:
	if peerjs_bridge:
		return peerjs_bridge.is_host
	return multiplayer.is_server()

## Check if we're in online multiplayer mode
func is_online() -> bool:
	return is_online_mode and rtc_peer != null

## Get this client's multiplayer peer ID
func get_local_peer_id() -> int:
	return multiplayer.get_unique_id()

## Get all connected peer IDs
func get_connected_peers() -> Array[int]:
	var peers: Array[int] = []
	if rtc_peer:
		for peer_id in multiplayer.get_peers():
			peers.append(peer_id)
		peers.append(get_local_peer_id())
	return peers

## Generate a simple lobby ID for sharing (fallback for non-web)
func _generate_lobby_id() -> String:
	var chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var lobby = ""
	for i in 6:
		lobby += chars[randi() % chars.length()]
	return lobby

func _on_peer_connected(peer_id: int) -> void:
	print("WebRTC Peer connected: " + str(peer_id))
	player_connected.emit(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	print("WebRTC Peer disconnected: " + str(peer_id))
	player_disconnected.emit(peer_id)

func _on_connected_to_server() -> void:
	print("Connected to server!")
	connected_to_server.emit()

func _on_connection_failed() -> void:
	print("Connection failed!")
	rtc_peer = null
	is_online_mode = false
	connection_failed.emit()

func _on_server_disconnected() -> void:
	print("Server disconnected!")
	disconnect_game()
	player_disconnected.emit(1)
