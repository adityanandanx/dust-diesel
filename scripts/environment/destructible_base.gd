extends RigidBody3D
class_name DestructibleBase

## Base for all destructible environment objects.

signal destroyed(position: Vector3, attacker: Node)

@export var max_hp: float = 100.0
@export var ram_speed_threshold: float = 20.0 ## km/h needed to deal ram damage
@export var ram_damage_to_car: float = 10.0

var hp: float = max_hp
var is_destroyed: bool = false
var loot_table: Array[PackedScene] = []
var loot_count: int = 1


func _ready() -> void:
	hp = max_hp
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)


func take_damage(amount: float, attacker: Node = null) -> void:
	if is_destroyed:
		return
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		_destroy(attacker)


func _on_body_entered(body: Node) -> void:
	if is_destroyed:
		return
	if body is VehicleBody3D:
		var speed_kmh: float = body.linear_velocity.length() * 3.6
		if speed_kmh >= ram_speed_threshold:
			# Damage the destructible
			var ram_dmg := speed_kmh * 0.5
			take_damage(ram_dmg, body)
			# Damage the car too
			if body.has_node("DamageSystem"):
				var dmg = body.get_node("DamageSystem")
				dmg.take_damage(dmg.DamageZone.CHASSIS, ram_damage_to_car)


func _destroy(attacker: Node = null) -> void:
	if is_destroyed:
		return
	is_destroyed = true
	destroyed.emit(global_position, attacker)
	_on_destroyed()
	_drop_loot()
	queue_free()


## Override in subclasses for custom destruction effects
func _on_destroyed() -> void:
	pass


func _drop_loot() -> void:
	for i in loot_count:
		if loot_table.is_empty():
			break
		var scene: PackedScene = loot_table.pick_random()
		var pickup = scene.instantiate()
		get_tree().current_scene.add_child(pickup)
		var scatter := Vector3(
			randf_range(-3.0, 3.0),
			0,
			randf_range(-3.0, 3.0)
		)
		pickup.global_position = global_position + scatter + Vector3.UP
