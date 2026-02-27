extends Node

## Car Particle System — orchestrates tire smoke, drift smoke, collision sparks,
## and explosion effects on a vehicle. Add as a child of a Car (VehicleBody3D).

@export_group("Scenes")
@export var tire_smoke_scene: PackedScene
@export var drift_smoke_scene: PackedScene
@export var collision_sparks_scene: PackedScene
@export var explosion_scene: PackedScene

@export_group("Tire Smoke")
@export var enable_tire_smoke: bool = true
@export var tire_smoke_speed_threshold: float = 6.0 ## km/h

@export_group("Drift Smoke")
@export var enable_drift_smoke: bool = true

@export_group("Collision Sparks")
@export var enable_collision_sparks: bool = true
@export var weapon_fire_particles_scene: PackedScene = preload("res://scenes/particles/WeaponFire.tscn")
@export var spark_damage_threshold: float = 5.0 ## minimum damage to trigger sparks
@export var spark_contact_cooldown: float = 0.12
@export var spark_min_vehicle_speed_kmh: float = 8.0
@export var spark_scrape_height_offset: float = 0.01
@export var spark_directional_up_bias: float = 0.25
@export var spark_directional_outward_bias: float = 0.35
@export var weapon_fire_particle_scale: float = 0.7
@export var damage_hit_particle_scale: float = 1.0

@export_group("Explosions")
@export var enable_explosions: bool = true
@export var death_explosion_scale: float = 1.2

# Tire smoke instances (one per wheel)
var _tire_smokes: Array[GPUParticles3D] = []
var _tire_smoke_wheels: Array[VehicleWheel3D] = []
# Drift smoke instances (rear wheels only)
var _drift_smokes: Array[GPUParticles3D] = []
var _drift_smoke_wheels: Array[VehicleWheel3D] = []
# Reusable collision sparks
var _sparks: GPUParticles3D = null
var _last_contact_spark_time_ms: int = -1000000

@onready var car: Car = get_parent()


func _ready() -> void:
	# Wait one frame so all sibling nodes are ready
	await get_tree().process_frame
	_spawn_tire_smoke()
	_spawn_drift_smoke()
	_spawn_collision_sparks()
	_connect_signals()


func _spawn_tire_smoke() -> void:
	if not tire_smoke_scene or not enable_tire_smoke:
		return
	var wheels: Array[VehicleWheel3D] = [
		car.front_left_wheel, car.front_right_wheel,
		car.rear_left_wheel, car.rear_right_wheel
	]
	for wheel in wheels:
		var smoke: GPUParticles3D = tire_smoke_scene.instantiate()
		wheel.add_child(smoke)
		smoke.position = Vector3(0, -0.1, 0) # slightly below wheel center
		_tire_smokes.append(smoke)
		_tire_smoke_wheels.append(wheel)


func _spawn_drift_smoke() -> void:
	if not drift_smoke_scene or not enable_drift_smoke:
		return
	var rear_wheels: Array[VehicleWheel3D] = [car.rear_left_wheel, car.rear_right_wheel]
	for wheel in rear_wheels:
		var smoke: GPUParticles3D = drift_smoke_scene.instantiate()
		wheel.add_child(smoke)
		smoke.position = Vector3(0, -0.1, 0)
		_drift_smokes.append(smoke)
		_drift_smoke_wheels.append(wheel)


func _spawn_collision_sparks() -> void:
	if not collision_sparks_scene or not enable_collision_sparks:
		return
	_sparks = collision_sparks_scene.instantiate()
	_sparks.auto_free = false # reusable, don't auto-free
	car.add_child(_sparks)


func _connect_signals() -> void:
	# Drift signals
	if car.drift_system and enable_drift_smoke:
		car.drift_system.drift_started.connect(_on_drift_started)
		car.drift_system.drift_ended.connect(_on_drift_ended)

	# Damage signals for sparks
	if car.damage_system and enable_collision_sparks:
		car.damage_system.zone_damaged.connect(_on_zone_damaged)

	# Collision signals for sparks (includes static world bodies like walls)
	if enable_collision_sparks:
		car.contact_monitor = true
		if car.max_contacts_reported < 8:
			car.max_contacts_reported = 8
		car.body_entered.connect(_on_body_entered)
		if car.has_signal("weapon_fired"):
			car.weapon_fired.connect(_on_weapon_fired)

	# Death signals for explosion
	if enable_explosions:
		car.car_destroyed.connect(_on_car_destroyed)
		car.car_stalled.connect(_on_car_stalled)


func _physics_process(delta: float) -> void:
	if not car or not car.is_alive:
		_set_tire_smoke(false)
		_set_scrape_sparks(false)
		return
	_update_tire_smoke()
	_update_drift_smoke(delta)
	_update_scrape_sparks()


