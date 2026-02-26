extends Control

## Lobby screen — shows connected players, ready toggle, start button for host.

@onready var code_label: Label = $Center/VBox/CodeLabel
@onready var player_list: VBoxContainer = $Center/VBox/PlayerList
@onready var ready_button: Button = $Center/VBox/ButtonRow/ReadyButton
@onready var start_button: Button = $Center/VBox/ButtonRow/StartButton
@onready var back_button: Button = $Center/VBox/BackButton

var is_ready: bool = false
var is_host: bool = true
var invite_code: String = ""


func _ready() -> void:
	ready_button.pressed.connect(_on_ready_pressed)
	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)

	if NakamaManager.current_match:
		invite_code = NakamaManager.match_name
		code_label.text = "INVITE CODE: %s" % invite_code
		
		# Assuming host is the one who created it (simplification for relayed matches)
		# A better check would be if we are the only one in the lobby on join
		is_host = NakamaManager.connected_players.size() <= 1
		NakamaManager.is_host = is_host
		start_button.visible = is_host

		NakamaManager.player_joined.connect(_on_player_joined)
		NakamaManager.player_left.connect(_on_player_left)
		NakamaManager.game_started.connect(_on_game_started)
		
		_refresh_players()
	else:
		code_label.text = "NOT CONNECTED"
		start_button.visible = false


func _on_ready_pressed() -> void:
	is_ready = not is_ready
	ready_button.text = "UNREADY" if is_ready else "READY"


func _on_start_pressed() -> void:
	if is_host and NakamaManager.current_match:
		NakamaManager.send_match_state(NakamaManager.OpCodes.GAME_STARTED, "")
		_on_game_started()


func _on_back_pressed() -> void:
	NakamaManager.leave_match()
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")


func _on_game_started() -> void:
	get_tree().change_scene_to_file("res://scenes/game/Game.tscn")


func _refresh_players() -> void:
	# Clear list
	for child in player_list.get_children():
		child.queue_free()
		
	# Re-add everyone
	for sess_id in NakamaManager.connected_players:
		var p_data: Dictionary = NakamaManager.connected_players[sess_id]
		var is_me = (NakamaManager.current_match and sess_id == NakamaManager.current_match.self_user.session_id)
		var display_name = p_data.get("username", "Unknown")
		if is_me:
			display_name += " (You)"
		_add_player_entry(display_name, true)


func _on_player_joined(_sess_id: String, _user_id: String, _username: String) -> void:
	_refresh_players()


func _on_player_left(_sess_id: String) -> void:
	_refresh_players()


func _add_player_entry(player_name: String, ready_state: bool) -> void:
	var hbox := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = player_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var status_label := Label.new()
	status_label.text = "READY" if ready_state else "NOT READY"
	status_label.add_theme_color_override("font_color", Color.GREEN if ready_state else Color.RED)
	hbox.add_child(name_label)
	hbox.add_child(status_label)
	player_list.add_child(hbox)
