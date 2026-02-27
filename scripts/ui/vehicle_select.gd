extends Control

## Vehicle selection screen — pick your car before the match.

const VehicleDataScript = preload("res://scripts/car/vehicle_data.gd")

var _all_vehicles: Array = []
var _current_index: int = 0
var _preview_instance: Node3D = null

@onready var vehicle_name_label: Label = $Panel/VBox/VehicleName
@onready var stats_speed: ProgressBar = $Panel/VBox/StatsGrid/SpeedBar
@onready var stats_armor: ProgressBar = $Panel/VBox/StatsGrid/ArmorBar
@onready var stats_weight: ProgressBar = $Panel/VBox/StatsGrid/WeightBar
@onready var preview_viewport: SubViewport = $Panel/VBox/PreviewContainer/SubViewportContainer/SubViewport
@onready var turntable: Node3D = $Panel/VBox/PreviewContainer/SubViewportContainer/SubViewport/Turntable
@onready var left_button: Button = $Panel/VBox/NavRow/LeftButton
@onready var right_button: Button = $Panel/VBox/NavRow/RightButton
@onready var confirm_button: Button = $Panel/VBox/ConfirmButton


func _ready() -> void:
	_all_vehicles = VehicleRegistry.get_all()
	left_button.pressed.connect(_on_left)
	right_button.pressed.connect(_on_right)
	confirm_button.pressed.connect(_on_confirm)

	# Pre-select the currently chosen vehicle
	var my_sess_id := ""
	if NakamaManager.current_match:
		my_sess_id = NakamaManager.current_match.self_user.session_id
	var current_id := "sedan"
	if my_sess_id in NakamaManager.connected_players:
		current_id = NakamaManager.connected_players[my_sess_id].get("selected_vehicle", "sedan")
	_current_index = VehicleRegistry.get_vehicle_index(current_id)

	_update_preview()


func _process(_delta: float) -> void:
	# Slowly rotate the turntable
	if turntable:
		turntable.rotate_y(_delta * 0.8)


func _on_left() -> void:
	_current_index = wrapi(_current_index - 1, 0, _all_vehicles.size())
	_update_preview()


func _on_right() -> void:
	_current_index = wrapi(_current_index + 1, 0, _all_vehicles.size())
	_update_preview()


func _on_confirm() -> void:
	var vdata = _all_vehicles[_current_index]

	# Store locally
	if NakamaManager.current_match:
		var my_sess_id = NakamaManager.current_match.self_user.session_id
		if my_sess_id in NakamaManager.connected_players:
			NakamaManager.connected_players[my_sess_id]["selected_vehicle"] = vdata.id

		# Broadcast to peers
		var payload := JSON.stringify({
			"session_id": my_sess_id,
			"vehicle_id": vdata.id,
		})
		NakamaManager.send_match_state(NakamaManager.OpCodes.VEHICLE_SELECT, payload)

	# Return to lobby
	get_tree().change_scene_to_file("res://scenes/ui/Lobby.tscn")


func _update_preview() -> void:
	var vdata = _all_vehicles[_current_index]

	# Update labels
	vehicle_name_label.text = vdata.display_name.to_upper()

	# Stat bars — UI stats are pre-normalized 0–100 by VehicleRegistry
	stats_speed.value = clampf(vdata.ui_speed, 0.0, 100.0)
	stats_armor.value = clampf(vdata.ui_armor, 0.0, 100.0)
	stats_weight.value = clampf(vdata.ui_weight, 0.0, 100.0)

	# Swap the 3D model on the turntable
	if turntable:
		# Remove old preview
		for child in turntable.get_children():
			if child is Node3D and child.name != "PreviewCamera" and child.name != "PreviewLight":
				child.queue_free()

		var body_scene: PackedScene = load(vdata.preview_model_path)
		if body_scene:
			_preview_instance = body_scene.instantiate()
			turntable.add_child(_preview_instance)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/ui/Lobby.tscn")
