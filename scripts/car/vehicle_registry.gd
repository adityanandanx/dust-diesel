extends Node

## Autoload singleton — catalog of all driveable vehicles.

const VehicleDataScript = preload("res://scripts/car/vehicle_data.gd")

const DEFAULT_UI_STAT: float = 50.0
const UI_STAT_MIN: float = 0.0
const UI_STAT_MAX: float = 100.0

var _vehicles: Dictionary = {} # id -> VehicleData
var _ordered: Array = []


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
		if _ordered[i].id == id:
			return i
	return 0


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

		var stats: Dictionary = _extract_runtime_stats(v.scene_path)
		raw_stats.append(stats)
		
		_vehicles[v.id] = v
		_ordered.append(v)

	_apply_ui_stats(raw_stats)


func _extract_runtime_stats(scene_path: String) -> Dictionary:
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
