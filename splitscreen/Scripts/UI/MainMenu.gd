extends Control

# ── Main menu panels ──────────────────────────────────────────────────────────
@onready var main_buttons: VBoxContainer   = %MainButtons   if has_node("%MainButtons")   else null
@onready var online_panel: PanelContainer  = %OnlinePanel   if has_node("%OnlinePanel")   else null
@onready var controls_panel: PanelContainer = %ControlsPanel if has_node("%ControlsPanel") else null

# ── Online panel: mode selector ───────────────────────────────────────────────
@onready var mode_row: HBoxContainer       = %ModeRow       if has_node("%ModeRow")       else null
@onready var host_mode_btn: Button         = %HostModeBtn   if has_node("%HostModeBtn")   else null
@onready var join_mode_btn: Button         = %JoinModeBtn   if has_node("%JoinModeBtn")   else null

# ── Host sub-panel ────────────────────────────────────────────────────────────
@onready var host_panel: VBoxContainer     = %HostPanel     if has_node("%HostPanel")     else null
@onready var host_code_label: Label        = %HostCodeLabel if has_node("%HostCodeLabel") else null
@onready var host_start_btn: Button        = %HostStartBtn  if has_node("%HostStartBtn")  else null
@onready var host_cancel_btn: Button       = %HostCancelBtn if has_node("%HostCancelBtn") else null

# ── Join sub-panel ────────────────────────────────────────────────────────────
@onready var join_panel: VBoxContainer     = %JoinPanel     if has_node("%JoinPanel")     else null
@onready var join_code_input: LineEdit     = %JoinCodeInput if has_node("%JoinCodeInput") else null
@onready var join_connect_btn: Button      = %JoinConnectBtn if has_node("%JoinConnectBtn") else null

# ── Shared status ─────────────────────────────────────────────────────────────
@onready var status_label: Label           = %StatusLabel   if has_node("%StatusLabel")   else null
@onready var back_btn: Button              = %BackBtn       if has_node("%BackBtn")        else null

# ── State ─────────────────────────────────────────────────────────────────────
var _current_code := ""
var _mode := ""   # "host" or "join"

# ── Helpers ───────────────────────────────────────────────────────────────────
func _set_status(msg: String) -> void:
	if status_label: status_label.text = msg

func _lock_buttons(locked: bool) -> void:
	for btn in [host_mode_btn, join_mode_btn, host_start_btn,
				host_cancel_btn, join_connect_btn]:
		if btn: btn.disabled = locked

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	NetworkManager.connection_status_changed.connect(_on_status_changed)
	RoomRelay.room_registered.connect(_on_room_registered)
	RoomRelay.room_resolved.connect(_on_room_resolved)
	RoomRelay.relay_error.connect(_on_relay_error)

	# Handle CLI args for quick testing
	var args := OS.get_cmdline_args()
	var user_args := OS.get_cmdline_user_args()
	if "--host" in args or "--host" in user_args:
		NetworkManager.host_game(8080)
		return
	if "--client" in args or "--client" in user_args:
		NetworkManager.join_game("127.0.0.1", 8080)
		return

	_show_main_menu()

func _show_main_menu() -> void:
	if main_buttons: main_buttons.visible = true
	if online_panel: online_panel.visible = false
	if controls_panel: controls_panel.visible = false

func _show_online_panel() -> void:
	if main_buttons: main_buttons.visible = false
	if online_panel: online_panel.visible = true
	if host_panel: host_panel.visible = false
	if join_panel: join_panel.visible = false
	if mode_row: mode_row.visible = true
	_set_status("Host a game and share your code, or enter a friend's code.")
	_lock_buttons(false)

# ── Main menu buttons ─────────────────────────────────────────────────────────
func _on_online_btn_pressed() -> void:
	_show_online_panel()

func _on_splitscreen_btn_pressed() -> void:
	NetworkManager.disconnect_game()
	GameManager.reset_params()
	get_tree().change_scene_to_file("res://Instantiables/environment/main.tscn")

