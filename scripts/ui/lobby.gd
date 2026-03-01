extends Control

## Lobby screen — shows connected players, ready toggle, start button for host.

@onready var code_label: Label = $Center/VBox/CodeLabel
@onready var player_list: VBoxContainer = $Center/VBox/PlayerList
@onready var ready_button: Button = $Center/VBox/ButtonRow/ReadyButton
@onready var start_button: Button = $Center/VBox/ButtonRow/StartButton
@onready var vehicle_button: Button = $Center/VBox/VehicleButton
@onready var map_row: HBoxContainer = $Center/VBox/MapRow
@onready var map_selector: OptionButton = $Center/VBox/MapRow/MapSelector
@onready var map_value: Label = $Center/VBox/MapValue
@onready var bot_row: HBoxContainer = $Center/VBox/BotRow
@onready var bot_count_spin: SpinBox = $Center/VBox/BotRow/BotCountSpin
@onready var back_button: Button = $Center/VBox/BackButton

var is_ready: bool = false
var is_host: bool = true
var invite_code: String = ""
var _map_ids: Array[String] = []
var _is_updating_map_selector: bool = false
var _is_updating_bot_spin: bool = false


func _ready() -> void:
	ready_button.pressed.connect(_on_ready_pressed)
	start_button.pressed.connect(_on_start_pressed)
	vehicle_button.pressed.connect(_on_vehicle_pressed)
	back_button.pressed.connect(_on_back_pressed)
	map_selector.item_selected.connect(_on_map_selected)
	bot_count_spin.value_changed.connect(_on_bot_count_changed)
	_populate_map_selector()

	if NakamaManager.current_match:
		invite_code = NakamaManager.match_name
		code_label.text = "INVITE CODE: %s" % invite_code
		
		# Restore host status from NakamaManager — only set it the first time
		# (when we're the only player, i.e. we just created the match).
		# On subsequent lobby loads (e.g. returning from VehicleSelect), just read it back.
		if NakamaManager.is_host:
			is_host = true
		else:
			is_host = NakamaManager.connected_players.size() <= 1
			NakamaManager.is_host = is_host
		start_button.visible = is_host
		map_row.visible = is_host
		bot_row.visible = is_host

		NakamaManager.player_joined.connect(_on_player_joined)
		NakamaManager.player_left.connect(_on_player_left)
		NakamaManager.game_started.connect(_on_game_started)
		NakamaManager.map_selected.connect(_on_remote_map_selected)
		NakamaManager.bot_count_selected.connect(_on_remote_bot_count_selected)
		NakamaManager.socket.received_match_state.connect(_on_match_state)
		if is_host:
			_announce_selected_map()
			NakamaManager.set_bot_count(NakamaManager.selected_bot_count)
		_update_bot_ui()
		_update_map_ui()
		
		_refresh_players()
	else:
		code_label.text = "NOT CONNECTED"
		start_button.visible = false
		map_row.visible = false
		bot_row.visible = false


func _on_ready_pressed() -> void:
	is_ready = not is_ready
	ready_button.text = "UNREADY" if is_ready else "READY"


func _on_start_pressed() -> void:
	if is_host and NakamaManager.current_match:
		NakamaManager.sync_bot_roster(_build_bot_roster())
		_announce_selected_map()
		NakamaManager.send_match_state(NakamaManager.OpCodes.GAME_STARTED, "")
		_on_game_started()


func _on_back_pressed() -> void:
	NakamaManager.leave_match()
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")


func _on_vehicle_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/VehicleSelect.tscn")


func _on_game_started() -> void:
	get_tree().change_scene_to_file("res://scenes/game/Game.tscn")


func _on_match_state(match_state: NakamaRTAPI.MatchData) -> void:
	if match_state.op_code == NakamaManager.OpCodes.VEHICLE_SELECT:
		_refresh_players()
	elif match_state.op_code == NakamaManager.OpCodes.MAP_SELECT:
		_update_map_ui()
	elif match_state.op_code == NakamaManager.OpCodes.BOT_COUNT_SELECT:
		_update_bot_ui()
	elif match_state.op_code == NakamaManager.OpCodes.BOT_SYNC:
		_refresh_players()


