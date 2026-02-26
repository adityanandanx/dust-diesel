extends Node
class_name CarDriftSystem

## Detects drift state and fills boost meter.
## Child of a Car (VehicleBody3D) node.

signal drift_started()
signal drift_ended(drift_duration: float, boost_earned: float)

@export var drift_friction: float = 1.2
@export var normal_friction: float = 3.0
@export var min_drift_speed: float = 15.0 ## km/h
@export var boost_fill_rate: float = 25.0 ## per second while drifting
@export var perfect_drift_bonus: float = 20.0

var is_drifting: bool = false
var drift_duration: float = 0.0

@onready var car: Car = get_parent()


func _physics_process(delta: float) -> void:
	if not car or not car.is_alive:
		return

	var speed := car.current_speed_kmh
	var braking := Input.is_action_pressed("brake")
	var has_steer: bool = abs(Input.get_axis("steer_right", "steer_left")) > 0.2
	var lateral: float = abs(car.get_lateral_speed())

	var should_drift := braking and has_steer and speed > min_drift_speed

	if should_drift and not is_drifting:
		_start_drift()
	elif not should_drift and is_drifting:
		_end_drift()

	if is_drifting:
		drift_duration += delta
		var drift_intensity := clampf(lateral / 10.0, 0.2, 1.0)
		car.add_boost(boost_fill_rate * drift_intensity * delta)


func _start_drift() -> void:
	is_drifting = true
	drift_duration = 0.0
	car.rear_left_wheel.wheel_friction_slip = drift_friction
	car.rear_right_wheel.wheel_friction_slip = drift_friction
	drift_started.emit()


func _end_drift() -> void:
	is_drifting = false
	car.rear_left_wheel.wheel_friction_slip = normal_friction
	car.rear_right_wheel.wheel_friction_slip = normal_friction
	var boost_earned := 0.0
	if drift_duration > 1.0:
		boost_earned = perfect_drift_bonus * minf(drift_duration, 5.0)
		car.add_boost(boost_earned)
	drift_ended.emit(drift_duration, boost_earned)
