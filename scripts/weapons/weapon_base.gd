extends Node3D
class_name WeaponBase

## Base class for all weapons. Handles ammo, fire rate, heat/reload.

signal fired()
signal ammo_changed(current: int, max_ammo: int)
signal overheated()
signal cooled_down()
signal weapon_destroyed()

enum MountType {PRIMARY, SECONDARY}
enum ReloadType {OVERHEAT, MAGAZINE, NONE}

@export_group("Mount")
@export var mount_type: MountType = MountType.PRIMARY

@export_group("Aiming")
@export var aim_mesh_path: NodePath
@export var aim_yaw_node_path: NodePath
@export var aim_pitch_node_path: NodePath
@export var aim_enabled: bool = true
@export var aim_max_pitch_up_deg: float = 68.0
@export var aim_max_pitch_down_deg: float = 38.0
@export var aim_smoothing_speed: float = 26.0
@export var aim_yaw_offset_deg: float = 0.0
@export var aim_pitch_offset_deg: float = 0.0
@export var aim_roll_offset_deg: float = 0.0

@export_group("Stats")
@export var damage: float = 10.0
@export var fire_rate: float = 5.0 ## shots per second
@export var max_ammo: int = -1 ## -1 = infinite
@export var reload_type: ReloadType = ReloadType.NONE

@export_group("Particles")
@export var fire_particles_scene: PackedScene = preload("res://scenes/particles/WeaponFire.tscn")
@export var fire_particles_forward_offset: float = 2.2
@export var fire_particles_up_offset: float = 0.55

@export_group("Recoil")
@export var recoil_enabled: bool = true
@export var recoil_impulse: float = 20.0
@export var recoil_torque_impulse: float = 2.0
@export var recoil_direction: float = -1.0 ## -1 pushes backward, +1 pushes forward
@export var recoil_linear_scale: float = 10.0
@export var recoil_torque_scale: float = 6.0

@export_group("Heat")
@export var heat_per_shot: float = 10.0
@export var max_heat: float = 100.0
@export var cooldown_rate: float = 30.0 ## per second
@export var overheat_penalty: float = 2.0 ## seconds locked out when overheated

@export_group("Magazine")
@export var reload_time: float = 2.0

var ammo: int = -1
var heat: float = 0.0
var is_overheated: bool = false
var is_reloading: bool = false
var _fire_timer: float = 0.0
var _overheat_timer: float = 0.0
var _reload_timer: float = 0.0
var owner_car: Node = null ## set by car when equipped
var _aim_mesh: Node3D = null
var _aim_mesh_parent: Node3D = null
var _aim_local_rotation: Vector3 = Vector3.ZERO
var _aim_base_local_rotation: Vector3 = Vector3.ZERO
var _aim_yaw_node: Node3D = null
var _aim_pitch_node: Node3D = null
var _aim_yaw_base_rotation: Vector3 = Vector3.ZERO
var _aim_pitch_base_rotation: Vector3 = Vector3.ZERO
var _aim_target_yaw: float = 0.0
var _aim_target_pitch: float = 0.0
var _has_aim_target: bool = false
var _last_aim_target_world: Vector3 = Vector3.ZERO


func _ready() -> void:
	if max_ammo > 0:
		ammo = max_ammo
	_resolve_aim_mesh()


func _physics_process(delta: float) -> void:
	_fire_timer = maxf(_fire_timer - delta, 0.0)

	# Overheat cooldown
	if is_overheated:
		_overheat_timer -= delta
		if _overheat_timer <= 0.0:
			is_overheated = false
			heat = 0.0
			cooled_down.emit()
	elif heat > 0.0:
		heat = maxf(heat - cooldown_rate * delta, 0.0)

	# Magazine reload
	if is_reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			is_reloading = false
			ammo = max_ammo
			ammo_changed.emit(ammo, max_ammo)

	if _aim_yaw_node and _aim_pitch_node:
		var blend_t_split: float = clampf(aim_smoothing_speed * delta, 0.0, 1.0)
		var yaw_target: Vector3 = _aim_yaw_base_rotation + Vector3(0.0, _aim_target_yaw, 0.0)
		var pitch_target: Vector3 = _aim_pitch_base_rotation + Vector3(_aim_target_pitch, 0.0, deg_to_rad(aim_roll_offset_deg))
		_aim_yaw_node.rotation = _aim_yaw_node.rotation.lerp(yaw_target, blend_t_split)
		_aim_pitch_node.rotation = _aim_pitch_node.rotation.lerp(pitch_target, blend_t_split)
	elif _aim_mesh:
		var blend_t: float = clampf(aim_smoothing_speed * delta, 0.0, 1.0)
		_aim_mesh.rotation = _aim_mesh.rotation.lerp(_aim_local_rotation, blend_t)


func can_fire() -> bool:
	if is_overheated or is_reloading:
		return false
	if _fire_timer > 0.0:
		return false
	if max_ammo > 0 and ammo <= 0:
		return false
	return true


