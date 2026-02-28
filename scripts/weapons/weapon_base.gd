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


func _ready() -> void:
	if max_ammo > 0:
		ammo = max_ammo


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


func can_fire() -> bool:
	if is_overheated or is_reloading:
		return false
	if _fire_timer > 0.0:
		return false
	if max_ammo > 0 and ammo <= 0:
		return false
	return true


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
	
	if owner_car and owner_car.is_player and NakamaManager.current_match:
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

	var anchor: Node3D = owner_car if owner_car is Node3D else self
	if anchor == null:
		return

	var fx: Node3D = fire_particles_scene.instantiate()
	get_tree().current_scene.add_child(fx)

	var forward: Vector3 = anchor.global_basis.z.normalized()
	fx.global_position = anchor.global_position + forward * fire_particles_forward_offset + Vector3.UP * fire_particles_up_offset

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
