extends Node
## WebRTCBridge - Bridges direct browser WebRTC with Godot via PythonAnywhere relay signaling

signal code_ready(code: String)
signal connection_opened(role: String)
signal data_received(data: Dictionary)
signal error_occurred(message: String)

var current_code: String = ""
var is_host: bool = false
var is_connected: bool = false

var _js_callbacks: Array = []
var _webrtc_js = null
var _callbacks_initialized: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_feature("web"):
		return
	call_deferred("_try_setup_callbacks")

func _get_webrtc_js():
	if _webrtc_js != null:
		return _webrtc_js
	if not OS.has_feature("web"):
		return null
	var js_window = JavaScriptBridge.get_interface("window")
	if js_window and js_window.GodotWebRTC:
		_webrtc_js = js_window.GodotWebRTC
		_setup_callbacks()
	return _webrtc_js

func _try_setup_callbacks() -> void:
	if _get_webrtc_js() != null:
		print("[WebRTCBridge] WebRTC JS interface successfully connected.")
	else:
		# Retry
		get_tree().create_timer(0.2).timeout.connect(_try_setup_callbacks)

func _setup_callbacks() -> void:
	if _callbacks_initialized or _webrtc_js == null:
		return
	_callbacks_initialized = true
	
	var on_code = JavaScriptBridge.create_callback(_on_js_code_ready)
	_js_callbacks.append(on_code)
	_webrtc_js.onCodeReady = on_code
	
	var on_conn = JavaScriptBridge.create_callback(_on_js_connected)
	_js_callbacks.append(on_conn)
	_webrtc_js.onConnected = on_conn
	
	var on_data = JavaScriptBridge.create_callback(_on_js_data)
	_js_callbacks.append(on_data)
	_webrtc_js.onData = on_data
	
	var on_err = JavaScriptBridge.create_callback(_on_js_error)
	_js_callbacks.append(on_err)
	_webrtc_js.onError = on_err
	
	print("[WebRTCBridge] Callbacks registered successfully.")

func host_room() -> void:
	if not OS.has_feature("web"):
		return
	is_host = true
	is_connected = false
	var webrtc = _get_webrtc_js()
	if webrtc:
		webrtc.hostRoom()
	else:
		push_error("[WebRTCBridge] Cannot host: window.GodotWebRTC is not available")

func join_room(code: String) -> void:
	if not OS.has_feature("web"):
		return
	is_host = false
	is_connected = false
	current_code = code.to_upper().strip_edges()
	var webrtc = _get_webrtc_js()
	if webrtc:
		webrtc.joinRoom(current_code)
	else:
		push_error("[WebRTCBridge] Cannot join: window.GodotWebRTC is not available")

func send_data(data: Dictionary) -> bool:
	if not OS.has_feature("web") or not is_connected:
		return false
	var webrtc = _get_webrtc_js()
	if not webrtc:
		return false
	var json_str = JSON.stringify(data)
	var res = webrtc.sendData(json_str)
	return bool(res)

func disconnect_room() -> void:
	if not OS.has_feature("web"):
		return
	var webrtc = _get_webrtc_js()
	if webrtc:
		webrtc.disconnect()
	current_code = ""
	is_host = false
	is_connected = false

# ── JavaScript Callback Handlers ──────────────────────────────────────────────
func _on_js_code_ready(args: Array) -> void:
	if args.size() > 0:
		current_code = str(args[0])
		print("[WebRTCBridge] Room code ready: ", current_code)
		code_ready.emit(current_code)

func _on_js_connected(args: Array) -> void:
	var role = str(args[0]) if args.size() > 0 else ""
	is_connected = true
	print("[WebRTCBridge] WebRTC connected role: ", role)
	connection_opened.emit(role)

func _on_js_data(args: Array) -> void:
	if args.size() > 0:
		var raw = str(args[0])
		var json = JSON.new()
		if json.parse(raw) == OK and json.get_data() is Dictionary:
			data_received.emit(json.get_data())
		else:
			data_received.emit({"raw": raw})

func _on_js_error(args: Array) -> void:
	var msg = str(args[0]) if args.size() > 0 else "Unknown error"
	print("[WebRTCBridge] Error: ", msg)
	error_occurred.emit(msg)