func can_apply_gameplay_effects() -> bool:
	if owner_car == null:
		return false
	if not is_instance_valid(owner_car):
		return false
	if owner_car.has_method("is_authoritative_instance"):
		return bool(owner_car.is_authoritative_instance())
	return NakamaManager.current_match == null or bool(owner_car.get("is_player"))


func fire() -> void:
	if not can_fire():
		return

	_fire_timer = 1.0 / fire_rate

	# Ammo
	if max_ammo > 0:
		ammo -= 1
		ammo_changed.emit(ammo, max_ammo)
		if ammo <= 0 and reload_type == ReloadType.MAGAZINE:
			start_reload()

	# Heat
	if reload_type == ReloadType.OVERHEAT:
		heat += heat_per_shot
		if heat >= max_heat:
			is_overheated = true
			_overheat_timer = overheat_penalty
			overheated.emit()

	fired.emit()
	_spawn_fire_particles()
	_apply_recoil()
	
	if NakamaManager.current_match and can_apply_gameplay_effects():
		var data = {
			"session_id": owner_car.network_id,
			"slot": mount_type
		}
		NakamaManager.send_match_state(NakamaManager.OpCodes.FIRE_WEAPON, JSON.stringify(data))
		
	_do_fire()


## Override in subclasses — spawn projectile, raycast, etc.
func _do_fire() -> void:
	pass


func _spawn_fire_particles() -> void:
	if fire_particles_scene == null:
		return

	var fx: Node3D = fire_particles_scene.instantiate()
	get_tree().current_scene.add_child(fx)

	var forward: Vector3 = get_muzzle_direction()
	fx.global_position = get_muzzle_position(fire_particles_forward_offset, fire_particles_up_offset)

	if fx.has_method("set"):
		fx.set("auto_free", true)
	if fx.has_method("emit_at"):
		fx.emit_at(fx.global_position, forward)


func _apply_recoil() -> void:
	if not recoil_enabled:
		return
	if not (owner_car is VehicleBody3D):
		return

	var car := owner_car as VehicleBody3D
	if recoil_impulse != 0.0 and car.has_method("apply_central_impulse"):
		var dir := car.global_basis.z.normalized() * recoil_direction
		var mass_factor: float = maxf(car.mass / 1200.0, 0.5)
		var linear_impulse: float = recoil_impulse * recoil_linear_scale * mass_factor
		car.apply_central_impulse(dir * linear_impulse)

	if recoil_torque_impulse != 0.0 and car.has_method("apply_torque_impulse"):
		var yaw_sign: float = -1.0 if randf() < 0.5 else 1.0
		car.apply_torque_impulse(Vector3.UP * recoil_torque_impulse * recoil_torque_scale * yaw_sign)


func start_reload() -> void:
	if reload_type != ReloadType.MAGAZINE or is_reloading:
		return
	is_reloading = true
	_reload_timer = reload_time


func refill_ammo() -> void:
	if max_ammo > 0:
		ammo = max_ammo
		ammo_changed.emit(ammo, max_ammo)


func get_heat_ratio() -> float:
	return heat / max_heat if max_heat > 0.0 else 0.0


func get_fire_cooldown_remaining() -> float:
	return maxf(_fire_timer, 0.0)


func get_fire_cooldown_duration() -> float:
	if fire_rate <= 0.0:
		return 0.0
	return 1.0 / fire_rate


func get_fire_cooldown_ratio() -> float:
	var duration: float = get_fire_cooldown_duration()
	if duration <= 0.0:
		return 0.0
	return clampf(_fire_timer / duration, 0.0, 1.0)


func get_muzzle_direction() -> Vector3:
	if _has_aim_target:
		var anchor_pos: Vector3 = _get_muzzle_anchor_position()
		var to_target: Vector3 = _last_aim_target_world - anchor_pos
		if to_target.length_squared() > 0.0001:
			return to_target.normalized()

	if _aim_pitch_node and is_instance_valid(_aim_pitch_node):
		return _aim_pitch_node.global_basis.z.normalized()
	if _aim_mesh and is_instance_valid(_aim_mesh):
		return _aim_mesh.global_basis.z.normalized()
	if self is Node3D:
		return global_basis.z.normalized()
	if owner_car is Node3D:
		return (owner_car as Node3D).global_basis.z.normalized()
	return Vector3.FORWARD


func get_muzzle_position(forward_offset: float = 0.0, up_offset: float = 0.0) -> Vector3:
	var anchor_pos: Vector3 = _get_muzzle_anchor_position()
	return anchor_pos + get_muzzle_direction() * forward_offset + Vector3.UP * up_offset