func _refresh_players() -> void:
	# Clear list
	for child in player_list.get_children():
		child.queue_free()
		
	# Re-add everyone
	for sess_id in NakamaManager.connected_players:
		var p_data: Dictionary = NakamaManager.connected_players[sess_id]
		var is_me = (NakamaManager.current_match and sess_id == NakamaManager.current_match.self_user.session_id)
		var display_name = p_data.get("username", "Unknown")
		var vehicle_name = p_data.get("selected_vehicle", "sedan")
		if is_me:
			display_name += " (You)"
		_add_player_entry(display_name, true, vehicle_name)


func _on_player_joined(_sess_id: String, _user_id: String, _username: String) -> void:
	_refresh_players()


func _on_player_left(_sess_id: String) -> void:
	_refresh_players()


func _add_player_entry(player_name: String, ready_state: bool, vehicle_id: String = "sedan") -> void:
	var hbox := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = player_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vehicle_label := Label.new()
	vehicle_label.text = vehicle_id.to_upper().replace("_", " ")
	vehicle_label.add_theme_color_override("font_color", Color(1, 0.85, 0.5, 1))
	var status_label := Label.new()
	status_label.text = "READY" if ready_state else "NOT READY"
	status_label.add_theme_color_override("font_color", Color.GREEN if ready_state else Color.RED)
	hbox.add_child(name_label)
	hbox.add_child(vehicle_label)
	hbox.add_child(status_label)
	player_list.add_child(hbox)


func _populate_map_selector() -> void:
	map_selector.clear()
	_map_ids.clear()
	var map_registry: Node = get_node_or_null("/root/MapRegistry")
	if map_registry == null:
		return
	for map_data in map_registry.get_all():
		map_selector.add_item(map_data.display_name)
		_map_ids.append(map_data.id)


func _on_map_selected(index: int) -> void:
	if _is_updating_map_selector or not is_host:
		return
	if index < 0 or index >= _map_ids.size():
		return
	NakamaManager.selected_map = _map_ids[index]
	_announce_selected_map()
	_update_map_ui()


func _on_remote_map_selected(_map_id: String) -> void:
	_update_map_ui()


func _on_remote_bot_count_selected(_bot_count: int) -> void:
	_update_bot_ui()


func _announce_selected_map() -> void:
	if not NakamaManager.current_match:
		return
	var payload := JSON.stringify({
		"map_id": NakamaManager.selected_map,
	})
	NakamaManager.send_match_state(NakamaManager.OpCodes.MAP_SELECT, payload)


func _update_map_ui() -> void:
	if _map_ids.is_empty():
		map_value.text = "MAP: N/A"
		return
	var map_registry: Node = get_node_or_null("/root/MapRegistry")
	if map_registry == null:
		map_value.text = "MAP: N/A"
		return

	var selected_map_id: String = NakamaManager.selected_map
	var map_index: int = map_registry.get_map_index(selected_map_id)
	if not map_registry.has_id(selected_map_id):
		NakamaManager.selected_map = "boneyard"
		map_index = map_registry.get_map_index("boneyard")

	_is_updating_map_selector = true
	map_selector.select(map_index)
	_is_updating_map_selector = false

	var map_data = map_registry.get_by_id(NakamaManager.selected_map)
	map_value.text = "MAP: %s" % map_data.display_name.to_upper()


func _on_bot_count_changed(value: float) -> void:
	if _is_updating_bot_spin or not is_host:
		return
	NakamaManager.set_bot_count(int(value))


func _update_bot_ui() -> void:
	if bot_count_spin == null:
		return
	_is_updating_bot_spin = true
	bot_count_spin.value = NakamaManager.selected_bot_count
	_is_updating_bot_spin = false


func _build_bot_roster() -> Array[Dictionary]:
	var bots: Array[Dictionary] = []
	for i in range(NakamaManager.selected_bot_count):
		var bot_id: String = "bot_%d" % [i + 1]
		bots.append({
			"session_id": bot_id,
			"user_id": bot_id,
			"username": "BOT %d" % [i + 1],
			"selected_vehicle": "sedan",
		})
	return bots
