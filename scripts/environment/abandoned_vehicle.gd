extends DestructibleBase

## Abandoned Vehicle — rammable wreck, explodes on destroy, drops weapon pickup.

@export var explosion_scene: PackedScene


func _ready() -> void:
	super._ready()
	max_hp = 60.0
	hp = max_hp
	ram_damage_to_car = 8.0
	loot_table = [preload("res://scenes/pickups/WeaponPickup.tscn")]
	loot_count = 1
	mass = 800.0


func _on_destroyed() -> void:
	var attacker: Node = get_last_attacker()

	# Spawn explosion particles
	if explosion_scene:
		var fx: Node3D = explosion_scene.instantiate()
		get_tree().current_scene.add_child(fx)
		fx.global_position = global_position + Vector3(0, 0.5, 0)
		if fx.has_method("set_scale_factor"):
			fx.set_scale_factor(0.8)
		if fx.has_method("explode"):
			fx.explode()

	# Small explosion
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 5.0
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.collision_mask = 1 # cars

	var results := space.intersect_shape(query, 16)
	for r in results:
		var body = r["collider"]
		if body is VehicleBody3D and body.has_node("DamageSystem"):
			var dist := global_position.distance_to(body.global_position)
			var falloff := 1.0 - clampf(dist / 5.0, 0.0, 1.0)
			body.get_node("DamageSystem").take_damage(
				body.get_node("DamageSystem").DamageZone.CHASSIS,
				20.0 * falloff,
				attacker
			)
			var push = (body.global_position - global_position).normalized()
			body.apply_central_impulse(push * 3000.0 * falloff)
