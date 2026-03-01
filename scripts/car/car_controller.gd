extends VehicleBody3D
class_name Car

const EMP_LIGHTNING_SHADER: Shader = preload("res://resources/emp_lightning.gdshader")
const KILL_CREDIT_WINDOW_MS: int = 12000

## Main vehicle controller — input, steering, acceleration, boost.
## Integrates with child DriftSystem, FuelSystem, DamageSystem nodes.

# ---------- Signals ----------
signal car_destroyed(car: Car)
signal car_stalled(car: Car)
signal collision_impact(impact_speed: float)
signal weapon_fired(mount_slot: int, intensity: float)
signal powerup_started(powerup_id: String, duration: float)
signal powerup_updated(powerup_id: String, remaining: float, duration: float)
signal powerup_ended(powerup_id: String)

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

@export_group("EMP FX")
@export var emp_fx_intensity: float = 1.0
@export var emp_fx_random_scale: float = 4.6
@export var emp_fx_speed: float = 5.1

@export_group("Weapon Aim")
@export var mouse_aim_enabled: bool = true
@export var mouse_aim_distance: float = 450.0
@export var mouse_aim_collision_mask: int = 0xFFFFFFFF

# ---------- State ----------
var boost_meter: float = 0.0
var is_boosting: bool = false
var is_alive: bool = true
var is_player: bool = false ## only true for the local player's car
var uses_player_input: bool = true
var is_bot: bool = false
var network_id: String = "" ## session_id of the owning player
var vehicle_data_id: String = "sedan" ## which vehicle model to load
var is_emp_disabled: bool = false
var _emp_timer: float = 0.0
var current_speed_kmh: float = 0.0
var _steer_current: float = 0.0
var _collision_signal_cooldown: float = 0.0
var active_powerups: Dictionary = {} # String -> {duration: float, remaining: float}
var _emp_fx_active: bool = false
var _emp_meshes: Array[MeshInstance3D] = []
var _emp_original_overlays: Dictionary = {}
var _aim_point_world: Vector3 = Vector3.ZERO
var _last_attacker_session_id: String = ""
var _last_attacker_name: String = ""
var _last_attacker_timestamp_ms: int = 0

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
@onready var weapon_mount_primary: Node3D = $WeaponMountPrimary
@onready var weapon_mount_secondary: Node3D = $WeaponMountSecondary

@export_group("Damage Hit Mapping")
@export var wheel_hit_radius: float = 0.95
@export var weapon_mount_hit_radius: float = 0.9
@export var engine_hit_front_ratio: float = 0.2


func _ready() -> void:
	add_to_group("cars")
	if damage_system:
		damage_system.car_destroyed.connect(_on_car_destroyed)
	if fuel_system:
		fuel_system.fuel_empty.connect(_on_fuel_empty)
	contact_monitor = true
	max_contacts_reported = 6
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	# Disable fuel drain for non-player-input cars (remote peers and bots).
	if not is_player or not uses_player_input or is_bot:
		if fuel_system:
			fuel_system.set_physics_process(false)
	_cache_emp_meshes()


func _physics_process(delta: float) -> void:
	_collision_signal_cooldown = maxf(_collision_signal_cooldown - delta, 0.0)
	_tick_powerups(delta)

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
			_set_emp_fx(false)
		return

	current_speed_kmh = linear_velocity.length() * 3.6

	_handle_steering(delta)
	_handle_acceleration(delta)
	_handle_boost(delta)
	_update_weapon_aim()
	_handle_weapons()


func _handle_steering(delta: float) -> void:
	if not is_player or not uses_player_input:
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
	if not is_player or not uses_player_input:
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
	if not is_player or not uses_player_input:
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
	if not is_player or not uses_player_input:
		return
	if Input.is_action_pressed("fire_primary") and primary_weapon and primary_weapon.can_fire():
		primary_weapon.fire()
		weapon_fired.emit(WeaponBase.MountType.PRIMARY, _weapon_recoil_intensity(primary_weapon))
	if Input.is_action_pressed("fire_secondary") and secondary_weapon and secondary_weapon.can_fire():
		secondary_weapon.fire()
		weapon_fired.emit(WeaponBase.MountType.SECONDARY, _weapon_recoil_intensity(secondary_weapon))


func _update_weapon_aim() -> void:
	if not is_player or not mouse_aim_enabled:
		return

	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return

	var mouse_pos: Vector2
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		mouse_pos = get_viewport().get_visible_rect().size * 0.5
	else:
		mouse_pos = get_viewport().get_mouse_position()

	var ray_origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(mouse_pos).normalized()
	var ray_end: Vector3 = ray_origin + ray_dir * mouse_aim_distance

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.exclude = [ self.get_rid()]
	query.collision_mask = mouse_aim_collision_mask
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)

	if hit.is_empty():
		_aim_point_world = ray_end
	else:
		_aim_point_world = hit.get("position", ray_end)

	if primary_weapon:
		primary_weapon.update_aim_target(_aim_point_world)


