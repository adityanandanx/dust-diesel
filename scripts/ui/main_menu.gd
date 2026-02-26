extends Control

## Main Menu — create or join a game session.

@onready var join_code_input: LineEdit = $CenterPanel/VBox/JoinRow/CodeInput
@onready var status_label: Label = $CenterPanel/VBox/StatusLabel


func _ready() -> void:
	$CenterPanel/VBox/CreateButton.pressed.connect(_on_create_pressed)
	$CenterPanel/VBox/JoinRow/JoinButton.pressed.connect(_on_join_pressed)
	$CenterPanel/VBox/QuitButton.pressed.connect(_on_quit_pressed)


func _on_create_pressed() -> void:
	status_label.text = "Creating lobby..."
	# For Phase 1 local testing, go straight to the game
	get_tree().change_scene_to_file("res://scenes/game/Game.tscn")


func _on_join_pressed() -> void:
	var code := join_code_input.text.strip_edges().to_upper()
	if code.is_empty():
		status_label.text = "Enter an invite code."
		return
	status_label.text = "Joining %s..." % code
	# Multiplayer join will be added in Phase 4
	get_tree().change_scene_to_file("res://scenes/game/Game.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
