extends Node

## Autoload singleton — catalog of all driveable vehicles.

const VehicleDataScript = preload("res://scripts/car/vehicle_data.gd")

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
	return _ordered[0]


func get_random():
	return _ordered[randi() % _ordered.size()]


func get_vehicle_index(id: String) -> int:
	for i in range(_ordered.size()):
		if _ordered[i].id == id:
			return i
	return 0


func _register_vehicles() -> void:
	var defs := [
		# id, display_name, basename, ui_speed, ui_armor, ui_weight
		["ambulance", "Ambulance", "Ambulance", 50.0, 60.0, 70.0],
		["delivery", "Delivery Van", "Delivery", 45.0, 50.0, 65.0],
		["delivery_flat", "Flatbed Delivery", "DeliveryFlat", 45.0, 45.0, 60.0],
		["firetruck", "Fire Truck", "Firetruck", 40.0, 80.0, 90.0],
		["garbage_truck", "Garbage Truck", "GarbageTruck", 35.0, 90.0, 100.0],
		["hatchback_sports", "Sport Hatchback", "HatchbackSports", 80.0, 30.0, 40.0],
		["police", "Police Car", "Police", 75.0, 55.0, 50.0],
		["race", "Race Car", "Race", 95.0, 20.0, 30.0],
		["race_future", "Future Racer", "RaceFuture", 100.0, 15.0, 25.0],
		["sedan", "Sedan", "Sedan", 60.0, 40.0, 45.0],
		["sedan_sports", "Sport Sedan", "SedanSports", 85.0, 35.0, 40.0],
		["suv", "SUV", "Suv", 55.0, 65.0, 75.0],
		["suv_luxury", "Luxury SUV", "SuvLuxury", 60.0, 70.0, 80.0],
		["taxi", "Taxi", "Taxi", 65.0, 40.0, 45.0],
		["truck", "Truck", "Truck", 40.0, 75.0, 85.0],
		["van", "Van", "Van", 45.0, 55.0, 60.0],
	]

	var model_base_path := "res://assets/models/cars/"
	var scene_base_path := "res://scenes/vehicles/cars/"
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
		
		v.ui_speed = d[3]
		v.ui_armor = d[4]
		v.ui_weight = d[5]
		
		_vehicles[v.id] = v
		_ordered.append(v)
