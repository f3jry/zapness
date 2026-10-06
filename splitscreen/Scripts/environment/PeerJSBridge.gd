extends Node
## PeerJSBridge - Bridges PeerJS (JavaScript) with Godot for web multiplayer signaling
## This only works in web/HTML5 exports!
## Add to autoloads in project.godot

signal peer_opened(my_peer_id: String)
signal peer_connected(remote_peer_id: String)
signal data_received(from_peer_id: String, data: Dictionary)
signal peer_disconnected(remote_peer_id: String)
signal error_occurred(error_message: String)

## Our local peer ID assigned by PeerJS
var my_peer_id: String = ""
## Most recent error message from PeerJS
var last_error: String = ""
## Whether we're the host of the session
var is_host: bool = false
## Whether PeerJS is initialized and ready
var is_ready: bool = false
## Connected peer IDs
var connected_peers: Array[String] = []

## JavaScript callback references (prevent garbage collection)
var _js_callbacks: Array = []

func _ready() -> void:
	if not _is_web_platform():
		push_warning("PeerJSBridge: Not running on web platform. PeerJS functionality disabled.")
		return
	
	# Set up JavaScript callbacks
	_setup_js_callbacks()

## Check if running on web platform
func _is_web_platform() -> bool:
	return OS.has_feature("web")

func _setup_js_callbacks() -> void:
	if not _is_web_platform():
		return
	
	var window = JavaScriptBridge.get_interface("window")
	if not window:
		return
	
	# Create callback for peer open event
	var on_open = JavaScriptBridge.create_callback(_on_js_peer_open)
	_js_callbacks.append(on_open)
	window._godotPeerOnOpen = on_open
	
	# Create callback for peer connected event
	var on_connected = JavaScriptBridge.create_callback(_on_js_peer_connected)
	_js_callbacks.append(on_connected)
	window._godotPeerOnConnected = on_connected
	
	# Create callback for data received event
	var on_data = JavaScriptBridge.create_callback(_on_js_data_received)
	_js_callbacks.append(on_data)
	window._godotPeerOnData = on_data
	
	# Create callback for peer disconnected event
	var on_disconnected = JavaScriptBridge.create_callback(_on_js_peer_disconnected)
	_js_callbacks.append(on_disconnected)
	window._godotPeerOnDisconnected = on_disconnected
	
	# Create callback for error event
	var on_error = JavaScriptBridge.create_callback(_on_js_error)
	_js_callbacks.append(on_error)
	window._godotPeerOnError = on_error
	
	JavaScriptBridge.eval("""
		(function() {
			function bind() {
				if (window.GodotPeerJS) {
					if (window._godotPeerOnOpen) window.GodotPeerJS.onPeerOpen = window._godotPeerOnOpen;
					if (window._godotPeerOnConnected) window.GodotPeerJS.onPeerConnected = window._godotPeerOnConnected;
					if (window._godotPeerOnData) window.GodotPeerJS.onDataReceived = window._godotPeerOnData;
					if (window._godotPeerOnDisconnected) window.GodotPeerJS.onPeerDisconnected = window._godotPeerOnDisconnected;
					if (window._godotPeerOnError) window.GodotPeerJS.onError = window._godotPeerOnError;
				} else {
					setTimeout(bind, 50);
				}
			}
			bind();
		})();
	""", true)

## Initialize PeerJS connection
## @param custom_id: Optional custom peer ID (leave empty for random)
## @return: true if initialization started successfully
func initialize(custom_id: String = "") -> bool:
	if not _is_web_platform():
		push_error("PeerJSBridge: Cannot initialize - not on web platform")
		return false
	
	# Check if GodotPeerJS is available
	var check = JavaScriptBridge.eval("typeof window.GodotPeerJS !== 'undefined'", true)
	if not check:
		push_error("PeerJSBridge: GodotPeerJS not found. Make sure peerjs_bridge.js is loaded.")
		return false
	
	# Initialize PeerJS
	var result = JavaScriptBridge.eval(
		"window.GodotPeerJS.initialize('" + custom_id.replace("'", "\\'") + "')",
		true
	)
	return result == true

## Host a new lobby - initializes PeerJS and waits for peer_opened signal
## @param custom_id: Optional custom peer ID
## @return: true if hosting started successfully
func host_lobby(custom_id: String = "") -> bool:
	is_host = true
	return initialize(custom_id)

