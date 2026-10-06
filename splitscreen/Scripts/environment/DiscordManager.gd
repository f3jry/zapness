extends Node
## DiscordManager — bridges the Discord Embedded App SDK (window.GodotDiscord)
## into GDScript via JavaScriptBridge.
##
## Add this as an Autoload named "DiscordManager" in Project > Project Settings > Autoload.
## It gracefully no-ops on non-web and non-Discord platforms.

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when the Discord SDK is fully initialised and user data is available.
signal sdk_ready(user: Dictionary)

## Emitted if the SDK fails to initialise.
signal sdk_error(message: String)

## Emitted when lobbies change via real-time WebSocket or polling.
signal lobbies_updated(lobbies: Array)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Replace with your Discord Application (Client) ID from the Developer Portal.
const DISCORD_CLIENT_ID := "1556972180930166785"

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var is_ready: bool = false
var current_user: Dictionary = {}
var channel_id: String = ""
var instance_id: String = ""
var guild_id: String = ""

# JavaScriptBridge callback references (must be kept alive)
var _js_on_ready: JavaScriptObject = null
var _js_on_error: JavaScriptObject = null
var _js_on_lobbies_changed: JavaScriptObject = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	if not _is_web_platform():
		push_warning("DiscordManager: Not on web platform — SDK disabled.")
		return

	# Immediately query channelId / instanceId synchronously from JS/URL params
	_check_initial_channel_id()
	_setup_js_callbacks()
	_call_js_init()


func _is_web_platform() -> bool:
	return OS.has_feature("web")

# ---------------------------------------------------------------------------
# Initialisation
# ---------------------------------------------------------------------------

func _check_initial_channel_id() -> void:
	var cid = str(JavaScriptBridge.eval("""
		(function() {
			if (window.GodotDiscord && window.GodotDiscord.channelId) {
				return window.GodotDiscord.channelId;
			}
			try {
				var p = new URLSearchParams(window.location.search);
				return p.get('channel_id') || '';
			} catch(e) {
				return '';
			}
		})()
	""", true))
	if not cid.is_empty():
		channel_id = cid
		is_ready = true
		print("DiscordManager: Synchronously detected channel ID: ", channel_id)

	var iid = str(JavaScriptBridge.eval("""
		(function() {
			if (window.GodotDiscord && window.GodotDiscord.instanceId) {
				return window.GodotDiscord.instanceId;
			}
			try {
				var p = new URLSearchParams(window.location.search);
				return p.get('instance_id') || '';
			} catch(e) {
				return '';
			}
		})()
	""", true))
	if not iid.is_empty():
		instance_id = iid


func _setup_js_callbacks() -> void:
	_js_on_ready = JavaScriptBridge.create_callback(_on_js_ready)
	_js_on_error = JavaScriptBridge.create_callback(_on_js_error)
	_js_on_lobbies_changed = JavaScriptBridge.create_callback(_on_js_lobbies_changed)

	var window = JavaScriptBridge.get_interface("window")
	if window:
		window._godotDiscordOnReady = _js_on_ready
		window._godotDiscordOnError = _js_on_error
		window._godotDiscordOnLobbiesChanged = _js_on_lobbies_changed

		JavaScriptBridge.eval("""
			(function() {
				function bind() {
					if (window.GodotDiscord && window._godotDiscordOnReady) {
						window.GodotDiscord.onReady = window._godotDiscordOnReady;
						window.GodotDiscord.onError = window._godotDiscordOnError;
						window.GodotDiscord.onLobbiesChanged = window._godotDiscordOnLobbiesChanged;
						if (window.GodotDiscord.ready) {
							window._godotDiscordOnReady();
						}
					} else {
						setTimeout(bind, 50);
					}
				}
				bind();
			})();
		""", true)


func _call_js_init() -> void:
	JavaScriptBridge.eval("""
		(function() {
			function tryInit() {
				if (window.GodotDiscord && typeof window.GodotDiscord.init === 'function') {
					window.GodotDiscord.init('%s');
				} else {
					setTimeout(tryInit, 50);
				}
			}
			tryInit();
		})();
	""" % DISCORD_CLIENT_ID, true)

# ---------------------------------------------------------------------------
# JS Callback handlers
# ---------------------------------------------------------------------------

