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

@export_group("Damage Popup")
@export var show_damage_popup: bool = true
@export var popup_base_height: float = 2.4
@export var popup_rise_distance: float = 1.3
@export var popup_rise_time: float = 0.42
@export var popup_fade_out_time: float = 0.35
@export var popup_pixel_size: float = 0.0075
@export var popup_font_size: int = 44

var engine_hp: float = 100.0
var chassis_hp: float = 100.0
var wheel_hp: Array[float] = [50.0, 50.0, 50.0, 50.0] # FL, FR, RL, RR
var weapon_mount_hp: float = 60.0


func take_damage(zone: DamageZone, amount: float, attacker: Node = null, attacker_session_id: String = "", attacker_name: String = "", event_id: String = "") -> void:
	var attacker_identity: Dictionary = _resolve_attacker_identity(attacker)
	if attacker_session_id == "":
		attacker_session_id = str(attacker_identity.get("session_id", ""))
	if attacker_name == "":
		attacker_name = str(attacker_identity.get("name", ""))

	if NakamaManager.current_match:
		var car = get_parent() as Car
		if car == null:
			return
		if car.has_method("is_authoritative_instance") and not bool(car.is_authoritative_instance()):
			return
		if event_id == "":
			event_id = "%s:%d:%d" % [str(car.network_id), Time.get_ticks_msec(), randi()]
		var data = {
			"target": car.network_id if car.network_id != "" else NakamaManager.current_match.self_user.session_id,
			"zone": zone,
			"amount": amount,
			"event_id": event_id,
		}
		if attacker_session_id != "":
			data["attacker_session_id"] = attacker_session_id
		if attacker_name != "":
			data["attacker_name"] = attacker_name
		NakamaManager.send_match_state(NakamaManager.OpCodes.DAMAGE_EVENT, JSON.stringify(data))

	_apply_damage_internal(zone, amount, attacker, attacker_session_id, attacker_name)


func _apply_damage_internal(zone: DamageZone, amount: float, attacker: Node = null, attacker_session_id: String = "", attacker_name: String = "") -> void:
	var car = get_parent() as Car
	if car:
		if attacker:
			car.register_damage_attacker(attacker)
		elif attacker_session_id != "" or attacker_name != "":
			car.register_damage_attacker_info(attacker_session_id, attacker_name)

	if amount > 0.0:
		_show_damage_popup(amount)

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


func take_collision_damage(impact_force: float, attacker: Node = null, attacker_session_id: String = "", attacker_name: String = "") -> void:
	take_damage(DamageZone.CHASSIS, impact_force * 0.1, attacker, attacker_session_id, attacker_name)


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


func _resolve_attacker_identity(attacker: Node) -> Dictionary:
	if attacker == null:
		return {}
	if not is_instance_valid(attacker):
		return {}
	if not (attacker is Car):
		return {}
	var attacker_car: Car = attacker as Car
	var session_id: String = attacker_car.network_id
	if session_id == "" and NakamaManager.current_match and attacker_car.uses_player_input:
		session_id = NakamaManager.current_match.self_user.session_id
	return {
		"session_id": session_id,
		"name": attacker_car.name,
	}


func _show_damage_popup(amount: float) -> void:
	if not show_damage_popup:
		return
	if amount <= 0.0:
		return

	var car := get_parent() as Node3D
	if car == null:
		return
	if not is_instance_valid(car):
		return
	if car.is_queued_for_deletion():
		return
	if not car.is_inside_tree():
		return

	var tree: SceneTree = get_tree()
	if tree == null:
		return

	var host: Node = tree.current_scene
	if host == null:
		host = car
	if not host.is_inside_tree():
		return

	var popup := Label3D.new()
	popup.top_level = true
	popup.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	popup.no_depth_test = true
	popup.font_size = popup_font_size
	popup.outline_size = 10
	popup.pixel_size = popup_pixel_size
	popup.modulate = Color(1.0, 0.36, 0.2, 0.0)
	popup.outline_modulate = Color(0.05, 0.05, 0.05, 0.95)

	var dmg_text: String = "%d" % int(round(amount))
	if amount < 1.0:
		dmg_text = "%.1f" % amount
	popup.text = "-%s" % dmg_text

	if not is_instance_valid(car) or car.is_queued_for_deletion() or not car.is_inside_tree():
		return
	var start_pos := car.global_position + Vector3(randf_range(-0.35, 0.35), popup_base_height, randf_range(-0.35, 0.35))
	host.add_child(popup)
	popup.global_position = start_pos

	var tween: Tween = popup.create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(popup, "global_position", start_pos + Vector3(0.0, popup_rise_distance, 0.0), popup_rise_time + popup_fade_out_time)
	tween.parallel().tween_property(popup, "modulate:a", 1.0, popup_rise_time * 0.4)
	tween.tween_property(popup, "modulate:a", 0.0, popup_fade_out_time)
	tween.finished.connect(popup.queue_free)
