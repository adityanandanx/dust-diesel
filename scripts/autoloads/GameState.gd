extends Node

## GameState Autoload
## Coordinates game-level state: player info, lobby, matchmaking, etc.
## Uses NakamaManager for all server communication.

# ---------- Signals ----------
signal player_info_updated(account: NakamaAPI.ApiAccount)
signal match_joined(match_data)
signal match_state_received(state)
signal match_presence_changed(joins, leaves)
signal matchmaking_found(matched)

# ---------- Game State ----------
var account: NakamaAPI.ApiAccount
var current_match: NakamaRTAPI.Match
var players: Dictionary = {} # session_id -> presence

# ---------- OpCodes ----------
# Define your game-specific op codes here
const OP_POSITION := 1
const OP_VOTE := 2
const OP_GAME_STATE := 3
const OP_PLAYER_ACTION := 4
const OP_CHAT := 5
const OP_READY := 6

# ---------- Lifecycle ----------

func _ready() -> void:
	# Wait for NakamaManager to be ready, then try restoring or creating a session
	_initialize.call_deferred()


func _initialize() -> void:
	# Try to restore an existing session first
	var restored := await NakamaManager.restore_session_async()
	if restored:
		print("[GameState] Session restored from saved tokens.")
		await _post_authentication()
	else:
		# Authenticate with device ID (creates account automatically)
		var session := await NakamaManager.authenticate_device_async()
		if session != null:
			await _post_authentication()
		else:
			push_error("[GameState] Failed to authenticate. Game cannot proceed online.")


func _post_authentication() -> void:
	# Fetch the full account info
	account = await NakamaManager.client.get_account_async(NakamaManager.session)
	if account.is_exception():
		push_error("[GameState] Failed to fetch account: %s" % account)
		return

	print("[GameState] Welcome, %s (user_id: %s)" % [account.user.username, account.user.id])
	player_info_updated.emit(account)

	# Connect the real-time socket
	var socket_ok := await NakamaManager.connect_socket_async()
	if socket_ok:
		_setup_socket_listeners()
		print("[GameState] Ready for real-time features.")


# ---------- Socket Listeners ----------

func _setup_socket_listeners() -> void:
	var socket := NakamaManager.socket
	if socket == null:
		return

	socket.received_match_state.connect(_on_match_state)
	socket.received_match_presence.connect(_on_match_presence)
	socket.received_matchmaker_matched.connect(_on_matchmaker_matched)


func _on_match_state(match_state: NakamaRTAPI.MatchData) -> void:
	match_state_received.emit(match_state)


func _on_match_presence(presence: NakamaRTAPI.MatchPresenceEvent) -> void:
	for p in presence.joins:
		players[p.session_id] = p
		print("[GameState] Player joined: %s (session: %s)" % [p.user_id, p.session_id])

	for p in presence.leaves:
		if p.session_id in players:
			players.erase(p.session_id)
			print("[GameState] Player left: %s (session: %s)" % [p.user_id, p.session_id])

	match_presence_changed.emit(presence.joins, presence.leaves)


func _on_matchmaker_matched(matched: NakamaRTAPI.MatchmakerMatched) -> void:
	print("[GameState] Matchmaker found a match!")
	matchmaking_found.emit(matched)
	# Automatically join the matched game
	var match_result = await NakamaManager.socket.join_match_async(matched.match_id)
	if match_result.is_exception():
		push_error("[GameState] Failed to join matched game: %s" % match_result)
		return
	_set_current_match(match_result)


# ---------- Match Management ----------

## Create a new match (server relayed)
func create_match_async(match_name: String = "") -> NakamaRTAPI.Match:
	if NakamaManager.socket == null:
		push_error("[GameState] Socket not connected.")
		return null

	var match_result: NakamaRTAPI.Match
	if match_name.is_empty():
		match_result = await NakamaManager.socket.create_match_async()
	else:
		match_result = await NakamaManager.socket.create_match_async(match_name)

	if match_result.is_exception():
		push_error("[GameState] Failed to create match: %s" % match_result)
		return null

	_set_current_match(match_result)
	print("[GameState] Created match: %s" % current_match.match_id)
	return current_match


## Join an existing match by ID
func join_match_async(match_id: String) -> NakamaRTAPI.Match:
	if NakamaManager.socket == null:
		push_error("[GameState] Socket not connected.")
		return null

	var match_result: NakamaRTAPI.Match = await NakamaManager.socket.join_match_async(match_id)
	if match_result.is_exception():
		push_error("[GameState] Failed to join match: %s" % match_result)
		return null

	_set_current_match(match_result)
	print("[GameState] Joined match: %s" % current_match.match_id)
	return current_match


## Leave the current match
func leave_match_async() -> void:
	if current_match == null or NakamaManager.socket == null:
		return
	await NakamaManager.socket.leave_match_async(current_match.match_id)
	print("[GameState] Left match: %s" % current_match.match_id)
	current_match = null
	players.clear()


## Send match state to all other players
func send_match_state(op_code: int, data: Dictionary) -> void:
	if current_match == null or NakamaManager.socket == null:
		return
	await NakamaManager.socket.send_match_state_async(current_match.match_id, op_code, JSON.stringify(data))


func _set_current_match(match_data: NakamaRTAPI.Match) -> void:
	current_match = match_data
	players.clear()
	for p in match_data.presences:
		players[p.session_id] = p
	match_joined.emit(match_data)


# ---------- Matchmaking ----------

## Add to matchmaker pool
func find_match_async(min_players: int = 2, max_players: int = 10, query: String = "", string_props: Dictionary = {}, numeric_props: Dictionary = {}) -> NakamaRTAPI.MatchmakerTicket:
	if NakamaManager.socket == null:
		push_error("[GameState] Socket not connected.")
		return null

	var ticket: NakamaRTAPI.MatchmakerTicket = await NakamaManager.socket.add_matchmaker_async(query, min_players, max_players, string_props, numeric_props)
	if ticket.is_exception():
		push_error("[GameState] Failed to join matchmaker: %s" % ticket)
		return null

	print("[GameState] Joined matchmaker with ticket: %s" % ticket.ticket)
	return ticket


# ---------- Account Helpers ----------

## Update the player's display name and other account info
func update_account_async(username: String = "", display_name: String = "", avatar_url: String = "") -> bool:
	var result := await NakamaManager.client.update_account_async(
		NakamaManager.session, username, display_name, avatar_url
	)
	if result.is_exception():
		push_error("[GameState] Failed to update account: %s" % result)
		return false

	# Refresh the cached account
	account = await NakamaManager.client.get_account_async(NakamaManager.session)
	player_info_updated.emit(account)
	return true


# ---------- RPC Helper ----------

## Call a server RPC
func rpc_async(rpc_id: String, payload: Dictionary = {}) -> NakamaAPI.ApiRpc:
	var payload_str := JSON.stringify(payload) if not payload.is_empty() else ""
	var result: NakamaAPI.ApiRpc = await NakamaManager.client.rpc_async(NakamaManager.session, rpc_id, payload_str)
	if result.is_exception():
		push_error("[GameState] RPC '%s' failed: %s" % [rpc_id, result])
		return null
	return result