func _on_js_ready(args: Array) -> void:
	is_ready = true

	# Pull state out of window.GodotDiscord
	var user_json: String = JavaScriptBridge.eval("JSON.stringify(window.GodotDiscord.currentUser || {})", true)
	channel_id  = str(JavaScriptBridge.eval("window.GodotDiscord.channelId || ''", true))
	instance_id = str(JavaScriptBridge.eval("window.GodotDiscord.instanceId || ''", true))
	guild_id    = str(JavaScriptBridge.eval("window.GodotDiscord.guildId || ''", true))

	var json := JSON.new()
	if json.parse(user_json) == OK and json.get_data() is Dictionary:
		current_user = json.get_data()

	print("DiscordManager: SDK ready. User: ", current_user.get("username", "(unknown)"), " Channel: ", channel_id, " Instance: ", instance_id)
	sdk_ready.emit(current_user)


func _on_js_error(args: Array) -> void:
	var msg := str(args[0]) if args.size() > 0 else "Unknown error"
	push_error("DiscordManager: SDK error — " + msg)
	sdk_error.emit(msg)


func _on_js_lobbies_changed(_args: Array) -> void:
	var lobbies = fetch_lobbies()
	lobbies_updated.emit(lobbies)

# ---------------------------------------------------------------------------
# Public API (callable from any GDScript)
# ---------------------------------------------------------------------------

## Returns the current Discord user dict, or empty dict if not ready.
func get_user() -> Dictionary:
	return current_user


## Returns the Discord channel ID the Activity is running in.
func get_channel_id() -> String:
	return channel_id


## Returns the Discord activity instance ID.
func get_instance_id() -> String:
	return instance_id


## Returns the call / room identifier (channel_id or instance_id).
func get_call_id() -> String:
	if not channel_id.is_empty():
		return channel_id
	if not instance_id.is_empty():
		return instance_id
	return ""


## Returns the Discord guild (server) ID, or empty string for DM activities.
func get_guild_id() -> String:
	return guild_id


## Returns the active ntfy topic name.
func get_topic() -> String:
	if not _is_web_platform():
		return ""
	return str(JavaScriptBridge.eval("window.GodotDiscord ? window.GodotDiscord.getChannelTopic() : ''", true))


## Patches PeerJS URL mappings to route through Discord's proxy.
func patch_peerjs_url_mappings() -> void:
	if not _is_web_platform() or not is_ready:
		return
	JavaScriptBridge.eval("window.GodotDiscord.patchUrlMappings()", true)


## Returns true if running inside Discord or in a call session.
func is_in_discord_call() -> bool:
	if not _is_web_platform():
		return false
	if not channel_id.is_empty() or not instance_id.is_empty():
		return true
	return _is_running_in_discord_js()


func _is_running_in_discord_js() -> bool:
	return bool(JavaScriptBridge.eval("""
		(function() {
			if (window.GodotDiscord && typeof window.GodotDiscord.isRunningInDiscord === 'function') {
				return window.GodotDiscord.isRunningInDiscord();
			}
			return false;
		})()
	""", true))


## Returns a deterministic room ID for players in this voice call.
func get_call_room_id() -> String:
	var cid = get_call_id()
	if not cid.is_empty():
		return "call-" + cid
	return ""


## Start announcing this host's lobby to the channel via ntfy
func start_hosting_announcement(host_peer_id: String) -> void:
	if not _is_web_platform():
		return
	var uname = current_user.get("username", "Host")
	var av = current_user.get("avatar", "")
	JavaScriptBridge.eval("""
		(function() {
			if (window.GodotDiscord && window.GodotDiscord.startHostingAnnouncement) {
				window.GodotDiscord.startHostingAnnouncement(%s, %s, %s);
			}
		})();
	""" % [JSON.stringify(host_peer_id), JSON.stringify(uname), JSON.stringify(av)], true)


## Stop announcing this host's lobby
func stop_hosting_announcement() -> void:
	if not _is_web_platform():
		return
	JavaScriptBridge.eval("""
		(function() {
			if (window.GodotDiscord && window.GodotDiscord.stopHostingAnnouncement) {
				window.GodotDiscord.stopHostingAnnouncement();
			}
		})();
	""", true)


## Trigger lobby fetch and return array of active lobby dictionaries
func fetch_lobbies() -> Array:
	if not _is_web_platform():
		return []
	var json_str = str(JavaScriptBridge.eval("""
		(function() {
			if (window.GodotDiscord && window.GodotDiscord.fetchLobbies) {
				window.GodotDiscord.fetchLobbies();
				return window.GodotDiscord.getActiveLobbiesJson() || '[]';
			}
			return '[]';
		})();
	""", true))
	var json = JSON.new()
	if json.parse(json_str) == OK and json.get_data() is Array:
		return json.get_data()
	return []
