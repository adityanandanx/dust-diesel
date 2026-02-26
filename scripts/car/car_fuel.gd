extends Node
class_name CarFuelSystem

## Fuel lifecycle — passive drain, boost drain, engine-damage leak, stall & explode.

signal fuel_changed(current: float, max_fuel: float)
signal fuel_critical()
signal fuel_empty()

@export var max_fuel: float = 100.0
@export var passive_drain_rate: float = 1.0 ## per second
@export var boost_drain_multiplier: float = 2.0
@export var critical_threshold: float = 20.0
@export var stall_delay: float = 5.0 ## seconds after empty before explosion

var fuel: float = 100.0
var is_critical: bool = false
var is_empty: bool = false
var _stall_timer: float = 0.0

@onready var car: Car = get_parent()


func _physics_process(delta: float) -> void:
	if not car or not car.is_alive:
		return

	if is_empty:
		_process_stall(delta)
		return

	# Passive drain
	var drain := passive_drain_rate * delta

	# Engine damage multiplier
	if car.damage_system:
		drain *= car.damage_system.get_fuel_drain_modifier()

	fuel = maxf(fuel - drain, 0.0)
	fuel_changed.emit(fuel, max_fuel)

	if fuel <= critical_threshold and not is_critical:
		is_critical = true
		fuel_critical.emit()

	if fuel <= 0.0:
		is_empty = true
		_stall_timer = stall_delay


func apply_boost_drain(delta: float) -> void:
	fuel = maxf(fuel - passive_drain_rate * boost_drain_multiplier * delta, 0.0)


func _process_stall(delta: float) -> void:
	_stall_timer -= delta
	if car:
		car.engine_force = 0.0
		car.brake = car.max_brake_force * 0.3
	if _stall_timer <= 0.0:
		fuel_empty.emit()


func refuel(amount: float) -> void:
	fuel = minf(fuel + amount, max_fuel)
	is_critical = fuel <= critical_threshold
	is_empty = false
	fuel_changed.emit(fuel, max_fuel)