func equip_weapon(weapon: WeaponBase) -> void:
	# Ensure the weapon enters the tree so subclasses that set mount_type in _ready() are initialized.
	weapon.owner_car = self
	if not weapon.is_inside_tree():
		add_child(weapon)

	var slot: WeaponBase.MountType = weapon.mount_type
	if slot == WeaponBase.MountType.PRIMARY:
		if primary_weapon and primary_weapon != weapon:
			drop_weapon(WeaponBase.MountType.PRIMARY)
		primary_weapon = weapon
		if primary_weapon.get_parent() != weapon_mount_primary:
			primary_weapon.reparent(weapon_mount_primary)
		# Snap weapon exactly to mount transform.
		primary_weapon.transform = Transform3D.IDENTITY
	else:
		if secondary_weapon and secondary_weapon != weapon:
			drop_weapon(WeaponBase.MountType.SECONDARY)
		secondary_weapon = weapon
		if secondary_weapon.get_parent() != weapon_mount_secondary:
			secondary_weapon.reparent(weapon_mount_secondary)
		# Snap weapon exactly to mount transform.
		secondary_weapon.transform = Transform3D.IDENTITY


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
	_set_emp_fx(true)


func get_emp_remaining() -> float:
	return maxf(_emp_timer, 0.0)


func register_powerup(powerup_id: String, duration: float) -> void:
	var display_duration: float = maxf(duration, 1.5)
	active_powerups[powerup_id] = {
		"duration": display_duration,
		"remaining": display_duration,
	}
	powerup_started.emit(powerup_id, display_duration)


func get_active_powerups() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for key_variant in active_powerups.keys():
		var key: String = str(key_variant)
		var entry: Dictionary = active_powerups[key]
		var duration: float = float(entry.get("duration", 1.0))
		var remaining: float = float(entry.get("remaining", 0.0))
		list.append({
			"id": key,
			"duration": duration,
			"remaining": remaining,
			"ratio": clampf(remaining / maxf(duration, 0.001), 0.0, 1.0),
		})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("remaining", 0.0)) > float(b.get("remaining", 0.0))
	)
	return list


func _tick_powerups(delta: float) -> void:
	if active_powerups.is_empty():
		return

	var ended: Array[String] = []
	for key_variant in active_powerups.keys():
		var key: String = str(key_variant)
		var entry: Dictionary = active_powerups[key]
		var duration: float = float(entry.get("duration", 1.0))
		var remaining: float = maxf(float(entry.get("remaining", 0.0)) - delta, 0.0)
		entry["remaining"] = remaining
		active_powerups[key] = entry
		powerup_updated.emit(key, remaining, duration)
		if remaining <= 0.0:
			ended.append(key)

	for key in ended:
		active_powerups.erase(key)
		powerup_ended.emit(key)


func _on_car_destroyed() -> void:
	is_alive = false
	_set_emp_fx(false)
	car_destroyed.emit(self )


func _on_fuel_empty() -> void:
	is_alive = false
	_set_emp_fx(false)
	car_stalled.emit(self )


func _cache_emp_meshes() -> void:
	var mesh_nodes: Array[Node] = find_children("*", "MeshInstance3D", true, false)
	for node in mesh_nodes:
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh == null:
			continue
		_emp_meshes.append(mesh)
		_emp_original_overlays[mesh] = mesh.material_overlay


func _set_emp_fx(enabled: bool) -> void:
	if enabled == _emp_fx_active:
		return
	_emp_fx_active = enabled

	for mesh in _emp_meshes:
		if not is_instance_valid(mesh):
			continue
		if enabled:
			var mat: ShaderMaterial = ShaderMaterial.new()
			mat.shader = EMP_LIGHTNING_SHADER
			var seed_value: float = float(mesh.get_instance_id() % 997) / 997.0
			mat.set_shader_parameter("seed", Vector2(seed_value, 1.0 - seed_value))
			mat.set_shader_parameter("speed", emp_fx_speed)
			mat.set_shader_parameter("random_scale", emp_fx_random_scale)
			mat.set_shader_parameter("intensity", emp_fx_intensity)
			mesh.material_overlay = mat
		else:
			mesh.material_overlay = _emp_original_overlays.get(mesh, null)


