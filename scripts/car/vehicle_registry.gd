extends Node

## Autoload singleton — catalog of all driveable vehicles.

const VehicleDataScript = preload("res://scripts/car/vehicle_data.gd")

const DEFAULT_UI_STAT: float = 50.0
const UI_STAT_MIN: float = 0.0
const UI_STAT_MAX: float = 100.0

var _vehicles: Dictionary = {} # id -> VehicleData
var _ordered: Array[VehicleData] = []
var _tuning_by_id: Dictionary = {} # id -> runtime tuning dictionary


func _ready() -> void:
	_register_vehicles()


func get_all() -> Array:
	return _ordered


func get_by_id(id: String):
	if id in _vehicles:
		return _vehicles[id]
	# Fallback to first vehicle
	if _ordered.is_empty():
		return null
	return _ordered[0]


func get_random():
	if _ordered.is_empty():
		return null
	return _ordered[randi() % _ordered.size()]


func get_vehicle_index(id: String) -> int:
	for i in range(_ordered.size()):
		var data: VehicleData = _ordered[i]
		if data.id == id:
			return i
	return 0


func apply_tuning(car: Car, vehicle_id: String) -> void:
	if car == null:
		return
	var tuning: Dictionary = _get_tuning_for_id(vehicle_id)
	_apply_tuning_to_car(car, tuning)


func _register_vehicles() -> void:
	var defs := [
		# id, display_name, basename
		["ambulance", "Ambulance", "Ambulance"],
		["delivery", "Delivery Van", "Delivery"],
		["delivery_flat", "Flatbed Delivery", "DeliveryFlat"],
		["firetruck", "Fire Truck", "Firetruck"],
		["garbage_truck", "Garbage Truck", "GarbageTruck"],
		["hatchback_sports", "Sport Hatchback", "HatchbackSports"],
		["police", "Police Car", "Police"],
		["race", "Race Car", "Race"],
		["race_future", "Future Racer", "RaceFuture"],
		["sedan", "Sedan", "Sedan"],
		["sedan_sports", "Sport Sedan", "SedanSports"],
		["suv", "SUV", "Suv"],
		["suv_luxury", "Luxury SUV", "SuvLuxury"],
		["taxi", "Taxi", "Taxi"],
		["truck", "Truck", "Truck"],
		["van", "Van", "Van"],
	]

	var model_base_path := "res://assets/models/cars/"
	var scene_base_path := "res://scenes/vehicles/cars/"
	var raw_stats: Array[Dictionary] = []
	for d in defs:
		var v = VehicleDataScript.new()
		v.id = d[0]
		v.display_name = d[1]
		
		# e.g. "res://scenes/vehicles/cars/Sedan.tscn"
		v.scene_path = scene_base_path + d[2] + ".tscn"
		
		# e.g. "res://assets/models/cars/sedan.glb" (we convert Sedan -> sedan for the GLB name)
		# Some like hatchback-sports vs HatchbackSports need a proper mapping if we strictly derive it.
		# Since we know the GLB names map directly to the IDs:
		var glb_name = String(d[0]).replace("_", "-") + ".glb"
		v.preview_model_path = model_base_path + glb_name
		var speed_seed: float = _seed_for_speed(v.id)
		var armor_seed: float = _seed_for_armor(v.id)
		var weight_seed: float = _seed_for_weight(v.id)
		_tuning_by_id[v.id] = _build_tuning(speed_seed, armor_seed, weight_seed)

		var stats: Dictionary = _extract_runtime_stats(v.id, v.scene_path)
		raw_stats.append(stats)
		
		_vehicles[v.id] = v
		_ordered.append(v)

	_apply_ui_stats(raw_stats)