func _update_tire_smoke() -> void:
	if not enable_tire_smoke or _tire_smokes.is_empty():
		return
	var dominated_by_drift: bool = car.drift_system and car.drift_system.is_drifting
	# Show tire smoke when driving above threshold, but not during drift
	# (drift smoke takes over for rear wheels)
	var moving_fast: bool = car.current_speed_kmh > tire_smoke_speed_threshold
	for i in range(_tire_smokes.size()):
		var smoke: GPUParticles3D = _tire_smokes[i]
		if not is_instance_valid(smoke):
			continue
		var wheel: VehicleWheel3D = _tire_smoke_wheels[i]
		var grounded: bool = _wheel_is_grounded(wheel)
		smoke.emitting = moving_fast and not dominated_by_drift and grounded


func _set_tire_smoke(enabled: bool) -> void:
	for smoke in _tire_smokes:
		if is_instance_valid(smoke):
			smoke.emitting = enabled


func _update_drift_smoke(_delta: float) -> void:
	if not enable_drift_smoke or _drift_smokes.is_empty():
		return
	var drifting: bool = car.drift_system and car.drift_system.is_drifting
	# Scale drift intensity by lateral velocity
	var lateral: float = absf(car.get_lateral_speed())
	var intensity: float = clampf(lateral / 10.0, 0.2, 1.0)
	for i in range(_drift_smokes.size()):
		var smoke: GPUParticles3D = _drift_smokes[i]
		if not is_instance_valid(smoke):
			continue
		var wheel: VehicleWheel3D = _drift_smoke_wheels[i]
		var grounded: bool = _wheel_is_grounded(wheel)
		smoke.emitting = drifting and grounded
		if smoke.emitting and smoke.has_method("set_intensity"):
			smoke.set_intensity(intensity)


func _on_drift_started() -> void:
	for smoke in _drift_smokes:
		if is_instance_valid(smoke):
			smoke.emitting = true


func _on_drift_ended(_duration: float, _boost_earned: float) -> void:
	for smoke in _drift_smokes:
		if is_instance_valid(smoke):
			smoke.emitting = false


func _update_scrape_sparks() -> void:
	if not enable_collision_sparks or not is_instance_valid(_sparks):
		return
	if car.current_speed_kmh < spark_min_vehicle_speed_kmh:
		_set_scrape_sparks(false)
		return

	var contact_count: int = car.get_contact_count()
	if contact_count <= 0:
		_set_scrape_sparks(false)
		return

	var contact_data: Dictionary = _get_best_contact_data()
	var contact_pos: Vector3 = contact_data["position"]
	var trail_dir: Vector3 = contact_data["trail_direction"]
	var speed: float = contact_data["relative_speed"]
	_set_scrape_sparks(true, contact_pos, trail_dir, speed)


func _on_zone_damaged(_zone: String, current_hp: float, max_hp: float) -> void:
	if not enable_collision_sparks or not _sparks:
		return
	var damage_taken: float = max_hp - current_hp
	if damage_taken < spark_damage_threshold:
		return
	_spawn_one_shot_sparks(car.global_position + Vector3(0, 0.5, 0), damage_hit_particle_scale)


func _on_body_entered(_body: Node) -> void:
	if not enable_collision_sparks or not is_instance_valid(_sparks):
		return
	if car.current_speed_kmh < spark_min_vehicle_speed_kmh:
		return
	var now_ms: int = Time.get_ticks_msec()
	var cooldown_ms: int = int(spark_contact_cooldown * 1000.0)
	if now_ms - _last_contact_spark_time_ms < cooldown_ms:
		return
	_last_contact_spark_time_ms = now_ms
	var contact_pos: Vector3 = car.global_position + Vector3(0, 0.4, 0)
	if car.get_contact_count() > 0:
		var contact_data: Dictionary = _get_best_contact_data()
		contact_pos = contact_data["position"]
	_sparks.emit_at(contact_pos)


func _on_weapon_fired(_mount_slot: int = 0, intensity: float = 1.0) -> void:
	if not enable_collision_sparks:
		return
	var forward: Vector3 = car.global_basis.z.normalized()
	var pos: Vector3 = car.global_position + forward * 2.1 + Vector3.UP * 0.55
	_spawn_weapon_fire_particles(pos, forward, weapon_fire_particle_scale * maxf(intensity, 0.3))


func _spawn_weapon_fire_particles(pos: Vector3, forward: Vector3, scale_factor: float = 1.0) -> void:
	if not weapon_fire_particles_scene:
		return
	var fx: GPUParticles3D = weapon_fire_particles_scene.instantiate()
	get_tree().current_scene.add_child(fx)
	fx.scale = Vector3.ONE * maxf(scale_factor, 0.25)
	if fx.has_method("set"):
		fx.set("auto_free", true)
	if fx.has_method("emit_at"):
		fx.emit_at(pos, forward)


