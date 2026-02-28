extends Node
class_name CarDamageSystem

## Four-zone damage model: engine, chassis, wheels (×4), weapon mount.

signal zone_damaged(zone: String, current_hp: float, max_hp: float)
signal car_destroyed()

enum DamageZone {ENGINE, CHASSIS, WHEEL_FL, WHEEL_FR, WHEEL_RL, WHEEL_RR, WEAPON_MOUNT}

@export var max_engine_hp: float = 100.0
@export var max_chassis_hp: float = 100.0
@export var max_wheel_hp: float = 50.0
@export var max_weapon_hp: float = 60.0

var engine_hp: float = 100.0
var chassis_hp: float = 100.0
var wheel_hp: Array[float] = [50.0, 50.0, 50.0, 50.0] # FL, FR, RL, RR
var weapon_mount_hp: float = 60.0


func take_damage(zone: DamageZone, amount: float) -> void:
	if NakamaManager.current_match:
		var car = get_parent()
		var data = {
			"target": car.network_id if car.network_id != "" else NakamaManager.current_match.self_user.session_id,
			"zone": zone,
			"amount": amount
		}
		NakamaManager.send_match_state(NakamaManager.OpCodes.DAMAGE_EVENT, JSON.stringify(data))
	
	_apply_damage_internal(zone, amount)


func _apply_damage_internal(zone: DamageZone, amount: float) -> void:
	match zone:
		DamageZone.ENGINE:
			engine_hp = maxf(engine_hp - amount, 0.0)
			zone_damaged.emit("engine", engine_hp, max_engine_hp)
		DamageZone.CHASSIS:
			chassis_hp = maxf(chassis_hp - amount, 0.0)
			zone_damaged.emit("chassis", chassis_hp, max_chassis_hp)
			if chassis_hp <= 0.0:
				car_destroyed.emit()
		DamageZone.WHEEL_FL, DamageZone.WHEEL_FR, DamageZone.WHEEL_RL, DamageZone.WHEEL_RR:
			var idx := zone - DamageZone.WHEEL_FL
			wheel_hp[idx] = maxf(wheel_hp[idx] - amount, 0.0)
			zone_damaged.emit("wheel_%d" % idx, wheel_hp[idx], max_wheel_hp)
		DamageZone.WEAPON_MOUNT:
			weapon_mount_hp = maxf(weapon_mount_hp - amount, 0.0)
			zone_damaged.emit("weapon", weapon_mount_hp, max_weapon_hp)


func take_collision_damage(impact_force: float) -> void:
	take_damage(DamageZone.CHASSIS, impact_force * 0.1)


## 1.0 = full speed, 0.3 = critical engine damage
func get_speed_modifier() -> float:
	return lerpf(0.3, 1.0, engine_hp / max_engine_hp)


## 1.0 = normal drain, 3.0 = worst leak
func get_fuel_drain_modifier() -> float:
	return lerpf(3.0, 1.0, engine_hp / max_engine_hp)


## Steering pull from asymmetric wheel damage
func get_steering_bias() -> float:
	var left_dmg := (max_wheel_hp - wheel_hp[0]) + (max_wheel_hp - wheel_hp[2])
	var right_dmg := (max_wheel_hp - wheel_hp[1]) + (max_wheel_hp - wheel_hp[3])
	return (right_dmg - left_dmg) / (max_wheel_hp * 4.0) * 0.15


func repair_zone(zone: DamageZone, amount: float) -> void:
	match zone:
		DamageZone.ENGINE:
			engine_hp = minf(engine_hp + amount, max_engine_hp)
		DamageZone.CHASSIS:
			chassis_hp = minf(chassis_hp + amount, max_chassis_hp)
		DamageZone.WEAPON_MOUNT:
			weapon_mount_hp = minf(weapon_mount_hp + amount, max_weapon_hp)


## Returns the zone with the lowest HP ratio
func get_worst_zone() -> DamageZone:
	var worst := DamageZone.CHASSIS
	var worst_ratio := chassis_hp / max_chassis_hp

	var er := engine_hp / max_engine_hp
	if er < worst_ratio:
		worst = DamageZone.ENGINE
		worst_ratio = er

	for i in range(4):
		var wr := wheel_hp[i] / max_wheel_hp
		if wr < worst_ratio:
			worst = (DamageZone.WHEEL_FL + i) as DamageZone
			worst_ratio = wr

	if weapon_mount_hp / max_weapon_hp < worst_ratio:
		worst = DamageZone.WEAPON_MOUNT

	return worst


func get_zone_health(zone: String) -> Dictionary:
	match zone:
		"engine":
			return {"current": engine_hp, "max": max_engine_hp}
		"chassis":
			return {"current": chassis_hp, "max": max_chassis_hp}
		"weapon":
			return {"current": weapon_mount_hp, "max": max_weapon_hp}
		"wheel_0", "wheel_1", "wheel_2", "wheel_3":
			var idx: int = int(zone.trim_prefix("wheel_"))
			if idx >= 0 and idx < wheel_hp.size():
				return {"current": wheel_hp[idx], "max": max_wheel_hp}
	return {"current": 0.0, "max": 1.0}
