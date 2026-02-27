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
var is_player: bool = false ## only true for the local player's car
var network_id: String = "" ## session_id of the owning player
var vehicle_data_id: String = "sedan" ## which vehicle model to load
var is_emp_disabled: bool = false
var _emp_timer: float = 0.0
var current_speed_kmh: float = 0.0
var _steer_current: float = 0.0

# ---------- Weapons ----------
var primary_weapon: WeaponBase = null
var secondary_weapon: WeaponBase = null

# ---------- Node References ----------
@onready var drift_system: CarDriftSystem = $DriftSystem
@onready var fuel_system: CarFuelSystem = $FuelSystem
@onready var damage_system: CarDamageSystem = $DamageSystem
@onready var front_left_wheel: VehicleWheel3D = $FrontLeft
@onready var front_right_wheel: VehicleWheel3D = $FrontRight
@onready var rear_left_wheel: VehicleWheel3D = $RearLeft
@onready var rear_right_wheel: VehicleWheel3D = $RearRight
@onready var weapon_mount: Node3D = $WeaponMount


func _ready() -> void:
	if damage_system:
		damage_system.car_destroyed.connect(_on_car_destroyed)
	if fuel_system:
		fuel_system.fuel_empty.connect(_on_fuel_empty)
	# Non-player cars: disable fuel drain
	if not is_player:
		if fuel_system:
			fuel_system.set_physics_process(false)


func _physics_process(delta: float) -> void:
	if not is_alive:
		engine_force = 0.0
		brake = max_brake_force
		return

	# EMP disable
	if is_emp_disabled:
		_emp_timer -= delta
		engine_force = 0.0
		brake = max_brake_force * 0.5
		if _emp_timer <= 0.0:
			is_emp_disabled = false
		return

	current_speed_kmh = linear_velocity.length() * 3.6

	_handle_steering(delta)
	_handle_acceleration(delta)
	_handle_boost(delta)
	_handle_weapons()


func _handle_steering(delta: float) -> void:
	if not is_player:
		return
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
	if not is_player:
		engine_force = 0.0
		brake = 0.0
		return
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
	if not is_player:
		return
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


func _handle_weapons() -> void:
	if not is_player:
		return
	if Input.is_action_pressed("fire_primary") and primary_weapon and primary_weapon.can_fire():
		primary_weapon.fire()
	if Input.is_action_pressed("fire_secondary") and secondary_weapon and secondary_weapon.can_fire():
		secondary_weapon.fire()


func equip_weapon(weapon: WeaponBase) -> void:
	# Add to tree first so _ready() sets mount_type
	weapon.owner_car = self
	if weapon.get_parent():
		weapon.reparent(weapon_mount)
	else:
		weapon_mount.add_child(weapon)

	# Now check slot (mount_type is set by _ready)
	var slot := weapon.mount_type
	if slot == WeaponBase.MountType.PRIMARY:
		if primary_weapon and primary_weapon != weapon:
			drop_weapon(WeaponBase.MountType.PRIMARY)
		primary_weapon = weapon
	else:
		if secondary_weapon and secondary_weapon != weapon:
			drop_weapon(WeaponBase.MountType.SECONDARY)
		secondary_weapon = weapon


func drop_weapon(slot: WeaponBase.MountType) -> void:
	var weapon: WeaponBase
	if slot == WeaponBase.MountType.PRIMARY:
		weapon = primary_weapon
		primary_weapon = null
	else:
		weapon = secondary_weapon
		secondary_weapon = null
	if weapon:
		weapon.queue_free()


func apply_emp(duration: float) -> void:
	is_emp_disabled = true
	_emp_timer = duration


func _on_car_destroyed() -> void:
	is_alive = false
	car_destroyed.emit(self )


func _on_fuel_empty() -> void:
	is_alive = false
	car_stalled.emit(self )