func update_aim_target(world_target: Vector3) -> void:
	if not aim_enabled:
		return
	_has_aim_target = true
	_last_aim_target_world = world_target

	if _aim_yaw_node and _aim_pitch_node:
		var to_target: Vector3 = world_target - _aim_pitch_node.global_position
		if to_target.length_squared() <= 0.0001:
			return

		# Yaw from yaw node parent space: base rotates only around Y.
		var yaw_parent: Node3D = _aim_yaw_node.get_parent_node_3d()
		if yaw_parent:
			var local_yaw_dir: Vector3 = yaw_parent.global_basis.inverse() * to_target.normalized()
			var split_yaw: float = atan2(local_yaw_dir.x, local_yaw_dir.z)
			_aim_target_yaw = split_yaw + deg_to_rad(aim_yaw_offset_deg)

		# Pitch from pitch node parent space: barrel rotates only around X.
		var pitch_parent: Node3D = _aim_pitch_node.get_parent_node_3d()
		if pitch_parent:
			var local_pitch_dir: Vector3 = pitch_parent.global_basis.inverse() * to_target.normalized()
			var split_horizontal_len: float = Vector2(local_pitch_dir.x, local_pitch_dir.z).length()
			var split_pitch: float = atan2(-local_pitch_dir.y, maxf(split_horizontal_len, 0.0001))
			split_pitch = clampf(split_pitch, deg_to_rad(-aim_max_pitch_up_deg), deg_to_rad(aim_max_pitch_down_deg))
			_aim_target_pitch = split_pitch + deg_to_rad(aim_pitch_offset_deg)
		return

	if _aim_mesh == null or _aim_mesh_parent == null:
		_resolve_aim_mesh()
	if _aim_mesh == null or _aim_mesh_parent == null:
		return

	var to_target_world: Vector3 = world_target - _aim_mesh.global_position
	if to_target_world.length_squared() <= 0.0001:
		return

	var local_dir: Vector3 = _aim_mesh_parent.global_basis.inverse() * to_target_world.normalized()
	var yaw: float = atan2(local_dir.x, local_dir.z)
	var horizontal_len: float = Vector2(local_dir.x, local_dir.z).length()
	var pitch: float = atan2(-local_dir.y, maxf(horizontal_len, 0.0001))
	pitch = clampf(pitch, deg_to_rad(-aim_max_pitch_up_deg), deg_to_rad(aim_max_pitch_down_deg))

	var aim_delta: Vector3 = Vector3(
		pitch + deg_to_rad(aim_pitch_offset_deg),
		yaw + deg_to_rad(aim_yaw_offset_deg),
		deg_to_rad(aim_roll_offset_deg)
	)
	_aim_local_rotation = _aim_base_local_rotation + aim_delta


func _resolve_aim_mesh() -> void:
	_aim_yaw_node = null
	_aim_pitch_node = null

	if aim_yaw_node_path != NodePath("") and aim_pitch_node_path != NodePath(""):
		_aim_yaw_node = get_node_or_null(aim_yaw_node_path) as Node3D
		_aim_pitch_node = get_node_or_null(aim_pitch_node_path) as Node3D
		if _aim_yaw_node and _aim_pitch_node:
			_aim_yaw_base_rotation = _aim_yaw_node.rotation
			_aim_pitch_base_rotation = _aim_pitch_node.rotation
			_aim_target_yaw = 0.0
			_aim_target_pitch = 0.0
			# Keep these for shared muzzle helpers.
			_aim_mesh = _aim_pitch_node
			_aim_mesh_parent = _aim_pitch_node.get_parent_node_3d()
			_aim_base_local_rotation = _aim_pitch_base_rotation
			_aim_local_rotation = _aim_pitch_base_rotation
			return

	_aim_mesh = null
	_aim_mesh_parent = null

	var mesh_candidate: Node3D = null
	if aim_mesh_path != NodePath(""):
		mesh_candidate = get_node_or_null(aim_mesh_path) as Node3D
	if mesh_candidate == null:
		mesh_candidate = _find_first_mesh_child(self )

	if mesh_candidate == null:
		return

	_aim_mesh = mesh_candidate
	_aim_mesh_parent = _aim_mesh.get_parent_node_3d()
	if _aim_mesh_parent:
		_aim_base_local_rotation = _aim_mesh.rotation
		_aim_local_rotation = _aim_mesh.rotation


func _find_first_mesh_child(root: Node) -> Node3D:
	for child in root.get_children():
		if child is MeshInstance3D:
			return child as Node3D
		var nested: Node3D = _find_first_mesh_child(child)
		if nested:
			return nested
	return null


func _get_muzzle_anchor_position() -> Vector3:
	if _aim_pitch_node and is_instance_valid(_aim_pitch_node):
		return _aim_pitch_node.global_position
	if _aim_mesh and is_instance_valid(_aim_mesh):
		return _aim_mesh.global_position
	if self is Node3D:
		return global_position
	if owner_car is Node3D:
		return (owner_car as Node3D).global_position
	return Vector3.ZERO
