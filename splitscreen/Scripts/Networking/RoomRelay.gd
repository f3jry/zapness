extends Node

## HTTP relay client for the room-code matchmaking server.
## Replace RELAY_URL with your PythonAnywhere app URL once deployed.
const RELAY_URL := "https://ironinblood.pythonanywhere.com"

signal room_registered(code: String)
signal room_resolved(ip: String, port: int)
signal relay_error(message: String)

var _http: HTTPRequest = null
var _pending_action := ""   # "host" | "join" | "cancel"
var _pending_code := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_http = HTTPRequest.new()
	if not OS.has_feature("web"):
		_http.use_threads = true
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

## Called by the host: registers ip+lan_ip+port with the relay, emits room_registered(code).
func register_room(ip: String, lan_ip: String, port: int) -> void:
	_pending_action = "host"
	var body := JSON.stringify({"ip": ip, "lan_ip": lan_ip, "port": port})
	var headers := ["Content-Type: application/json"]
	var err := _http.request(RELAY_URL + "/zap/host", headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		relay_error.emit("HTTP request failed: " + error_string(err))

## Called by the joiner: looks up ip+port by code, emits room_resolved(ip, port).
func resolve_room(code: String) -> void:
	_pending_action = "join"
	_pending_code = code.strip_edges().to_upper()
	var err := _http.request(RELAY_URL + "/zap/join/" + _pending_code)
	if err != OK:
		relay_error.emit("HTTP request failed: " + error_string(err))

## Called by the host when the match starts or is cancelled.
func cancel_room(code: String) -> void:
	_pending_action = "cancel"
	var err := _http.request(
		RELAY_URL + "/zap/cancel/" + code.strip_edges().to_upper(),
		[], HTTPClient.METHOD_DELETE
	)
	if err != OK:
		pass  # Fire and forget — not critical

func _on_request_completed(result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		relay_error.emit("Network error (result %d)" % result)
		return

	var text := body.get_string_from_utf8()
	var parsed = JSON.parse_string(text)
	if parsed == null:
		relay_error.emit("Invalid relay response: " + text)
		return

	match _pending_action:
		"host":
			if response_code == 200 and "code" in parsed:
				room_registered.emit(parsed["code"])
			else:
				relay_error.emit("Relay host error: " + text)
		"join":
			if response_code == 200 and "ip" in parsed:
				var target_ip = parsed["ip"]
				# If on the same LAN or testing locally, connect via LAN IP if available
				if parsed.get("is_same_public_ip", false) and not parsed.get("lan_ip", "").is_empty():
					target_ip = parsed["lan_ip"]
				room_resolved.emit(target_ip, int(parsed["port"]))
			else:
				relay_error.emit("Room not found. Check the code and try again.")
		"cancel":
			pass  # nothing to do
