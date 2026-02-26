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
	_do_fire()


## Override in subclasses — spawn projectile, raycast, etc.
func _do_fire() -> void:
	pass


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