func _on_controls_btn_pressed() -> void:
	if controls_panel:
		controls_panel.visible = !controls_panel.visible

func _on_quit_btn_pressed() -> void:
	get_tree().quit()

# ── Mode buttons ──────────────────────────────────────────────────────────────
func _on_host_mode_btn_pressed() -> void:
	_mode = "host"
	if mode_row: mode_row.visible = false
	if host_panel: host_panel.visible = true
	if join_panel: join_panel.visible = false
	if host_code_label: host_code_label.text = "Getting your code…"
	if host_start_btn: host_start_btn.disabled = true
	_set_status("Opening server…")
	_lock_buttons(true)

	# 1. Start local WebSocket server first
	var err := NetworkManager.host_game(8080)
	if err != OK:
		_set_status("Failed to open server: " + error_string(err))
		_lock_buttons(false)
		return

	# 2. Register with relay using external IP
	_set_status("Registering with relay…")
	_fetch_external_ip_then_register()

func _on_join_mode_btn_pressed() -> void:
	_mode = "join"
	if mode_row: mode_row.visible = false
	if host_panel: host_panel.visible = false
	if join_panel: join_panel.visible = true
	if join_code_input: join_code_input.grab_focus()
	_set_status("Enter the 4-letter code your friend shared.")

# ── Host flow ─────────────────────────────────────────────────────────────────
func _fetch_external_ip_then_register() -> void:
	# Use a small free IP-echo API. If this fails, fall back to LAN IP.
	var http := HTTPRequest.new()
	http.use_threads = true
	add_child(http)
	http.request_completed.connect(func(result, code, _h, body):
		http.queue_free()
		var ip := ""
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			ip = body.get_string_from_utf8().strip_edges()
		if ip.is_empty() or not ip.is_valid_ip_address():
			# Fall back to first non-loopback local IP
			ip = _get_local_ip()
		if ip.is_empty():
			_set_status("Could not determine IP address.")
			_lock_buttons(false)
			return
		RoomRelay.register_room(ip, 8080)
	)
	http.request("https://ironinblood.pythonanywhere.com/get_own_ip")

func _get_local_ip() -> String:
	for addr in IP.get_local_addresses():
		if addr.is_valid_ip_address() and not addr.begins_with("127.") and not addr.begins_with("::1"):
			return addr
	return ""

func _on_room_registered(code: String) -> void:
	_current_code = code
	if host_code_label:
		host_code_label.text = code
	if host_start_btn:
		host_start_btn.disabled = false
	_lock_buttons(false)
	if host_cancel_btn: host_cancel_btn.disabled = false
	_set_status("Share this code with your friend. Waiting for them to join…")

func _on_host_cancel_btn_pressed() -> void:
	if _current_code:
		RoomRelay.cancel_room(_current_code)
		_current_code = ""
	NetworkManager.disconnect_game()
	_show_online_panel()

# ── Join flow ─────────────────────────────────────────────────────────────────
func _on_join_connect_btn_pressed(_submitted_text: String = "") -> void:
	if not join_code_input: return
	var code := join_code_input.text.strip_edges().to_upper()
	if code.length() != 4:
		_set_status("Please enter the full 4-letter code.")
		return
	_lock_buttons(true)
	_set_status("Looking up room '%s'..." % code)
	RoomRelay.resolve_room(code)

func _on_room_resolved(ip: String, port: int) -> void:
	_set_status("Found host at %s:%d — connecting…" % [ip, port])
	var err := NetworkManager.join_game(ip, port)
	if err != OK:
		_set_status("Connection error: " + error_string(err))
		_lock_buttons(false)

# ── Shared callbacks ──────────────────────────────────────────────────────────
func _on_status_changed(status: String) -> void:
	_set_status(status)

func _on_relay_error(message: String) -> void:
	_set_status("⚠ " + message)
	_lock_buttons(false)

func _on_back_btn_pressed() -> void:
	# Cancel any active room registration
	if _current_code:
		RoomRelay.cancel_room(_current_code)
		_current_code = ""
	NetworkManager.disconnect_game()
	_show_main_menu()
