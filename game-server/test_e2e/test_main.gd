extends Node
## E2E test driver: runs one Godot instance (host or client, selected via
## `-- --role=host|client`) against the WebSocket relay and checks the exact
## paths the game uses:
##   - transport handshake and SceneMultiplayer peer admission
##   - targeted rpc_id() from client to host (the _report_death path)
##   - broadcast rpc() host->client and client->host
##   - correct sender attribution via multiplayer.get_remote_sender_id()
## Exits 0 after receiving everything it expects; fails loudly on mismatch
## or the 10 second timeout.

const GAME_HOST_PEER_ID := 2

var role := "host"
var expected := {}   # "kind:msg" -> expected remote sender id
var received := {}
var failed := false

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.substr(7)

	if role == "host":
		expected = {
			"targeted:hi-from-client": 3,
			"bc:bc-from-client": 3,
		}
	else:
		expected = {
			"targeted:hi-from-host": 2,
			"bc:host-bc": 2,
		}

	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.connection_failed.connect(_fail.bind("connection to relay failed"))
	multiplayer.server_disconnected.connect(_fail.bind("relay dropped the connection"))

	var port := OS.get_environment("RELAY_PORT")
	if port.is_empty():
		port = "8922"
	var ws := WebSocketMultiplayerPeer.new()
	var err := ws.create_client(
		"ws://127.0.0.1:%s/ws?role=%s&room=E2E000" % [port, role]
	)
	if err != OK:
		_fail("create_client failed: " + str(err))
		return
	multiplayer.multiplayer_peer = ws

	# hard safety timeout
	get_tree().create_timer(10.0).timeout.connect(
		func(): _fail("timeout, received=" + str(received))
	)

func _on_connected() -> void:
	print("[%s] transport connected, my transport id = %d, peers=%s" % [
		role, multiplayer.get_unique_id(), str(multiplayer.get_peers())
	])
	if role != "client":
		return
	# Client: fire a targeted RPC to the game host and a broadcast, mimicking
	# GameManager_score._report_death.rpc_id(...) and _sync_*.rpc().
	# Wait until the host is admitted (rpc_id to an unknown peer errors).
	for i in 40:
		if multiplayer.get_peers().has(GAME_HOST_PEER_ID):
			break
		await get_tree().create_timer(0.25).timeout
	print("[%s] sending rpc_id(2, hi-from-client) and broadcast, peers=%s server_relay=%s" % [
		role, str(multiplayer.get_peers()), str(multiplayer.server_relay)
	])
	_targeted.rpc_id(GAME_HOST_PEER_ID, "hi-from-client")
	_bc.rpc("bc-from-client")
	_sent = true
	_maybe_pass()

func _on_peer_connected(peer_id: int) -> void:
	print("[%s] multiplayer peer_connected %d" % [role, peer_id])
	if peer_id == 1:
		return
	print("[%s] peer_connected %d" % [role, peer_id])
	print("[%s] server_relay=%s unique=%d peers=%s" % [
		role, str(multiplayer.server_relay), multiplayer.get_unique_id(), str(multiplayer.get_peers())
	])
	if role == "host":
		_targeted.rpc_id(peer_id, "hi-from-host")
		_bc.rpc("host-bc")

# --------------------------------------------------------------- receivers --

@rpc("any_peer", "call_remote", "reliable")
func _targeted(msg: String) -> void:
	_on_msg("targeted", msg, multiplayer.get_remote_sender_id())

@rpc("any_peer", "call_remote", "reliable")
func _bc(msg: String) -> void:
	_on_msg("bc", msg, multiplayer.get_remote_sender_id())

func _on_msg(kind: String, msg: String, sender: int) -> void:
	var key := kind + ":" + msg
	print("[%s] got %s '%s' from sender %d" % [role, kind, msg, sender])
	if not expected.has(kind + ":" + msg):
		_fail("unexpected message '" + msg + "' from " + str(sender))
		return
	if int(expected[key]) != sender:
		_fail("wrong sender for '" + key + "': " + str(sender))
		return
	received[key] = sender
	_maybe_pass()

var _sent := false

func _maybe_pass() -> void:
	# The client must have sent its messages too (it would otherwise quit
	# before its send timer fires). The host sends on peer_connected.
	if role == "client" and not _sent:
		return
	if received.size() >= expected.size():
		print("E2E_PASS ", role)
		get_tree().quit(0)

# --------------------------------------------------------------- helpers ----

func _fail(msg: String) -> void:
	print("E2E_FAIL ", role, ": ", msg)
	get_tree().quit(1)