func _spawn_one_shot_sparks(pos: Vector3, scale_factor: float = 1.0) -> void:
	if not collision_sparks_scene:
		return
	var sparks: GPUParticles3D = collision_sparks_scene.instantiate()
	get_tree().current_scene.add_child(sparks)
	if sparks.has_method("set"):
		sparks.set("auto_free", true)
	if sparks.has_method("emit_at"):
		sparks.emit_at(pos)
	var scaled: Vector3 = Vector3.ONE * maxf(scale_factor, 0.25)
	sparks.scale = scaled


func _get_best_contact_data() -> Dictionary:
	var fallback_pos: Vector3 = car.global_position + car.global_basis.y * 0.4
	if car.get_contact_count() <= 0 or not car.has_method("get_contact_local_position"):
		return {
			"position": fallback_pos,
			"trail_direction": - car.linear_velocity.normalized() if car.linear_velocity.length() > 0.01 else -car.global_basis.z,
			"relative_speed": car.linear_velocity.length()
		}

	var best: Dictionary = {
		"position": fallback_pos,
		"trail_direction": - car.global_basis.z,
		"relative_speed": 0.0
	}
	var best_score: float = -1.0
	var count: int = car.get_contact_count()
	for i in range(count):
		var local_pos: Vector3 = car.get_contact_local_position(i)
		var world_pos: Vector3 = car.to_global(local_pos) + car.global_basis.y * spark_scrape_height_offset

		var local_normal: Vector3 = Vector3.UP
		if car.has_method("get_contact_local_normal"):
			local_normal = car.get_contact_local_normal(i)
		var world_normal: Vector3 = (car.global_basis * local_normal).normalized()

		var collider_velocity: Vector3 = Vector3.ZERO
		if car.has_method("get_contact_collider_object"):
			var collider_obj: Variant = car.get_contact_collider_object(i)
			if collider_obj is Node:
				collider_velocity = _get_body_linear_velocity(collider_obj as Node)

		var relative_velocity: Vector3 = car.linear_velocity - collider_velocity
		var tangential_velocity: Vector3 = relative_velocity - world_normal * relative_velocity.dot(world_normal)
		var tangential_speed: float = tangential_velocity.length()

		var base_trail: Vector3 = - tangential_velocity.normalized() if tangential_speed > 0.1 else -car.linear_velocity.normalized()
		if base_trail.length() < 0.01:
			base_trail = - car.global_basis.z

		var directional: Vector3 = (
			base_trail
			+ car.global_basis.y * spark_directional_up_bias
			+ world_normal * spark_directional_outward_bias
		).normalized()

		if tangential_speed > best_score:
			best_score = tangential_speed
			best = {
				"position": world_pos,
				"trail_direction": directional,
				"relative_speed": tangential_speed
			}

	return best


func _get_body_linear_velocity(body: Node) -> Vector3:
	var lv: Variant = body.get("linear_velocity")
	if lv is Vector3:
		return lv as Vector3
	var v: Variant = body.get("velocity")
	if v is Vector3:
		return v as Vector3
	return Vector3.ZERO


func _set_scrape_sparks(active: bool, pos: Vector3 = Vector3.ZERO, trail_dir: Vector3 = Vector3.BACK, relative_speed: float = 0.0) -> void:
	if not is_instance_valid(_sparks):
		return
	if _sparks.has_method("set_scrape_motion"):
		_sparks.set_scrape_motion(trail_dir, relative_speed)
	if _sparks.has_method("set_scrape_active"):
		_sparks.set_scrape_active(active, pos)


func _wheel_is_grounded(wheel: VehicleWheel3D) -> bool:
	if not is_instance_valid(wheel):
		return false
	if wheel.has_method("is_in_contact"):
		return wheel.is_in_contact()
	var in_contact: Variant = wheel.get("is_in_contact")
	if in_contact is bool:
		return in_contact as bool
	return false


func _on_car_destroyed(_destroyed_car: Car) -> void:
	_spawn_death_explosion()


func _on_car_stalled(_stalled_car: Car) -> void:
	_spawn_death_explosion()


func _spawn_death_explosion() -> void:
	if not explosion_scene or not enable_explosions:
		return
	var explosion: Node3D = explosion_scene.instantiate()
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = car.global_position + Vector3(0, 0.5, 0)
	if explosion.has_method("set_scale_factor"):
		explosion.set_scale_factor(death_explosion_scale)
	if explosion.has_method("explode"):
		explosion.explode()
