extends Node
class_name BotDriver

## Minimal bot AI: random wandering movement + fires when target is in front and visible.

@export var steering_change_interval_min: float = 0.7
@export var steering_change_interval_max: float = 1.8
@export var throttle: float = 0.65
@export var max_brake_force_ratio: float = 0.35
@export var obstacle_probe_distance: float = 8.0
@export var obstacle_probe_side_angle_deg: float = 28.0
@export var obstacle_collision_mask: int = 0xFFFFFFFF
@export var stuck_speed_threshold_kmh: float = 2.5
@export var stuck_time_before_recover: float = 1.2
@export var recover_reverse_time_min: float = 0.55
@export var recover_reverse_time_max: float = 1.2
@export var recover_throttle_ratio: float = 0.7
@export var weapon_sight_range: float = 360.0
@export var shoot_cone_dot: float = 0.7
@export var sight_collision_mask: int = 0xFFFFFFFF

@onready var car: Car = get_parent() as Car

var _steer_target: float = 0.0
var _steer_timer: float = 0.0
var _stuck_timer: float = 0.0
var _is_recovering: bool = false
var _recover_timer: float = 0.0
var _recover_steer_sign: float = 1.0


func _ready() -> void:
	if car == null:
		set_physics_process(false)
		return
	_pick_next_steer()


func _physics_process(delta: float) -> void:
	if car == null or not car.is_alive or car.is_emp_disabled:
		return

	if _is_recovering:
		_run_recovery(delta)
		_try_fire_weapons()
		return

	_steer_timer -= delta
	if _steer_timer <= 0.0:
		_pick_next_steer()

	var avoid_steer: float = _compute_obstacle_avoidance()
	if absf(avoid_steer) > 0.001:
		_steer_target = avoid_steer
		_steer_timer = randf_range(0.25, 0.5)

	var target_steer: float = _steer_target * car.max_steer_angle
	car.steering = move_toward(car.steering, target_steer, car.steer_speed * delta)

	var speed_mod: float = 1.0
	if car.damage_system:
		speed_mod = car.damage_system.get_speed_modifier()
	var speed_limit: float = car.max_speed_kmh * speed_mod * 0.85

	if car.current_speed_kmh < speed_limit:
		car.engine_force = car.max_engine_force * throttle
		car.brake = 0.0
	else:
		car.engine_force = 0.0
		car.brake = car.max_brake_force * max_brake_force_ratio

	_update_stuck_state(delta, absf(avoid_steer) > 0.001)

	_try_fire_weapons()


func _pick_next_steer() -> void:
	_steer_target = randf_range(-1.0, 1.0)
	_steer_timer = randf_range(steering_change_interval_min, steering_change_interval_max)


func _try_fire_weapons() -> void:
	var target: Node3D = _find_target_in_front()
	if target == null:
		return

	if car.primary_weapon and car.primary_weapon.can_fire():
		car.primary_weapon.fire()
	if car.secondary_weapon and car.secondary_weapon.can_fire() and randf() < 0.25:
		car.secondary_weapon.fire()


func _find_target_in_front() -> Node3D:
	var origin: Vector3 = car.global_position + Vector3.UP * 0.8
	var forward: Vector3 = car.global_basis.z.normalized()
	var best_target: Node3D = null
	var best_dot: float = shoot_cone_dot

	for node in get_tree().get_nodes_in_group("cars"):
		if node == car:
			continue
		if not (node is Car):
			continue
		var other: Car = node as Car
		if not other.is_alive:
			continue
		if other.is_bot:
			continue

		var to_target: Vector3 = other.global_position - origin
		var dist: float = to_target.length()
		if dist > weapon_sight_range or dist <= 0.001:
			continue

		var dir: Vector3 = to_target / dist
		var facing: float = forward.dot(dir)
		if facing < best_dot:
			continue

		if not _has_line_of_sight(origin, other.global_position + Vector3.UP * 0.6):
			continue

		best_dot = facing
		best_target = other

	return best_target


func _has_line_of_sight(from_pos: Vector3, to_pos: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.exclude = [car.get_rid()]
	query.collision_mask = sight_collision_mask
	var hit: Dictionary = car.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	var collider: Variant = hit.get("collider")
	return collider != null and collider is Car and not (collider as Car).is_bot


func _compute_obstacle_avoidance() -> float:
	var origin: Vector3 = car.global_position + Vector3.UP * 0.6
	var forward: Vector3 = car.global_basis.z.normalized()
	var left_dir: Vector3 = forward.rotated(Vector3.UP, deg_to_rad(obstacle_probe_side_angle_deg)).normalized()
	var right_dir: Vector3 = forward.rotated(Vector3.UP, -deg_to_rad(obstacle_probe_side_angle_deg)).normalized()

	var center_hit: Dictionary = _probe(origin, forward, obstacle_probe_distance)
	if center_hit.is_empty():
		return 0.0

	var left_hit: Dictionary = _probe(origin, left_dir, obstacle_probe_distance)
	var right_hit: Dictionary = _probe(origin, right_dir, obstacle_probe_distance)

	var left_clear: float = obstacle_probe_distance if left_hit.is_empty() else origin.distance_to(left_hit.get("position", origin))
	var right_clear: float = obstacle_probe_distance if right_hit.is_empty() else origin.distance_to(right_hit.get("position", origin))

	if left_clear > right_clear:
		return 1.0
	if right_clear > left_clear:
		return -1.0
	return -1.0 if randf() < 0.5 else 1.0


func _probe(origin: Vector3, dir: Vector3, distance: float) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * distance)
	query.exclude = [car.get_rid()]
	query.collision_mask = obstacle_collision_mask
	return car.get_world_3d().direct_space_state.intersect_ray(query)


func _update_stuck_state(delta: float, avoiding_obstacle: bool) -> void:
	var speed_kmh: float = car.linear_velocity.length() * 3.6
	if speed_kmh <= stuck_speed_threshold_kmh and (car.engine_force > 0.0 or avoiding_obstacle):
		_stuck_timer += delta
		if _stuck_timer >= stuck_time_before_recover:
			_begin_recovery()
	else:
		_stuck_timer = maxf(_stuck_timer - delta * 1.5, 0.0)


func _begin_recovery() -> void:
	_is_recovering = true
	_stuck_timer = 0.0
	_recover_timer = randf_range(recover_reverse_time_min, recover_reverse_time_max)
	_recover_steer_sign = -1.0 if randf() < 0.5 else 1.0


func _run_recovery(delta: float) -> void:
	_recover_timer -= delta
	car.steering = move_toward(car.steering, _recover_steer_sign * car.max_steer_angle, car.steer_speed * delta * 1.5)
	car.engine_force = - car.max_engine_force * recover_throttle_ratio
	car.brake = 0.0

	if _recover_timer <= 0.0:
		_is_recovering = false
		car.brake = car.max_brake_force * max_brake_force_ratio
		_pick_next_steer()
