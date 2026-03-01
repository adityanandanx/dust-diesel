extends Control
class_name MatchEndDialog

signal restart_requested()
signal rejoin_requested()
signal back_to_menu_requested()
signal settings_changed(game_mode: String, match_time_seconds: int, map_id: String, bot_count: int)

@onready var title_label: Label = %TitleLabel
@onready var winners_label: Label = %WinnersLabel
@onready var scoreboard_label: Label = %ScoreboardLabel
@onready var settings_box: VBoxContainer = %SettingsBox
@onready var waiting_label: Label = %WaitingLabel
@onready var mode_selector: OptionButton = %ModeSelector
@onready var time_spin: SpinBox = %TimeSpin
@onready var map_selector: OptionButton = %MapSelector
@onready var bots_spin: SpinBox = %BotsSpin
@onready var rejoin_restart_button: Button = %RejoinRestartButton
@onready var back_button: Button = %BackButton

var _map_ids: Array[String] = []
var _syncing: bool = false


func _ready() -> void:
	visible = false
	_ensure_mode_selector_populated()
	rejoin_restart_button.pressed.connect(_on_rejoin_restart_pressed)
	back_button.pressed.connect(_on_back_pressed)
	mode_selector.item_selected.connect(_on_settings_edited)
	time_spin.value_changed.connect(_on_settings_edited_value)
	map_selector.item_selected.connect(_on_settings_edited)
	bots_spin.value_changed.connect(_on_settings_edited_value)


func show_results(winner_name: String, kill_counts: Dictionary) -> void:
	var standings: Array[Dictionary] = []
	for key_variant in kill_counts.keys():
		var entry: Variant = kill_counts[key_variant]
		if not (entry is Dictionary):
			continue
		var item: Dictionary = entry
		var player_name: String = str(item.get("name", str(key_variant)))
		var kills: int = int(item.get("kills", 0))
		standings.append({
			"name": player_name,
			"kills": kills,
		})

	standings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ak: int = int(a.get("kills", 0))
		var bk: int = int(b.get("kills", 0))
		if ak == bk:
			return str(a.get("name", "")) < str(b.get("name", ""))
		return ak > bk
	)

	var winners: PackedStringArray = _build_winners_from_standings(standings)
	if winners.is_empty():
		winners = _parse_winner_names(winner_name)
	title_label.text = "WINNER" if winners.size() <= 1 else "WINNERS"
	winners_label.text = "\n".join(winners)

	var lines: PackedStringArray = PackedStringArray()
	lines.append("SCOREBOARD")
	for i in range(standings.size()):
		var row: Dictionary = standings[i]
		lines.append("%d. %s  -  %d" % [i + 1, str(row.get("name", "Unknown")), int(row.get("kills", 0))])
	if standings.is_empty():
		lines.append("No scores yet.")

	scoreboard_label.text = "\n".join(lines)
	visible = true


func _build_winners_from_standings(standings: Array[Dictionary]) -> PackedStringArray:
	if standings.is_empty():
		return PackedStringArray()

	var top_kills: int = int(standings[0].get("kills", 0))
	if top_kills <= 0:
		return PackedStringArray(["No winner"])

	var winners: PackedStringArray = PackedStringArray()
	for row in standings:
		var kills: int = int(row.get("kills", 0))
		if kills != top_kills:
			break
		winners.append(str(row.get("name", "Unknown")))
	return winners


func hide_results() -> void:
	visible = false


func configure_menu(is_host: bool, settings: Dictionary) -> void:
	settings_box.visible = is_host
	waiting_label.visible = not is_host
	rejoin_restart_button.disabled = false
	if is_host:
		rejoin_restart_button.text = "RESTART MATCH"
		waiting_label.text = ""
		_apply_settings_to_controls(settings)
	else:
		rejoin_restart_button.text = "REJOIN"
		waiting_label.text = "Press Rejoin, then wait for host to restart."


func set_waiting(waiting: bool, is_host: bool = false) -> void:
	if is_host:
		waiting_label.visible = false
		rejoin_restart_button.disabled = waiting
		rejoin_restart_button.text = "RESTART MATCH"
		return

	waiting_label.visible = true
	if waiting:
		waiting_label.text = "Waiting for host to restart..."
		rejoin_restart_button.disabled = true
		rejoin_restart_button.text = "WAITING..."
	else:
		waiting_label.text = "Press Rejoin, then wait for host to restart."
		rejoin_restart_button.disabled = false
		rejoin_restart_button.text = "REJOIN"


func _populate_map_selector(selected_map_id: String = "boneyard") -> void:
	map_selector.clear()
	_map_ids.clear()
	var map_registry: Node = get_node_or_null("/root/MapRegistry")
	if map_registry == null:
		map_selector.add_item("Boneyard")
		_map_ids.append("boneyard")
		map_selector.select(0)
		return

	for map_data in map_registry.get_all():
		map_selector.add_item(map_data.display_name)
		_map_ids.append(map_data.id)

	var idx: int = _map_ids.find(selected_map_id)
	if idx < 0:
		idx = 0
	if idx >= 0:
		map_selector.select(idx)


func _apply_settings_to_controls(settings: Dictionary) -> void:
	_syncing = true
	_ensure_mode_selector_populated()
	mode_selector.select(0)
	var match_seconds: int = int(settings.get("match_time_seconds", 300))
	time_spin.value = maxi(1, int(round(float(match_seconds) / 60.0)))
	bots_spin.value = int(settings.get("bot_count", 3))
	_populate_map_selector(str(settings.get("map_id", "boneyard")))
	_syncing = false


func _ensure_mode_selector_populated() -> void:
	if mode_selector.item_count == 0:
		mode_selector.add_item("FREE FOR ALL")


func _parse_winner_names(raw_winners: String) -> PackedStringArray:
	var text: String = raw_winners.strip_edges()
	if text.is_empty():
		return PackedStringArray(["TBD"])

	var split_regex := RegEx.new()
	if split_regex.compile("\\s*(,|&|\\+|\\||\\band\\b)\\s*") != OK:
		return PackedStringArray([text])

	var normalized: String = split_regex.sub(text, "\n", true)
	var parts: PackedStringArray = normalized.split("\n", false)
	if parts.is_empty():
		return PackedStringArray([text])

	var cleaned: PackedStringArray = PackedStringArray()
	for name_part in parts:
		var trimmed: String = name_part.strip_edges()
		if not trimmed.is_empty():
			cleaned.append(trimmed)
	if cleaned.is_empty():
		cleaned.append(text)
	return cleaned


func _settings_from_controls() -> Dictionary:
	var map_id: String = "boneyard"
	var idx: int = map_selector.get_selected_id()
	if idx >= 0 and idx < _map_ids.size():
		map_id = _map_ids[idx]
	return {
		"game_mode": "free_for_all",
		"match_time_seconds": int(time_spin.value) * 60,
		"map_id": map_id,
		"bot_count": int(bots_spin.value),
	}


func _on_rejoin_restart_pressed() -> void:
	if settings_box.visible:
		restart_requested.emit()
	else:
		rejoin_requested.emit()


func _on_back_pressed() -> void:
	back_to_menu_requested.emit()


func _on_settings_edited(_value: Variant = null) -> void:
	if _syncing or not settings_box.visible:
		return
	var settings: Dictionary = _settings_from_controls()
	settings_changed.emit(
		str(settings.get("game_mode", "free_for_all")),
		int(settings.get("match_time_seconds", 300)),
		str(settings.get("map_id", "boneyard")),
		int(settings.get("bot_count", 0))
	)


func _on_settings_edited_value(_value: float) -> void:
	_on_settings_edited(_value)
