extends Area3D
class_name PickupBase

## Base pickup — Area3D trigger, bob animation, auto-despawn, apply on collect.

signal collected(car: Node)

@export var despawn_time: float = 30.0
@export var bob_height: float = 0.3
@export var bob_speed: float = 2.0
@export var spin_speed: float = 1.5

var _age: float = 0.0
var _start_y: float = 0.0
var _is_collected: bool = false


func _ready() -> void:
	_start_y = global_position.y + 1.0 # float above ground
	global_position.y = _start_y
	body_entered.connect(_on_body_entered)
	collision_layer = 16 # pickup layer
	collision_mask = 1 # cars only


func _process(delta: float) -> void:
	if _is_collected:
		return
	_age += delta

	# Bob animation
	global_position.y = _start_y + sin(_age * bob_speed) * bob_height

	# Spin
	rotate_y(spin_speed * delta)

	# Auto-despawn
	if _age >= despawn_time:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if _is_collected:
		return
	if body is VehicleBody3D:
		_is_collected = true
		apply(body)
		collected.emit(body)
		queue_free()


## Override in subclasses to apply effect
func apply(_car: VehicleBody3D) -> void:
	pass
