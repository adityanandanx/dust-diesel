extends DestructibleBase

## Fuel Barrel — explodes on destroy, chain-reacts, drops fuel can.

@export var explosion_scene: PackedScene


func _ready() -> void:
	super._ready()
	max_hp = 30.0
	hp = max_hp
	ram_damage_to_car = 5.0
	loot_table = [preload("res://scenes/pickups/FuelCan.tscn")]
	loot_count = 1


func _on_destroyed() -> void:
	_explode()


func _explode() -> void:
	# Spawn explosion particles
	if explosion_scene:
		var fx: Node3D = explosion_scene.instantiate()
		get_tree().current_scene.add_child(fx)
		fx.global_position = global_position + Vector3(0, 0.5, 0)
		if fx.has_method("set_scale_factor"):
			fx.set_scale_factor(1.0)
		if fx.has_method("explode"):
			fx.explode()

	# Splash damage to nearby cars and destructibles
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 8.0
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.collision_mask = 0xFF # all layers

	var results := space.intersect_shape(query, 32)
	for r in results:
		var body = r["collider"]
		if body == self:
			continue
		var dist := global_position.distance_to(body.global_position)
		var falloff := 1.0 - clampf(dist / 8.0, 0.0, 1.0)
		var dmg := 30.0 * falloff

		# Damage cars
		if body is VehicleBody3D and body.has_node("DamageSystem"):
			body.get_node("DamageSystem").take_damage(
				body.get_node("DamageSystem").DamageZone.CHASSIS, dmg
			)
			var push = (body.global_position - global_position).normalized()
			body.apply_central_impulse(push * 6000.0 * falloff)

		# Chain-react other destructibles
		if body is DestructibleBase and not body.is_destroyed:
			body.take_damage(dmg, self )