func _extract_runtime_stats(vehicle_id: String, scene_path: String) -> Dictionary:
	var stats := {
		"speed": 0.0,
		"armor": 0.0,
		"weight": 0.0,
	}

	var packed: PackedScene = load(scene_path)
	if not packed:
		return stats

	var root := packed.instantiate()
	if not (root is VehicleBody3D):
		if root:
			root.queue_free()
		return stats

	var car := root as VehicleBody3D
	var tuning: Dictionary = _get_tuning_for_id(vehicle_id)
	_apply_tuning_to_car(car, tuning)

	var max_speed: float = _float_or(car.get("max_speed_kmh"), 0.0)
	var max_engine_force: float = _float_or(car.get("max_engine_force"), 0.0)
	var boost_mult: float = _float_or(car.get("boost_force_multiplier"), 1.0)
	var avg_wheel_radius: float = _average_wheel_radius(car)
	stats["speed"] = max_speed + max_engine_force * boost_mult * avg_wheel_radius * 0.001

	var damage_node: Node = car.get_node_or_null("DamageSystem")
	if damage_node:
		var max_engine_hp: float = _float_or(damage_node.get("max_engine_hp"), 0.0)
		var max_chassis_hp: float = _float_or(damage_node.get("max_chassis_hp"), 0.0)
		var max_wheel_hp: float = _float_or(damage_node.get("max_wheel_hp"), 0.0)
		var max_weapon_hp: float = _float_or(damage_node.get("max_weapon_hp"), 0.0)
		stats["armor"] = max_engine_hp + max_chassis_hp + (max_wheel_hp * 4.0) + max_weapon_hp

	var shape_volume: float = _sum_collision_box_volume(car)
	var mass: float = car.mass
	stats["weight"] = mass * maxf(shape_volume, 0.001)

	car.queue_free()
	return stats


func _apply_tuning_to_car(car: VehicleBody3D, tuning: Dictionary) -> void:
	if car == null:
		return

	car.mass = _float_or(tuning.get("mass"), car.mass)
	car.set("max_speed_kmh", _float_or(tuning.get("max_speed_kmh"), _float_or(car.get("max_speed_kmh"), 120.0)))
	car.set("max_engine_force", _float_or(tuning.get("max_engine_force"), _float_or(car.get("max_engine_force"), 4000.0)))
	car.set("max_brake_force", _float_or(tuning.get("max_brake_force"), _float_or(car.get("max_brake_force"), 200.0)))
	car.set("reverse_force_ratio", _float_or(tuning.get("reverse_force_ratio"), _float_or(car.get("reverse_force_ratio"), 0.6)))
	car.set("max_steer_angle", _float_or(tuning.get("max_steer_angle"), _float_or(car.get("max_steer_angle"), 0.4)))
	car.set("steer_speed", _float_or(tuning.get("steer_speed"), _float_or(car.get("steer_speed"), 3.0)))
	car.set("steer_return_speed", _float_or(tuning.get("steer_return_speed"), _float_or(car.get("steer_return_speed"), 5.0)))
	car.set("boost_force_multiplier", _float_or(tuning.get("boost_force_multiplier"), _float_or(car.get("boost_force_multiplier"), 2.0)))

	var damage_node: Node = car.get_node_or_null("DamageSystem")
	if damage_node:
		damage_node.set("max_engine_hp", _float_or(tuning.get("max_engine_hp"), _float_or(damage_node.get("max_engine_hp"), 100.0)))
		damage_node.set("max_chassis_hp", _float_or(tuning.get("max_chassis_hp"), _float_or(damage_node.get("max_chassis_hp"), 100.0)))
		damage_node.set("max_wheel_hp", _float_or(tuning.get("max_wheel_hp"), _float_or(damage_node.get("max_wheel_hp"), 50.0)))
		damage_node.set("max_weapon_hp", _float_or(tuning.get("max_weapon_hp"), _float_or(damage_node.get("max_weapon_hp"), 60.0)))
		damage_node.set("engine_hp", _float_or(damage_node.get("max_engine_hp"), 100.0))
		damage_node.set("chassis_hp", _float_or(damage_node.get("max_chassis_hp"), 100.0))
		damage_node.set("weapon_mount_hp", _float_or(damage_node.get("max_weapon_hp"), 60.0))
		var wheel_max: float = _float_or(damage_node.get("max_wheel_hp"), 50.0)
		var wheel_hp: Array[float] = [wheel_max, wheel_max, wheel_max, wheel_max]
		damage_node.set("wheel_hp", wheel_hp)


