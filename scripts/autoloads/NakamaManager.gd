extends Node

## Nakama Manager Autoload
## Handles client creation, authentication, session lifecycle, and socket connection.
## Add this as an Autoload in Project Settings.

# ---------- Signals ----------
signal session_connected(session: NakamaSession)
signal session_expired()
signal socket_connected()
signal socket_disconnected()
signal error_occurred(message: String)

# ---------- Configuration ----------
const SERVER_KEY := "defaultkey"
const HOST := "127.0.0.1"
const PORT := 7350
const SCHEME := "http"
const REQUEST_TIMEOUT := 10 # seconds

# Where to persist auth tokens between game sessions
const AUTH_SAVE_PATH := "user://nakama_auth.cfg"

# ---------- Public State ----------
var client: NakamaClient
var session: NakamaSession
var socket: NakamaSocket

var is_session_valid: bool:
	get:
		return session != null and not session.expired

# ---------- Lifecycle ----------

func _ready() -> void:
	# Create the Nakama client via the Nakama singleton (must be set up as Autoload first)
	client = Nakama.create_client(SERVER_KEY, HOST, PORT, SCHEME)
	client.timeout = REQUEST_TIMEOUT
	print("[NakamaManager] Client created -> %s:%d (%s)" % [HOST, PORT, SCHEME])


## Authenticate using the device's unique ID. Creates an account if one doesn't exist.
## Returns the session on success, or null on failure.
func authenticate_device_async(username: String = "", create_account: bool = true, vars: Dictionary = {}) -> NakamaSession:
	var device_id := OS.get_unique_id()
	if device_id.is_empty():
		# Fallback for platforms that don't provide a device ID (e.g. desktop)
		device_id = _load_or_generate_device_id()

	print("[NakamaManager] Authenticating with device_id: %s" % device_id)

	var new_session: NakamaSession
	if vars.is_empty():
		new_session = await client.authenticate_device_async(device_id, username, create_account)
	else:
		new_session = await client.authenticate_device_async(device_id, username, create_account, vars)

	if new_session.is_exception():
		var err_msg := "Authentication failed: %s" % new_session
		push_error("[NakamaManager] %s" % err_msg)
		error_occurred.emit(err_msg)
		return null

	session = new_session
	_save_session()
	print("[NakamaManager] Authenticated successfully — user_id: %s, username: %s" % [session.user_id, session.username])
	session_connected.emit(session)
	return session


## Authenticate using email and password for dev/testing.
func authenticate_email_async(email: String, password: String, username: String = "", create_account: bool = true) -> NakamaSession:
	var new_session: NakamaSession = await client.authenticate_email_async(email, password, username, create_account)
	if new_session.is_exception():
		var err_msg := "Email authentication failed: %s" % new_session
		push_error("[NakamaManager] %s" % err_msg)
		error_occurred.emit(err_msg)
		return null

	session = new_session
	_save_session()
	print("[NakamaManager] Email auth successful — user_id: %s" % session.user_id)
	session_connected.emit(session)
	return session


# ---------- Session Lifecycle ----------

## Try to restore a saved session. Returns true if a valid session was restored.
func restore_session_async() -> bool:
	var config := ConfigFile.new()
	var err := config.load(AUTH_SAVE_PATH)
	if err != OK:
		print("[NakamaManager] No saved session found.")
		return false

	var auth_token: String = config.get_value("auth", "token", "")
	var refresh_token: String = config.get_value("auth", "refresh_token", "")
	if auth_token.is_empty():
		return false

	session = NakamaClient.restore_session(auth_token)
	if session.expired:
		print("[NakamaManager] Saved session expired, attempting refresh...")
		if refresh_token.is_empty():
			session = null
			return false
		# Try refreshing with the refresh token
		session.refresh_token = refresh_token
		var refreshed := await client.session_refresh_async(session)
		if refreshed.is_exception():
			push_warning("[NakamaManager] Session refresh failed, re-authentication required.")
			session = null
			session_expired.emit()
			return false
		session = refreshed
		_save_session()
		print("[NakamaManager] Session refreshed successfully.")

	session_connected.emit(session)
	return true


## Refresh the current session if it's close to expiring.
func refresh_session_async() -> bool:
	if session == null:
		return false
	if not session.expired:
		return true # Still valid

	var refreshed := await client.session_refresh_async(session)
	if refreshed.is_exception():
		push_warning("[NakamaManager] Session refresh failed.")
		session = null
		session_expired.emit()
		return false

	session = refreshed
	_save_session()
	return true


## Logout and clear the session.
func logout_async() -> void:
	if session != null:
		await client.session_logout_async(session)
		session = null
	if socket != null:
		socket.close()
		socket = null
	_clear_saved_session()
	print("[NakamaManager] Logged out.")


# ---------- Socket ----------

## Connect the real-time socket. Must be authenticated first.
func connect_socket_async() -> bool:
	if session == null or session.expired:
		push_error("[NakamaManager] Cannot connect socket — no valid session.")
		return false

	socket = Nakama.create_socket_from(client)
	socket.closed.connect(_on_socket_closed)

	var result: NakamaAsyncResult = await socket.connect_async(session)
	if result.is_exception():
		var err_msg := "Socket connection failed: %s" % result
		push_error("[NakamaManager] %s" % err_msg)
		error_occurred.emit(err_msg)
		return false

	print("[NakamaManager] Socket connected.")
	socket_connected.emit()
	return true


func _on_socket_closed() -> void:
	print("[NakamaManager] Socket disconnected.")
	socket_disconnected.emit()


# ---------- Helpers ----------

func _save_session() -> void:
	if session == null:
		return
	var config := ConfigFile.new()
	config.set_value("auth", "token", session.token)
	config.set_value("auth", "refresh_token", session.refresh_token)
	config.save(AUTH_SAVE_PATH)


func _clear_saved_session() -> void:
	if FileAccess.file_exists(AUTH_SAVE_PATH):
		DirAccess.remove_absolute(AUTH_SAVE_PATH)


func _load_or_generate_device_id() -> String:
	var config := ConfigFile.new()
	var err := config.load(AUTH_SAVE_PATH)
	if err == OK:
		var saved_id: String = config.get_value("auth", "device_id", "")
		if not saved_id.is_empty():
			return saved_id

	# Generate a random UUID-like device ID
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var new_id := ""
	for i in range(16):
		new_id += "%02x" % rng.randi_range(0, 255)
		if i in [3, 5, 7, 9]:
			new_id += "-"

	# Persist it
	config.set_value("auth", "device_id", new_id)
	config.save(AUTH_SAVE_PATH)
	print("[NakamaManager] Generated new device_id: %s" % new_id)
	return new_id
