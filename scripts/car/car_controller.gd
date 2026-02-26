extends VehicleBody3D
class_name Car

## Main vehicle controller — input, steering, acceleration, boost.
## Integrates with child DriftSystem, FuelSystem, DamageSystem nodes.

# ---------- Signals ----------
signal car_destroyed(car: Car)
signal car_stalled(car: Car)

# ---------- Exports ----------
@export_group("Engine")
@export var max_engine_force: float = 4000.0
@export var max_brake_force: float = 200.0
@export var max_speed_kmh: float = 120.0
@export var reverse_force_ratio: float = 0.6

@export_group("Steering")
@export var max_steer_angle: float = 0.4 ## radians
@export var steer_speed: float = 3.0
@export var steer_return_speed: float = 5.0

@export_group("Boost")
@export var boost_force_multiplier: float = 2.0
@export var boost_meter_max: float = 100.0
@export var boost_drain_rate: float = 30.0

# ---------- State ----------
var boost_meter: float = 0.0
var is_boosting: bool = false
var is_alive: bool = true
var current_speed_kmh: float = 0.0
var _steer_current: float = 0.0

# ---------- Node References ----------
@onready var drift_system: CarDriftSystem = $DriftSystem
@onready var fuel_system: CarFuelSystem = $FuelSystem
@onready var damage_system: CarDamageSystem = $DamageSystem
@onready var front_left_wheel: VehicleWheel3D = $FrontLeft
@onready var front_right_wheel: VehicleWheel3D = $FrontRight
@onready var rear_left_wheel: VehicleWheel3D = $RearLeft
@onready var rear_right_wheel: VehicleWheel3D = $RearRight


func _ready() -> void:
	if damage_system:
		damage_system.car_destroyed.connect(_on_car_destroyed)
	if fuel_system:
		fuel_system.fuel_empty.connect(_on_fuel_empty)


func _physics_process(delta: float) -> void:
	if not is_alive:
		engine_force = 0.0
		brake = max_brake_force
		return

	current_speed_kmh = linear_velocity.length() * 3.6

	_handle_steering(delta)
	_handle_acceleration(delta)
	_handle_boost(delta)


func _handle_steering(delta: float) -> void:
	var steer_input := Input.get_axis("steer_right", "steer_left")
	var steer_target := steer_input * max_steer_angle

	# Reduce steering at high speed
	var speed_factor := clampf(1.0 - (current_speed_kmh / max_speed_kmh) * 0.5, 0.3, 1.0)
	steer_target *= speed_factor

	# Apply steering bias from wheel damage
	if damage_system:
		steer_target += damage_system.get_steering_bias()

	# Smooth interpolation
	if abs(steer_target) > 0.01:
		_steer_current = move_toward(_steer_current, steer_target, steer_speed * delta)
	else:
		_steer_current = move_toward(_steer_current, 0.0, steer_return_speed * delta)

	steering = _steer_current


func _handle_acceleration(_delta: float) -> void:
	var accel := Input.get_action_strength("accelerate")
	var brake_input := Input.get_action_strength("brake")

	var speed_mod := 1.0
	if damage_system:
		speed_mod = damage_system.get_speed_modifier()

	if accel > 0.0:
		if current_speed_kmh < max_speed_kmh * speed_mod:
			var force_mult := boost_force_multiplier if is_boosting else 1.0
			engine_force = max_engine_force * accel * force_mult * speed_mod
		else:
			engine_force = 0.0
		brake = 0.0
	elif brake_input > 0.0:
		var forward_speed := get_forward_speed()
		if forward_speed > 1.0:
			engine_force = 0.0
			brake = max_brake_force * brake_input
		else:
			engine_force = - max_engine_force * reverse_force_ratio * brake_input
			brake = 0.0
	else:
		engine_force = 0.0
		brake = 0.0


func _handle_boost(delta: float) -> void:
	if Input.is_action_pressed("boost") and boost_meter > 0.0:
		is_boosting = true
		boost_meter = maxf(boost_meter - boost_drain_rate * delta, 0.0)
		if fuel_system:
			fuel_system.apply_boost_drain(delta)
	else:
		is_boosting = false


func add_boost(amount: float) -> void:
	boost_meter = minf(boost_meter + amount, boost_meter_max)


## Positive = moving forward along local +Z
func get_forward_speed() -> float:
	return transform.basis.z.dot(linear_velocity)


## Sideways velocity component
func get_lateral_speed() -> float:
	return transform.basis.x.dot(linear_velocity)


func _on_car_destroyed() -> void:
	is_alive = false
	car_destroyed.emit(self )


func _on_fuel_empty() -> void:
	is_alive = false
	car_stalled.emit(self )