func _get_tuning_for_id(vehicle_id: String) -> Dictionary:
	if vehicle_id in _tuning_by_id:
		return _tuning_by_id[vehicle_id]
	if "sedan" in _tuning_by_id:
		return _tuning_by_id["sedan"]
	return _build_tuning(60.0, 50.0, 50.0)


func _build_tuning(speed_seed: float, armor_seed: float, weight_seed: float) -> Dictionary:
	var speed_t: float = clampf(speed_seed / 100.0, 0.0, 1.0)
	var armor_t: float = clampf(armor_seed / 100.0, 0.0, 1.0)
	var weight_t: float = clampf(weight_seed / 100.0, 0.0, 1.0)

	var max_speed_kmh: float = lerpf(95.0, 170.0, speed_t)
	var max_engine_force: float = lerpf(2800.0, 5600.0, speed_t)
	var boost_force_multiplier: float = lerpf(1.6, 2.5, speed_t)

	var mass: float = lerpf(900.0, 2400.0, weight_t)
	var brake_from_weight: float = lerpf(160.0, 360.0, weight_t)
	var max_brake_force: float = brake_from_weight + (max_speed_kmh - 95.0) * 0.4

	var steer_agility: float = 1.0 - weight_t
	var max_steer_angle: float = lerpf(0.30, 0.48, steer_agility)
	var steer_speed: float = lerpf(2.0, 3.8, steer_agility)
	var steer_return_speed: float = lerpf(3.8, 6.2, steer_agility)
	var reverse_force_ratio: float = lerpf(0.5, 0.72, steer_agility)

	var max_engine_hp: float = lerpf(70.0, 180.0, armor_t)
	var max_chassis_hp: float = lerpf(85.0, 240.0, armor_t)
	var max_wheel_hp: float = lerpf(35.0, 95.0, armor_t)
	var max_weapon_hp: float = lerpf(45.0, 120.0, armor_t)

	return {
		"max_speed_kmh": max_speed_kmh,
		"max_engine_force": max_engine_force,
		"boost_force_multiplier": boost_force_multiplier,
		"mass": mass,
		"max_brake_force": max_brake_force,
		"reverse_force_ratio": reverse_force_ratio,
		"max_steer_angle": max_steer_angle,
		"steer_speed": steer_speed,
		"steer_return_speed": steer_return_speed,
		"max_engine_hp": max_engine_hp,
		"max_chassis_hp": max_chassis_hp,
		"max_wheel_hp": max_wheel_hp,
		"max_weapon_hp": max_weapon_hp,
	}


func _seed_for_speed(vehicle_id: String) -> float:
	var seeds := {
		"ambulance": 50.0,
		"delivery": 45.0,
		"delivery_flat": 45.0,
		"firetruck": 40.0,
		"garbage_truck": 35.0,
		"hatchback_sports": 80.0,
		"police": 75.0,
		"race": 95.0,
		"race_future": 100.0,
		"sedan": 60.0,
		"sedan_sports": 85.0,
		"suv": 55.0,
		"suv_luxury": 60.0,
		"taxi": 65.0,
		"truck": 40.0,
		"van": 45.0,
	}
	return _float_or(seeds.get(vehicle_id), 60.0)


