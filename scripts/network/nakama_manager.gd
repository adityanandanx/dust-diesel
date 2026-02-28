extends Node

## NakamaManager Autoload — handles client, session, socket, and match logic.

signal connected_to_server
signal match_joined(match_id: String)
signal player_joined(session_id: String, user_id: String, username: String)
signal player_left(session_id: String)
signal game_started
signal map_selected(map_id: String)

var client: NakamaClient
var session: NakamaSession
var socket: NakamaSocket
var current_match: NakamaRTAPI.Match
var match_name: String = ""
var is_host: bool = false
var selected_map: String = "boneyard"

enum OpCodes {
	POSITION_SYNC = 1,
	FIRE_WEAPON = 2,
	DAMAGE_EVENT = 3,
	PICKUP_CLAIM = 4,
	GAME_STARTED = 5,
	SPAWN_PICKUP = 6,
	ENV_DAMAGE = 7,
	WEAPON_EQUIP = 8,
	PLAYER_DEATH = 9,
	VEHICLE_SELECT = 10,
	MAP_SELECT = 11
}

# Dictionary of session_id to user data
var connected_players := {}
var _auth_complete := false


# ---------- Compatibility API for GameState.gd ----------

## Attempts to restore a saved session. Returns true if session is already valid.
func restore_session_async() -> bool:
	# Wait for internal auth if it hasn't finished yet
	if not _auth_complete:
		await connected_to_server
	return session != null and not session.expired


## Authenticates via device ID. Returns the session or null on failure.
func authenticate_device_async() -> NakamaSession:
	if not _auth_complete:
		await connected_to_server
	return session


## Connects the socket. Returns true if already connected or connection succeeds.
func connect_socket_async() -> bool:
	if not _auth_complete:
		await connected_to_server
	return socket != null


func _ready() -> void:
	# Create client to local Nakama server (default config)
	var server_host := OS.get_environment("NAKAMA_HOST")
	if server_host == "":
		server_host = "127.0.0.1"
	client = Nakama.create_client("defaultkey", server_host, 7350, "http")
	client.timeout = 10
	
	# Authenticate automatically using device UUID
	_authenticate()


func _authenticate() -> void:
	var device_id := OS.get_unique_id()
	
	session = await client.authenticate_device_async(device_id, "Player_" + str(randi() % 1000))
	if session.is_exception():
		printerr("Nakama Auth Error: ", session.get_exception().message)
		return
		
	print("Nakama Authenticated: ", session.user_id)
	
	# Create and connect socket
	socket = Nakama.create_socket_from(client)
	var connected: NakamaAsyncResult = await socket.connect_async(session)
	if connected.is_exception():
		printerr("Nakama Socket Error: ", connected.get_exception().message)
		return
		
	print("Nakama Socket connected.")
	
	# Hook up match events
	socket.received_match_presence.connect(_on_match_presence)
	socket.received_match_state.connect(_on_match_state)
	
	_auth_complete = true
	connected_to_server.emit()


func create_match(p_match_name: String = "") -> bool:
	if not socket or not session:
		printerr("Cannot create match — socket not ready.")
		return false
		
	var new_match: NakamaRTAPI.Match = await socket.create_match_async(p_match_name)
	if new_match.is_exception():
		printerr("Create Match Error: ", new_match.get_exception().message)
		return false
		
	current_match = new_match
	connected_players.clear()
	is_host = true
	selected_map = "boneyard"
	
	# Generate a short invite code and store the mapping
	var code := _generate_short_code()
	match_name = code
	var payload := JSON.stringify({"match_id": current_match.match_id})
	var ack = await client.write_storage_objects_async(session, [
		NakamaWriteStorageObject.new("match_codes", code, 2, 1, payload, "")
	])
	if ack.is_exception():
		printerr("Failed to store match code: ", ack)
	
	# Add ourselves to the player list
	_add_player(session.user_id, session.username, current_match.self_user.session_id)
	
	match_joined.emit(current_match.match_id)
	print("Created match | Code: ", code, " | ID: ", current_match.match_id)
	return true


