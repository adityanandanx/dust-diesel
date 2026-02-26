extends Node3D

## Last Driver Standing game mode controller.
## Spawns cars, tracks eliminations, declares winner.

signal player_eliminated(player_name: String, killer_name: String)
signal match_ended(winner_name: String)

const CarScene := preload("res://scenes/vehicles/Car.tscn")
const WreckScene := preload("res://scenes/vehicles/CarWreck.tscn")

@onready var spawn_points: Node3D = $SpawnPoints
@onready var cars_container: Node3D = $Cars
@onready var wrecks_container: Node3D = $Wrecks
@onready var hud: Control = $HUDLayer/HUD

var alive_cars: Array[Car] = []
var kill_feed: Array[Dictionary] = [] # {victim, killer, cause, time}


func _ready() -> void:
	_spawn_players()


func _spawn_players() -> void:
	var points := spawn_points.get_children()
	# For Phase 1: spawn 1 player car at first spawn point
	var car: Car = CarScene.instantiate()
	cars_container.add_child(car)
	car.global_transform = points[0].global_transform
	car.car_destroyed.connect(_on_car_destroyed)
	car.car_stalled.connect(_on_car_stalled)
	alive_cars.append(car)

	# Connect HUD to this car
	if hud and hud.has_method("bind_car"):
		hud.bind_car(car)


func _on_car_destroyed(car: Car) -> void:
	_eliminate_car(car, "destroyed")


func _on_car_stalled(car: Car) -> void:
	_eliminate_car(car, "out of fuel")


func _eliminate_car(car: Car, cause: String) -> void:
	alive_cars.erase(car)

	# Spawn wreck at car position
	var wreck: RigidBody3D = WreckScene.instantiate()
	wrecks_container.add_child(wreck)
	wreck.global_transform = car.global_transform
	wreck.linear_velocity = car.linear_velocity * 0.5

	# Log elimination
	var entry := {"victim": car.name, "killer": "", "cause": cause, "time": Time.get_ticks_msec()}
	kill_feed.append(entry)
	player_eliminated.emit(car.name, "")

	# Remove the car
	car.queue_free()

	# Check win condition
	if alive_cars.size() <= 1 and alive_cars.size() > 0:
		var winner: Car = alive_cars[0]
		match_ended.emit(winner.name)
	elif alive_cars.is_empty():
		match_ended.emit("Nobody")
