extends PickupBase

## Weapon Pickup — grants a random weapon when collected.

const WEAPON_POOL: Array[PackedScene] = []

# Populated in _ready since const arrays can't hold preloads
var _weapon_scenes: Array[PackedScene] = []


func _ready() -> void:
	super._ready()
	_weapon_scenes = [
		preload("res://scenes/weapons/RivetCannon.tscn"),
		preload("res://scenes/weapons/ScrapCannon.tscn"),
		preload("res://scenes/weapons/FlameProjector.tscn"),
		preload("res://scenes/weapons/HarpoonLauncher.tscn"),
		preload("res://scenes/weapons/OilSlick.tscn"),
		preload("res://scenes/weapons/MineLayer.tscn"),
		preload("res://scenes/weapons/EMPBlaster.tscn"),
	]


func apply(car: VehicleBody3D) -> void:
	if _weapon_scenes.is_empty():
		return
	var scene: PackedScene = _weapon_scenes.pick_random()
	var weapon = scene.instantiate()
	if car.has_method("equip_weapon"):
		car.equip_weapon(weapon)