func _seed_for_armor(vehicle_id: String) -> float:
	var seeds := {
		"ambulance": 60.0,
		"delivery": 50.0,
		"delivery_flat": 45.0,
		"firetruck": 80.0,
		"garbage_truck": 90.0,
		"hatchback_sports": 30.0,
		"police": 55.0,
		"race": 20.0,
		"race_future": 15.0,
		"sedan": 40.0,
		"sedan_sports": 35.0,
		"suv": 65.0,
		"suv_luxury": 70.0,
		"taxi": 40.0,
		"truck": 75.0,
		"van": 55.0,
	}
	return _float_or(seeds.get(vehicle_id), 50.0)


func _seed_for_weight(vehicle_id: String) -> float:
	var seeds := {
		"ambulance": 70.0,
		"delivery": 65.0,
		"delivery_flat": 60.0,
		"firetruck": 90.0,
		"garbage_truck": 100.0,
		"hatchback_sports": 40.0,
		"police": 50.0,
		"race": 30.0,
		"race_future": 25.0,
		"sedan": 45.0,
		"sedan_sports": 40.0,
		"suv": 75.0,
		"suv_luxury": 80.0,
		"taxi": 45.0,
		"truck": 85.0,
		"van": 60.0,
	}
	return _float_or(seeds.get(vehicle_id), 50.0)


func _average_wheel_radius(car: VehicleBody3D) -> float:
	var total_radius: float = 0.0
	var wheel_count: int = 0
	for child in car.get_children():
		if child is VehicleWheel3D:
			var wheel := child as VehicleWheel3D
			total_radius += wheel.wheel_radius
			wheel_count += 1

	if wheel_count == 0:
		return 0.35

	return total_radius / float(wheel_count)


func _sum_collision_box_volume(node: Node) -> float:
	var volume: float = 0.0
	for child in node.get_children():
		if child is CollisionShape3D:
			var shape_node := child as CollisionShape3D
			if shape_node.shape is BoxShape3D:
				var box := shape_node.shape as BoxShape3D
				volume += box.size.x * box.size.y * box.size.z
		volume += _sum_collision_box_volume(child)
	return volume


func _apply_ui_stats(raw_stats: Array[Dictionary]) -> void:
	if raw_stats.is_empty() or _ordered.is_empty():
		return

	var min_speed: float = _float_or(raw_stats[0].get("speed"), 0.0)
	var max_speed: float = min_speed
	var min_armor: float = _float_or(raw_stats[0].get("armor"), 0.0)
	var max_armor: float = min_armor
	var min_weight: float = _float_or(raw_stats[0].get("weight"), 0.0)
	var max_weight: float = min_weight

	for stats in raw_stats:
		var speed_value: float = _float_or(stats.get("speed"), 0.0)
		var armor_value: float = _float_or(stats.get("armor"), 0.0)
		var weight_value: float = _float_or(stats.get("weight"), 0.0)

		min_speed = minf(min_speed, speed_value)
		max_speed = maxf(max_speed, speed_value)
		min_armor = minf(min_armor, armor_value)
		max_armor = maxf(max_armor, armor_value)
		min_weight = minf(min_weight, weight_value)
		max_weight = maxf(max_weight, weight_value)

	for i in range(_ordered.size()):
		var data: VehicleData = _ordered[i]
		var stats := raw_stats[i]
		data.ui_speed = _normalize_to_ui(_float_or(stats.get("speed"), 0.0), min_speed, max_speed)
		data.ui_armor = _normalize_to_ui(_float_or(stats.get("armor"), 0.0), min_armor, max_armor)
		data.ui_weight = _normalize_to_ui(_float_or(stats.get("weight"), 0.0), min_weight, max_weight)


func _normalize_to_ui(value: float, min_value: float, max_value: float) -> float:
	if is_equal_approx(min_value, max_value):
		return DEFAULT_UI_STAT
	var normalized: float = ((value - min_value) / (max_value - min_value)) * UI_STAT_MAX
	return clampf(normalized, UI_STAT_MIN, UI_STAT_MAX)


func _float_or(value: Variant, fallback: float) -> float:
	if value == null:
		return fallback
	if value is float or value is int:
		return float(value)
	return fallback
