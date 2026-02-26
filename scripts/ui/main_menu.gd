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
	NakamaManager.create_match()
	
	await NakamaManager.match_joined
	get_tree().change_scene_to_file("res://scenes/ui/Lobby.tscn")


func _on_join_pressed() -> void:
	var code := join_code_input.text.strip_edges().to_upper()
	if code.is_empty():
		status_label.text = "Enter an invite code."
		return
	status_label.text = "Joining %s..." % code
	
	NakamaManager.join_match(code)
	
	await NakamaManager.match_joined
	get_tree().change_scene_to_file("res://scenes/ui/Lobby.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