func join_match(code: String) -> bool:
	if not socket or not session:
		printerr("Cannot join match — socket not ready.")
		return false
	
	# Look up the short code in Nakama Storage to get the real match_id
	var _result = await client.list_storage_objects_async(session, "match_codes", session.user_id, 100)
	
	# We need to find the code across ALL users, so try reading it directly
	# Since we don't know the writer's user_id, we search our own first
	# A simpler approach: try using the code to read via RPC or list
	# For now, attempt a direct join in case code IS a match_id (UUID)
	var real_match_id := code
	
	# If the code looks short (not a UUID), look it up
	if code.length() < 30:
		# Try to find the match_id by listing all match_codes objects
		# We'll search across users by trying to join with the code as-is first
		# and falling back. Since Nakama storage requires user_id for reads,
		# we use a workaround: store codes under a well-known "system" approach.
		# For simplicity, we'll try reading from all connected users.
		var found := false
		
		# Try reading from the host who wrote it (we don't know their ID)
		# Use list_storage_objects to scan the collection
		var cursor := ""
		while not found:
			var list_result = await client.list_storage_objects_async(session, "match_codes", "", 100, cursor)
			if list_result.is_exception():
				break
			for obj in list_result.objects:
				if obj.key == code:
					var data = JSON.parse_string(obj.value)
					if data and "match_id" in data:
						real_match_id = data["match_id"]
						found = true
						break
			if not found and list_result.cursor and list_result.cursor != "":
				cursor = list_result.cursor
			else:
				break
		
		if not found:
			printerr("Could not find match with code: ", code)
			return false
	
	var joined_match: NakamaRTAPI.Match = await socket.join_match_async(real_match_id)
	if joined_match.is_exception():
		printerr("Join Match Error: ", joined_match.get_exception().message)
		return false
		
	current_match = joined_match
	match_name = code
	connected_players.clear()
	is_host = false
	selected_map = "boneyard"
	
	_add_player(session.user_id, session.username, current_match.self_user.session_id)
	
	for p in current_match.presences:
		_add_player(p.user_id, p.username, p.session_id)
		
	match_joined.emit(current_match.match_id)
	print("Joined match: ", code, " -> ", current_match.match_id)
	return true


func leave_match() -> void:
	if current_match and socket:
		await socket.leave_match_async(current_match.match_id)
		current_match = null
		match_name = ""
		is_host = false
		selected_map = "boneyard"
		connected_players.clear()


func _on_match_presence(p_presence: NakamaRTAPI.MatchPresenceEvent) -> void:
	if not current_match or p_presence.match_id != current_match.match_id:
		return
		
	var saw_new_remote_join: bool = false
	for p in p_presence.joins:
		# Don't re-add ourselves if the server bounces our join event back
		if p.session_id != current_match.self_user.session_id:
			_add_player(p.user_id, p.username, p.session_id)
			saw_new_remote_join = true

	# Late-join sync: when a new player appears, resend our current vehicle selection.
	if saw_new_remote_join:
		_broadcast_my_vehicle_selection()
		if is_host:
			_broadcast_selected_map()
			
	for p in p_presence.leaves:
		if p.session_id in connected_players:
			connected_players.erase(p.session_id)
			player_left.emit(p.session_id)
			print("Player left: ", p.username)


func _on_match_state(match_state: NakamaRTAPI.MatchData) -> void:
	# Decode operations and emit signals for other systems
	if match_state.op_code == OpCodes.GAME_STARTED:
		game_started.emit()
	elif match_state.op_code == OpCodes.VEHICLE_SELECT:
		var data: Dictionary = JSON.parse_string(match_state.data)
		if data and "session_id" in data and "vehicle_id" in data:
			var sess_id: String = data["session_id"]
			if sess_id in connected_players:
				connected_players[sess_id]["selected_vehicle"] = data["vehicle_id"]
	elif match_state.op_code == OpCodes.MAP_SELECT:
		var data: Dictionary = JSON.parse_string(match_state.data)
		if data and "map_id" in data:
			selected_map = str(data["map_id"])
			map_selected.emit(selected_map)


func _add_player(user_id: String, username: String, sess_id: String) -> void:
	var p_data = {
		"user_id": user_id,
		"username": username,
		"session_id": sess_id,
		"selected_vehicle": "sedan"
	}
	connected_players[sess_id] = p_data
	player_joined.emit(sess_id, user_id, username)
	print("Player joined: ", username)


func send_match_state(op_code: int, data: String) -> void:
	if not current_match or not socket:
		return
	socket.send_match_state_async(current_match.match_id, op_code, data)


func _broadcast_my_vehicle_selection() -> void:
	if not current_match:
		return
	var my_sess_id: String = current_match.self_user.session_id
	if not (my_sess_id in connected_players):
		return
	var vehicle_id: String = connected_players[my_sess_id].get("selected_vehicle", "sedan")
	var payload := JSON.stringify({
		"session_id": my_sess_id,
		"vehicle_id": vehicle_id,
	})
	send_match_state(OpCodes.VEHICLE_SELECT, payload)


func _broadcast_selected_map() -> void:
	if not current_match:
		return
	var payload := JSON.stringify({
		"map_id": selected_map,
	})
	send_match_state(OpCodes.MAP_SELECT, payload)


func _generate_short_code() -> String:
	var chars := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var code := ""
	for i in range(5):
		code += chars[randi() % chars.length()]
	return code
