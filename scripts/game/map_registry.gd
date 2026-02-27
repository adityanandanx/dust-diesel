extends Node

## Autoload singleton that lists all playable maps.

const MapDataScript = preload("res://scripts/game/map_data.gd")

var _maps: Dictionary = {}
var _ordered: Array = []


func _ready() -> void:
	_register_maps()


func get_all() -> Array:
	return _ordered


func get_by_id(id: String):
	if id in _maps:
		return _maps[id]
	return _ordered[0]


func has_id(id: String) -> bool:
	return id in _maps


func get_map_index(id: String) -> int:
	for i in range(_ordered.size()):
		if _ordered[i].id == id:
			return i
	return 0


func _register_maps() -> void:
	var defs := [
		# id, display name, scene path
		["boneyard", "Boneyard", "res://scenes/game/Boneyard.tscn"],
		["city_raceway", "City Raceway", "res://scenes/game/CityRaceway.tscn"],
	]

	for d in defs:
		var map_data = MapDataScript.new()
		map_data.id = d[0]
		map_data.display_name = d[1]
		map_data.scene_path = d[2]
		_maps[map_data.id] = map_data
		_ordered.append(map_data)
