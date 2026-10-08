extends Node
## NetworkManager - WebSocket multiplayer networking for the Discord Activity build.
##
## Replaces the old PeerJS/WebRTC mesh: Discord Activities run in a sandboxed
## iframe where WebRTC is NOT supported and only proxied WebSockets work
## (https://docs.discord.com/developers/activities/development-guides/networking).
## That is why lobbies hung at "peer: connecting.." and never appeared.
##
## New topology:
##   [host client (id 2)] --wss--> [Node.js relay ("peer" 1)] <--wss-- [client (id 3)]
##
## The relay (game-server/server.js) speaks the server side of Godot's
## WebSocketMultiplayerPeer protocol, so the standard high-level multiplayer API
## (rpc(), MultiplayerSynchronizer, signals) works exactly like before - the
## relay just plays the role Godot's "server" (peer 1) normally plays.
## The first client to join a room becomes the game host (id GAME_HOST_PEER_ID).

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_failed()
signal server_started()
signal connected_to_server()
signal lobby_created(lobby_id: String)
signal lobby_joined(lobby_id: String)

const MAX_PLAYERS := 2

## The relay occupies the transport-level "server" slot (peer id 1).
const RELAY_PEER_ID := 1
## The first client in a room - acts as the game host (scoring authority etc).
const GAME_HOST_PEER_ID := 2

## Permanent relay origin (Render). Swap this one line when you deploy —
## e.g. "https://zapness-relay.onrender.com". Used for github.io + native.
## Inside Discord the game uses same-origin /relay/* via the Portal mapping,
## so no client change is needed there.
const DEFAULT_RELAY_ORIGIN := "https://4792-89-103-223-220.ngrok-free.app"
var ws_peer: MultiplayerPeer = null
var is_online_mode: bool = false
var current_lobby_id: String = ""
var _role_host: bool = false

## Override for the relay endpoint, e.g. "wss://zapness.example.com/ws".
## Empty = auto: same origin on web, ws://127.0.0.1:8920/ws for native testing.
@export var relay_url_override: String = ""

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	if _is_web_platform():
		call_deferred("_setup_discord")

func _setup_discord() -> void:
	# The Discord Embedded App SDK handshake (frame_id etc. are injected into
	# the iframe URL by the Discord client). Outside Discord this is skipped.
	if not _has_frame_id():
		print("NetworkManager: not running inside Discord (no frame_id), skipping Discord SDK init")
		return
	var em := get_node_or_null("/root/DiscordEM")
	if em == null:
		push_warning("NetworkManager: DiscordEM autoload not found")
		return
	var client_id := str(ProjectSettings.get_setting("discord/client_id", ""))
	if client_id.is_empty():
		push_warning("NetworkManager: set discord/client_id in project.godot to your Discord application ID")
		return
	em.init(client_id)
	print("Discord SDK initialized (client_id=%s)" % client_id)

func _has_frame_id() -> bool:
	if not _is_web_platform():
		return false
	return "frame_id=" in str(JavaScriptBridge.eval("window.location.search", true))

func _is_web_platform() -> bool:
	return OS.has_feature("web")

## WebSocket endpoint of the relay (no query string).
func _get_relay_url() -> String:
	if not relay_url_override.is_empty():
		return relay_url_override
	if _is_web_platform():
		var proto := str(JavaScriptBridge.eval("window.location.protocol", true))
		var host := str(JavaScriptBridge.eval("window.location.host", true))
		if host.ends_with("discordsays.com"):
			var ws_proto := "wss" if proto == "https:" else "ws"
			return "%s://%s/relay/ws" % [ws_proto, host]
		elif host.ends_with("github.io"):
			return DEFAULT_RELAY_ORIGIN.replace("https://", "wss://") + "/ws"
		var ws_proto := "wss" if proto == "https:" else "ws"
		return "%s://%s/relay/ws" % [ws_proto, host]
	return DEFAULT_RELAY_ORIGIN.replace("https://", "wss://") + "/ws"

## HTTP endpoint of the relay for REST requests (e.g. /lobbies, /health).
func get_relay_http_url(endpoint: String) -> String:
	var path := endpoint if endpoint.begins_with("/") else "/" + endpoint
	if _is_web_platform():
		var proto := str(JavaScriptBridge.eval("window.location.protocol", true))
		var host := str(JavaScriptBridge.eval("window.location.host", true))
		if host.ends_with("discordsays.com"):
			return "%s//%s/relay%s" % [proto, host, path]
		elif host.ends_with("github.io"):
			return DEFAULT_RELAY_ORIGIN + path
		return "%s//%s/relay%s" % [proto, host, path]
	return DEFAULT_RELAY_ORIGIN + path

## -------------------------------------------------------- lobby control ---

## Create a new lobby as host.
func host_game(custom_code: String = "") -> Error:
	var code := custom_code.strip_edges().to_upper()
	if code.is_empty():
		code = _generate_lobby_id()
	var err := _connect_to_relay(code, true)
	if err != OK:
		_reset_state()
	return err

## Join an existing lobby by its room code.
func join_game(lobby_id: String) -> Error:
	var code := lobby_id.strip_edges().to_upper()
	if code.is_empty():
		push_error("NetworkManager: cannot join - empty lobby id")
		return ERR_INVALID_PARAMETER
	var err := _connect_to_relay(code, false)
	if err != OK:
		_reset_state()
	return err