func _on_body_entered(body: Node) -> void:
	if not is_player:
		return
	if _collision_signal_cooldown > 0.0:
		return

	var other_velocity: Vector3 = Vector3.ZERO
	if body is RigidBody3D:
		other_velocity = (body as RigidBody3D).linear_velocity
	elif body is CharacterBody3D:
		other_velocity = (body as CharacterBody3D).velocity
	elif body is VehicleBody3D:
		other_velocity = (body as VehicleBody3D).linear_velocity

	var relative_speed: float = (linear_velocity - other_velocity).length()
	if relative_speed < 2.5:
		return

	_collision_signal_cooldown = 0.08
	collision_impact.emit(relative_speed)


func _weapon_recoil_intensity(weapon: WeaponBase) -> float:
	if weapon == null:
		return 0.8
	var recoil: float = absf(weapon.recoil_impulse) * maxf(weapon.recoil_linear_scale, 0.1)
	return clampf(recoil / 450.0, 0.35, 2.0)


func take_hit(amount: float, hit_position: Vector3, attacker: Node) -> void:
	if not is_alive or damage_system == null:
		return
	if amount <= 0.0:
		return

	var zone: CarDamageSystem.DamageZone = _resolve_hit_zone(hit_position)
	damage_system.take_damage(zone, amount, attacker)


func register_damage_attacker(attacker: Node) -> void:
	if attacker == null:
		return
	if not is_instance_valid(attacker):
		return
	if not (attacker is Car):
		return
	var attacker_car: Car = attacker as Car
	if attacker_car == self:
		return
	var attacker_session_id: String = attacker_car.network_id
	if attacker_session_id == "" and NakamaManager.current_match and attacker_car.uses_player_input:
		attacker_session_id = NakamaManager.current_match.self_user.session_id
	_store_attacker_info(attacker_session_id, attacker_car.name)


func register_damage_attacker_info(attacker_session_id: String, attacker_name: String = "") -> void:
	if attacker_session_id == "" and attacker_name == "":
		return
	if attacker_session_id != "" and network_id != "" and attacker_session_id == network_id:
		return
	if attacker_session_id == "" and attacker_name == name:
		return
	_store_attacker_info(attacker_session_id, attacker_name)


func get_recent_attacker_info(max_age_ms: int = KILL_CREDIT_WINDOW_MS) -> Dictionary:
	if _last_attacker_timestamp_ms <= 0:
		return {}
	var age_ms: int = Time.get_ticks_msec() - _last_attacker_timestamp_ms
	if age_ms > max_age_ms:
		return {}
	return {
		"session_id": _last_attacker_session_id,
		"name": _last_attacker_name,
		"age_ms": age_ms,
	}


func clear_recent_attacker() -> void:
	_last_attacker_session_id = ""
	_last_attacker_name = ""
	_last_attacker_timestamp_ms = 0


func _store_attacker_info(attacker_session_id: String, attacker_name: String) -> void:
	_last_attacker_session_id = attacker_session_id
	_last_attacker_name = attacker_name
	_last_attacker_timestamp_ms = Time.get_ticks_msec()


func _resolve_hit_zone(hit_position: Vector3) -> CarDamageSystem.DamageZone:
	var wheel_nodes: Array[Node3D] = [front_left_wheel, front_right_wheel, rear_left_wheel, rear_right_wheel]
	var wheel_zones: Array[CarDamageSystem.DamageZone] = [
		CarDamageSystem.DamageZone.WHEEL_FL,
		CarDamageSystem.DamageZone.WHEEL_FR,
		CarDamageSystem.DamageZone.WHEEL_RL,
		CarDamageSystem.DamageZone.WHEEL_RR,
	]

	for i in range(wheel_nodes.size()):
		var wheel: Node3D = wheel_nodes[i]
		if wheel and hit_position.distance_to(wheel.global_position) <= wheel_hit_radius:
			return wheel_zones[i]

	if weapon_mount_primary and hit_position.distance_to(weapon_mount_primary.global_position) <= weapon_mount_hit_radius:
		return CarDamageSystem.DamageZone.WEAPON_MOUNT
	if weapon_mount_secondary and hit_position.distance_to(weapon_mount_secondary.global_position) <= weapon_mount_hit_radius:
		return CarDamageSystem.DamageZone.WEAPON_MOUNT

	var front_center: Vector3 = (front_left_wheel.global_position + front_right_wheel.global_position) * 0.5
	var rear_center: Vector3 = (rear_left_wheel.global_position + rear_right_wheel.global_position) * 0.5
	var front_dir: Vector3 = (front_center - rear_center).normalized()
	if front_dir.length_squared() < 0.001:
		return CarDamageSystem.DamageZone.CHASSIS

	var wheelbase: float = front_center.distance_to(rear_center)
	var longitudinal: float = (hit_position - global_position).dot(front_dir)
	if longitudinal > wheelbase * engine_hit_front_ratio:
		return CarDamageSystem.DamageZone.ENGINE

	return CarDamageSystem.DamageZone.CHASSIS
