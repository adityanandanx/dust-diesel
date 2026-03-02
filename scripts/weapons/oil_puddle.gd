extends Area3D

## Oil Puddle — any car entering loses traction. Ignitable.

@export var friction_override: float = 0.2
@export var lifetime: float = 12.0

var _timer: float = 0.0
var is_ignited: bool = false
var _affected_cars: Dictionary = {} # car -> original friction
var owner_car: Node = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _physics_process(delta: float) -> void:
	_timer += delta
	if _timer >= lifetime:
		# Restore friction for any cars still on the puddle
		for car in _affected_cars:
			if is_instance_valid(car):
				_restore_friction(car)
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if not _can_apply_gameplay_effects():
		return
	if body is VehicleBody3D and body not in _affected_cars:
		_affected_cars[body] = []
		# Kill traction on all wheels
		for child in body.get_children():
			if child is VehicleWheel3D:
				_affected_cars[body].append(child.wheel_friction_slip)
				child.wheel_friction_slip = friction_override


func _on_body_exited(body: Node3D) -> void:
	if not _can_apply_gameplay_effects():
		return
	if body in _affected_cars:
		_restore_friction(body)
		_affected_cars.erase(body)


func _restore_friction(body: Node3D) -> void:
	if not is_instance_valid(body):
		return
	var original_frictions: Array = _affected_cars.get(body, [])
	var idx := 0
	for child in body.get_children():
		if child is VehicleWheel3D and idx < original_frictions.size():
			child.wheel_friction_slip = original_frictions[idx]
			idx += 1


func ignite() -> void:
	if is_ignited:
		return
	if not _can_apply_gameplay_effects():
		return
	is_ignited = true
	# TODO: Swap to fire puddle visual, deal fire damage
	lifetime = minf(_timer + 3.0, lifetime) # burn out faster


func _can_apply_gameplay_effects() -> bool:
	if NakamaManager.current_match == null:
		return true
	if owner_car == null or not is_instance_valid(owner_car):
		return false
	if owner_car.has_method("is_authoritative_instance"):
		return bool(owner_car.is_authoritative_instance())
	return bool(owner_car.get("is_player"))
