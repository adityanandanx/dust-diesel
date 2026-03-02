extends Control

## Host game setup screen.
## Configures game mode and match settings before start.

@export var game_scene: PackedScene
@export var lobby_scene: PackedScene

@onready var mode_selector: OptionButton = $Center/VBox/ModeRow/ModeSelector
@onready var time_spin: SpinBox = $Center/VBox/TimeRow/TimeSpin
@onready var map_selector: OptionButton = $Center/VBox/MapRow/MapSelector
@onready var bots_spin: SpinBox = $Center/VBox/BotRow/BotCountSpin
@onready var status_label: Label = $Center/VBox/StatusLabel
@onready var start_button: Button = $Center/VBox/ButtonRow/StartButton
@onready var back_button: Button = $Center/VBox/ButtonRow/BackButton

var _is_host: bool = false
var _map_ids: Array[String] = []
var _is_syncing_ui: bool = false


func _ready() -> void:
	_is_host = NakamaManager.is_host

	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)
	mode_selector.item_selected.connect(_on_mode_selected)
	time_spin.value_changed.connect(_on_time_changed)
	map_selector.item_selected.connect(_on_map_selected)
	bots_spin.value_changed.connect(_on_bot_count_changed)

	if NakamaManager.current_match:
		NakamaManager.game_started.connect(_on_game_started)
		NakamaManager.game_settings_updated.connect(_on_remote_game_settings_updated)
		NakamaManager.map_selected.connect(_on_remote_map_updated)
		NakamaManager.bot_count_selected.connect(_on_remote_bot_updated)

	_populate_game_modes()
	_populate_map_selector()
	_refresh_ui_from_settings()
	_apply_host_permissions()

	if _is_host:
		NakamaManager.set_game_settings(
			NakamaManager.selected_game_mode,
			NakamaManager.selected_match_time_seconds,
			NakamaManager.selected_map,
			NakamaManager.selected_bot_count,
			true
		)


func _populate_game_modes() -> void:
	mode_selector.clear()
	mode_selector.add_item("FREE FOR ALL")


func _populate_map_selector() -> void:
	map_selector.clear()
	_map_ids.clear()
	var map_registry: Node = get_node_or_null("/root/MapRegistry")
	if map_registry == null:
		return
	for map_data in map_registry.get_all():
		map_selector.add_item(map_data.display_name)
		_map_ids.append(map_data.id)


func _refresh_ui_from_settings() -> void:
	_is_syncing_ui = true
	mode_selector.select(0)
	time_spin.value = maxi(1, int(float(NakamaManager.selected_match_time_seconds) / 60.0))
	bots_spin.value = NakamaManager.selected_bot_count

	var map_index: int = _map_ids.find(NakamaManager.selected_map)
	if map_index < 0 and not _map_ids.is_empty():
		map_index = 0
	if map_index >= 0:
		map_selector.select(map_index)
	_is_syncing_ui = false


func _apply_host_permissions() -> void:
	mode_selector.disabled = not _is_host
	time_spin.editable = _is_host
	map_selector.disabled = not _is_host
	bots_spin.editable = _is_host
	start_button.visible = _is_host

	if _is_host:
		status_label.text = "Configure match settings and start."
	else:
		status_label.text = "Waiting for host to configure and start."


func _on_mode_selected(_index: int) -> void:
	if _is_syncing_ui or not _is_host:
		return
	_push_local_settings()


func _on_time_changed(_value: float) -> void:
	if _is_syncing_ui or not _is_host:
		return
	_push_local_settings()


func _on_map_selected(_index: int) -> void:
	if _is_syncing_ui or not _is_host:
		return
	_push_local_settings()


func _on_bot_count_changed(_value: float) -> void:
	if _is_syncing_ui or not _is_host:
		return
	_push_local_settings()


func _push_local_settings() -> void:
	var map_id: String = "boneyard"
	var map_index: int = map_selector.get_selected_id()
	if map_index >= 0 and map_index < _map_ids.size():
		map_id = _map_ids[map_index]
	var match_seconds: int = int(time_spin.value) * 60
	NakamaManager.set_game_settings("free_for_all", match_seconds, map_id, int(bots_spin.value), true)


func _on_start_pressed() -> void:
	if not _is_host or not NakamaManager.current_match:
		return
	_push_local_settings()
	NakamaManager.sync_bot_roster(_build_bot_roster())
	NakamaManager.set_match_phase(NakamaManager.MATCH_PHASE_IN_PROGRESS)
	NakamaManager.send_match_state(NakamaManager.OpCodes.GAME_STARTED, "")
	_on_game_started()


func _on_back_pressed() -> void:
	if lobby_scene:
		get_tree().change_scene_to_packed(lobby_scene)
	else:
		get_tree().change_scene_to_file("res://scenes/ui/Lobby.tscn")


func _on_game_started() -> void:
	if game_scene:
		get_tree().change_scene_to_packed(game_scene)
	else:
		get_tree().change_scene_to_file("res://scenes/game/Game.tscn")


func _on_remote_game_settings_updated(_settings: Dictionary) -> void:
	_refresh_ui_from_settings()


func _on_remote_map_updated(_map_id: String) -> void:
	_refresh_ui_from_settings()


func _on_remote_bot_updated(_bot_count: int) -> void:
	_refresh_ui_from_settings()


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
