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
static var _loot_id_counter: int = 0


func _ready() -> void:
	hp = max_hp
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)


func take_damage(amount: float, attacker: Node = null) -> void:
	if is_destroyed:
		return
		
	# Broadcast the damage to others
	if NakamaManager.current_match:
		var data = {"id": str(get_path()), "amount": amount}
		NakamaManager.send_match_state(NakamaManager.OpCodes.ENV_DAMAGE, JSON.stringify(data))
		
	_apply_damage_internal(amount, attacker)


func _apply_damage_internal(amount: float, attacker: Node = null) -> void:
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
	# In multiplayer, only the host spawns loot (non-host receives via SPAWN_PICKUP)
	if NakamaManager.current_match and not NakamaManager.is_host:
		return
	
	for i in loot_count:
		if loot_table.is_empty():
			break
		var scene: PackedScene = loot_table.pick_random()
		var pickup = scene.instantiate()
		
		var scatter := Vector3(
			randf_range(-3.0, 3.0),
			0,
			randf_range(-3.0, 3.0)
		)
		var spawn_pos := global_position + scatter + Vector3.UP
		
		# Assign a unique pickup_id
		_loot_id_counter += 1
		var p_id := _loot_id_counter + 100000 # offset to avoid clashing with PickupSpawner IDs
		
		if pickup is PickupBase:
			pickup.pickup_id = p_id
		
		get_tree().current_scene.add_child(pickup)
		pickup.global_position = spawn_pos
		
		# Broadcast to remote clients
		if NakamaManager.current_match:
			# Determine category: 0=weapon, 1=powerup, 2=fuel
			var cat := -1
			var sub := -1
			if pickup.has_method("apply"):
				var script_path: String = pickup.get_script().resource_path
				if "weapon" in script_path.to_lower() or "WeaponPickup" in script_path:
					cat = 0
				elif "powerup" in script_path.to_lower() or "Powerup" in script_path:
					cat = 1
					if "powerup_type" in pickup:
						sub = pickup.powerup_type
				elif "fuel" in script_path.to_lower() or "FuelCan" in script_path:
					cat = 2
			
			if cat >= 0:
				var data = {
					"id": p_id,
					"cat": cat,
					"sub": sub,
					"px": snappedf(spawn_pos.x, 0.01),
					"py": snappedf(spawn_pos.y, 0.01),
					"pz": snappedf(spawn_pos.z, 0.01)
				}
				NakamaManager.send_match_state(NakamaManager.OpCodes.SPAWN_PICKUP, JSON.stringify(data))
