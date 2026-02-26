extends Node3D

## Pickup Spawner — manages timed spawn of weapons, powerups, and fuel cans.

const WeaponPickupScene := preload("res://scenes/pickups/WeaponPickup.tscn")
const PowerupScene := preload("res://scenes/pickups/Powerup.tscn")
const FuelCanScene := preload("res://scenes/pickups/FuelCan.tscn")

@export var weapon_spawn_interval: float = 15.0
@export var powerup_spawn_interval: float = 20.0
@export var fuel_spawn_interval: float = 25.0
@export var max_active_pickups: int = 8

var _weapon_timer: float = 5.0 # first weapon spawns at 5s
var _powerup_timer: float = 10.0
var _fuel_timer: float = 8.0
var _active_pickups: int = 0

# Spawn positions around the arena
var _spawn_positions: Array[Vector3] = [
	Vector3(20, 0, 0),
	Vector3(-20, 0, 0),
	Vector3(0, 0, 20),
	Vector3(0, 0, -20),
	Vector3(15, 0, 15),
	Vector3(-15, 0, 15),
	Vector3(15, 0, -15),
	Vector3(-15, 0, -15),
	Vector3(35, 0, 0),
	Vector3(-35, 0, 0),
	Vector3(0, 0, 35),
	Vector3(0, 0, -35),
]


func _physics_process(delta: float) -> void:
	_weapon_timer -= delta
	_powerup_timer -= delta
	_fuel_timer -= delta

	if _weapon_timer <= 0.0:
		_weapon_timer = weapon_spawn_interval
		_spawn_pickup(WeaponPickupScene)

	if _powerup_timer <= 0.0:
		_powerup_timer = powerup_spawn_interval
		_spawn_random_powerup()

	if _fuel_timer <= 0.0:
		_fuel_timer = fuel_spawn_interval
		_spawn_pickup(FuelCanScene)


func _spawn_pickup(scene: PackedScene) -> void:
	if _active_pickups >= max_active_pickups:
		return
	var pickup = scene.instantiate()
	add_child(pickup)
	pickup.global_position = _spawn_positions.pick_random()
	_active_pickups += 1
	pickup.tree_exited.connect(func(): _active_pickups -= 1)


func _spawn_random_powerup() -> void:
	if _active_pickups >= max_active_pickups:
		return
	var pickup = PowerupScene.instantiate()
	add_child(pickup)
	pickup.global_position = _spawn_positions.pick_random()
	# Randomize powerup type
	var types = pickup.PowerupType.values()
	pickup.powerup_type = types.pick_random()
	_active_pickups += 1
	pickup.tree_exited.connect(func(): _active_pickups -= 1)
