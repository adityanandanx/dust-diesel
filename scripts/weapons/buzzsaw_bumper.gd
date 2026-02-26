extends Node3D

## Buzzsaw Bumper — melee upgrade. Ram damage becomes weapon-grade while boosting.

@export var buzzsaw_damage: float = 40.0
@export var min_ram_speed: float = 30.0 ## km/h

var owner_car: VehicleBody3D = null
var _is_active: bool = false


func _ready() -> void:
	owner_car = get_parent()
	if owner_car is VehicleBody3D:
		owner_car.body_entered.connect(_on_body_entered)


func _physics_process(_delta: float) -> void:
	if not owner_car:
		return
	_is_active = owner_car.is_boosting if owner_car.has_method("get_forward_speed") else false


func _on_body_entered(body: Node) -> void:
	if not _is_active or body == owner_car:
		return
	if not (body is VehicleBody3D):
		return

	var speed_kmh: float = owner_car.linear_velocity.length() * 3.6
	if speed_kmh < min_ram_speed:
		return

	# Apply weapon-grade damage instead of collision damage
	if body.has_node("DamageSystem"):
		var dmg = body.get_node("DamageSystem")
		dmg.take_damage(dmg.DamageZone.CHASSIS, buzzsaw_damage)
		dmg.take_damage(dmg.DamageZone.ENGINE, buzzsaw_damage * 0.3)