func _connect_to_relay(room_code: String, as_host: bool) -> Error:
	_role_host = as_host
	current_lobby_id = room_code
	if ClassDB.can_instantiate("WebSocketMultiplayerPeer"):
		ws_peer = ClassDB.instantiate("WebSocketMultiplayerPeer")
	else:
		push_error("NetworkManager: WebSocketMultiplayerPeer not available on this platform!")
		return ERR_UNAVAILABLE
	var url := "%s?role=%s&room=%s" % [_get_relay_url(), "host" if as_host else "join", room_code]
	var username := get_discord_username()
	var avatar := get_discord_avatar()
	var channel := get_discord_channel_id()
	if not username.is_empty():
		url += "&user=" + username.uri_encode()
	if not avatar.is_empty():
		url += "&avatar=" + avatar.uri_encode()
	if not channel.is_empty():
		url += "&channel=" + channel.uri_encode()

	var err: Error = ws_peer.create_client(url)
	if err != OK:
		push_error("Failed to start WebSocket client: " + str(err))
		return err
	multiplayer.multiplayer_peer = ws_peer
	is_online_mode = true
	print("NetworkManager: connecting to relay (role=%s, room=%s)" % ["host" if as_host else "join", room_code])
	return OK

func get_discord_channel_id() -> String:
	var em = get_node_or_null("/root/DiscordEM")
	if em and not str(em.get("channel_id")).is_empty():
		return str(em.get("channel_id"))
	if _is_web_platform():
		return str(JavaScriptBridge.eval("""
			(function() {
				try {
					var p = new URLSearchParams(window.location.search);
					return p.get('channel_id') || '';
				} catch(e) { return ''; }
			})()
		""", true))
	return ""

func get_discord_username() -> String:
	var em = get_node_or_null("/root/DiscordEM")
	if em and em.get("current_user_data") != null:
		var u = em.get("current_user_data")
		if not str(u.get("global_name")).is_empty():
			return str(u.get("global_name"))
		if not str(u.get("username")).is_empty():
			return str(u.get("username"))
	return "Player"

func get_discord_avatar() -> String:
	var em = get_node_or_null("/root/DiscordEM")
	if em and em.get("current_user_data") != null:
		var u = em.get("current_user_data")
		var av = str(u.get("avatar"))
		var uid = str(u.get("id"))
		if not av.is_empty() and not uid.is_empty():
			return "https://cdn.discordapp.com/avatars/%s/%s.png?size=128" % [uid, av]
	return ""

## ------------------------------------------------- multiplayer callbacks ---

func _on_connected_to_server() -> void:
	# Fired once the relay accepted us and assigned our peer id. Both the host
	# and the joining client are transport-level clients of the relay.
	print("NetworkManager: connected to relay as peer ", multiplayer.get_unique_id())
	_apply_host_authority()
	if _role_host:
		server_started.emit()
		lobby_created.emit(current_lobby_id)
	else:
		connected_to_server.emit()
		lobby_joined.emit(current_lobby_id)

func _on_peer_connected(peer_id: int) -> void:
	if peer_id == RELAY_PEER_ID:
		return  # the relay itself; handled via connected_to_server
	print("NetworkManager: player joined: ", peer_id)
	player_connected.emit(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	if peer_id == RELAY_PEER_ID:
		return
	print("NetworkManager: player left: ", peer_id)
	player_disconnected.emit(peer_id)

func _on_connection_failed() -> void:
	# The relay closes with 4000 (full) / 4004 (room not found) on bad joins.
	# Note: do NOT null multiplayer.multiplayer_peer here - it is inside the
	# MultiplayerAPI poll when this fires; disconnect_game() does the cleanup.
	print("NetworkManager: connection to relay failed")
	_reset_state()
	connection_failed.emit()

func _on_server_disconnected() -> void:
	print("NetworkManager: relay disconnected")
	disconnect_game()
	player_disconnected.emit(RELAY_PEER_ID)

## ------------------------------------------------------------- lifecycle ---

func disconnect_game() -> void:
	if ws_peer != null:
		ws_peer.close()
	ws_peer = null
	multiplayer.multiplayer_peer = null
	_reset_state()

func _reset_state() -> void:
	ws_peer = null
	is_online_mode = false
	current_lobby_id = ""
	_role_host = false

## ------------------------------------------------------------- queries -----

func is_host() -> bool:
	return is_online_mode and _role_host

## Check if we're in online multiplayer mode
func is_online() -> bool:
	return is_online_mode and ws_peer != null

## Peer id of the game host. NOTE: with the relay the relay itself is "peer 1"
## at the transport level; the first human player (the one who hosted the lobby)
## is GAME_HOST_PEER_ID. Never send RPCs to peer 1.
func game_host_peer_id() -> int:
	return GAME_HOST_PEER_ID

## Get this client's multiplayer peer ID
func get_local_peer_id() -> int:
	return multiplayer.get_unique_id()

## Get all connected player peer IDs (excludes the relay itself)
func get_connected_peers() -> Array[int]:
	var peers: Array[int] = []
	if ws_peer != null:
		for peer_id in multiplayer.get_peers():
			if peer_id != RELAY_PEER_ID:
				peers.append(peer_id)
	return peers

## The score/reset autoload is owned by the lobby host. With the relay topology
## the host is a normal client, so its multiplayer authority must be assigned
## explicitly on every machine (default authority would be the relay, peer 1).
func _apply_host_authority() -> void:
	var score_manager := get_node_or_null("/root/GameManager")
	if score_manager != null:
		score_manager.set_multiplayer_authority(GAME_HOST_PEER_ID)

func _generate_lobby_id() -> String:
	var chars := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var lobby := ""
	for i in 6:
		lobby += chars[randi() % chars.length()]
	return lobby
