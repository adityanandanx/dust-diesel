extends Control
class_name PauseMenu

signal resume_requested
signal main_menu_requested

@onready var resume_button: Button = %ResumeButton
@onready var main_menu_button: Button = %MainMenuButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	if resume_button and not resume_button.pressed.is_connected(_on_resume_pressed):
		resume_button.pressed.connect(_on_resume_pressed)
	if main_menu_button and not main_menu_button.pressed.is_connected(_on_main_menu_pressed):
		main_menu_button.pressed.connect(_on_main_menu_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		resume_requested.emit()


func _on_resume_pressed() -> void:
	resume_requested.emit()


func _on_main_menu_pressed() -> void:
	main_menu_requested.emit()