## Join an existing lobby by connecting to host's peer ID
## @param host_peer_id: The peer ID of the host to connect to
## @return: true if connection attempt started successfully
func join_lobby(host_peer_id: String) -> bool:
	if not _is_web_platform():
		return false
	
	if host_peer_id.is_empty():
		push_error("PeerJSBridge: Cannot join - empty peer ID")
		return false
	
	is_host = false
	
	# First initialize if not already
	if not is_ready:
		if not initialize():
			return false
		# Wait for initialization
		await peer_opened
	
	# Now connect to the host
	var result = JavaScriptBridge.eval(
		"window.GodotPeerJS.connectToPeer('" + host_peer_id.replace("'", "\\'") + "')",
		true
	)
	return result == true

## Send data to a specific peer
## @param peer_id: Target peer ID
## @param data: Dictionary of data to send
## @return: true if send was successful
func send_to_peer(peer_id: String, data: Dictionary) -> bool:
	if not _is_web_platform() or not is_ready:
		return false
	
	var json_data = JSON.stringify(data).replace("'", "\\'").replace("\n", "\\n")
	var result = JavaScriptBridge.eval(
		"window.GodotPeerJS.sendToPeer('" + peer_id.replace("'", "\\'") + "', '" + json_data + "')",
		true
	)
	return result == true

## Broadcast data to all connected peers
## @param data: Dictionary of data to send
## @return: Number of peers data was sent to
func broadcast(data: Dictionary) -> int:
	if not _is_web_platform() or not is_ready:
		return 0
	
	var json_data = JSON.stringify(data).replace("'", "\\'").replace("\n", "\\n")
	var result = JavaScriptBridge.eval(
		"window.GodotPeerJS.broadcast('" + json_data + "')",
		true
	)
	return result if result else 0

## Get list of connected peer IDs
func get_connected_peers() -> Array[String]:
	return connected_peers.duplicate()

## Check if connected to a specific peer
func is_connected_to(peer_id: String) -> bool:
	return peer_id in connected_peers

## Disconnect from a specific peer
func disconnect_from(peer_id: String) -> void:
	if not _is_web_platform():
		return
	
	JavaScriptBridge.eval(
		"window.GodotPeerJS.disconnectFrom('" + peer_id.replace("'", "\\'") + "')",
		true
	)

## Disconnect from all peers and clean up
func disconnect_all() -> void:
	if not _is_web_platform():
		return
	
	JavaScriptBridge.eval("window.GodotPeerJS.disconnect()", true)
	my_peer_id = ""
	is_host = false
	is_ready = false
	connected_peers.clear()

## JavaScript callback handlers

func _on_js_peer_open(args: Array) -> void:
	if args.size() > 0:
		my_peer_id = str(args[0])
		is_ready = true
		last_error = ""
		print("PeerJSBridge: Peer opened with ID: " + my_peer_id)
		peer_opened.emit(my_peer_id)

func _on_js_peer_connected(args: Array) -> void:
	if args.size() > 0:
		var remote_id = str(args[0])
		if remote_id not in connected_peers:
			connected_peers.append(remote_id)
		print("PeerJSBridge: Peer connected: " + remote_id)
		peer_connected.emit(remote_id)

func _on_js_data_received(args: Array) -> void:
	if args.size() >= 2:
		var from_peer = str(args[0])
		var json_str = str(args[1])
		
		var json = JSON.new()
		var error = json.parse(json_str)
		if error == OK:
			var data = json.get_data()
			if data is Dictionary:
				data_received.emit(from_peer, data)
			else:
				push_warning("PeerJSBridge: Received non-dictionary data")
				data_received.emit(from_peer, {"raw": data})
		else:
			push_error("PeerJSBridge: Failed to parse received JSON: " + json_str)

func _on_js_peer_disconnected(args: Array) -> void:
	if args.size() > 0:
		var remote_id = str(args[0])
		connected_peers.erase(remote_id)
		print("PeerJSBridge: Peer disconnected: " + remote_id)
		peer_disconnected.emit(remote_id)

func _on_js_error(args: Array) -> void:
	if args.size() > 0:
		var error_msg = str(args[0])
		last_error = error_msg
		push_error("PeerJSBridge: Error - " + error_msg)
		error_occurred.emit(error_msg)
