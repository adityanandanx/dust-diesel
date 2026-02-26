extends Camera3D

## Top-down follow camera that rotates with the car.

@export var offset: Vector3 = Vector3(0, 20, -12)
@export var follow_speed: float = 5.0
@export var rotation_speed: float = 4.0

var _target: Node3D


func _ready() -> void:
	top_level = true
	_target = get_parent()
	
	# Only activate camera for the local player's car
	if _target.has_method("get") and _target.is_player:
		make_current()
	else:
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	if not _target:
		return
	# Rotate offset around Y to match car's heading
	var rotated_offset := _target.global_basis * offset
	var goal := _target.global_position + rotated_offset
	global_position = global_position.lerp(goal, follow_speed * delta)
	# Smoothly look at car
	var target_pos := _target.global_position
	var desired_transform := global_transform.looking_at(target_pos, Vector3.UP)
	global_transform = global_transform.interpolate_with(desired_transform, rotation_speed * delta)
