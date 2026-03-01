extends Control

## Main Menu — create or join a game session.

@export var lobby_scene: PackedScene

@onready var join_code_input: LineEdit = $CenterPanel/VBox/JoinRow/CodeInput
@onready var status_label: Label = $CenterPanel/VBox/StatusLabel

var _is_connecting: bool = false


func _ready() -> void:
	$CenterPanel/VBox/CreateButton.pressed.connect(_on_create_pressed)
	$CenterPanel/VBox/JoinRow/JoinButton.pressed.connect(_on_join_pressed)
	$CenterPanel/VBox/QuitButton.pressed.connect(_on_quit_pressed)


func _on_create_pressed() -> void:
	if _is_connecting:
		return
	_is_connecting = true
	status_label.text = "Creating lobby..."
	var ok: bool = await NakamaManager.create_match()
	if not ok:
		status_label.text = "Failed to create lobby."
		_is_connecting = false
		return
	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	if tree:
		if lobby_scene:
			tree.change_scene_to_packed(lobby_scene)
		else:
			tree.change_scene_to_file("res://scenes/ui/Lobby.tscn")
	_is_connecting = false


func _on_join_pressed() -> void:
	if _is_connecting:
		return
	var code := join_code_input.text.strip_edges().to_upper()
	if code.is_empty():
		status_label.text = "Enter an invite code."
		return
	_is_connecting = true
	status_label.text = "Joining %s..." % code

	var ok: bool = await NakamaManager.join_match(code)
	if not ok:
		status_label.text = "Failed to join %s." % code
		_is_connecting = false
		return
	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	if tree:
		if lobby_scene:
			tree.change_scene_to_packed(lobby_scene)
		else:
			tree.change_scene_to_file("res://scenes/ui/Lobby.tscn")
	_is_connecting = false


func _on_quit_pressed() -> void:
	get_tree().quit()
