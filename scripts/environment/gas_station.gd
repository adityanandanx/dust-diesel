extends DestructibleBase

## Gas Station — massive one-time chain explosion, reshapes the area.

@export var explosion_scene: PackedScene


func _ready() -> void:
	super._ready()
	max_hp = 200.0
	hp = max_hp
	ram_damage_to_car = 25.0
	loot_table = [
		preload("res://scenes/pickups/WeaponPickup.tscn"),
		preload("res://scenes/pickups/Powerup.tscn"),
		preload("res://scenes/pickups/FuelCan.tscn"),
	]
	loot_count = 4
	mass = 5000.0 # immovable


func _on_destroyed() -> void:
	_mega_explosion()


func _mega_explosion() -> void:
	# Spawn massive explosion particles
	if explosion_scene:
		var fx: Node3D = explosion_scene.instantiate()
		get_tree().current_scene.add_child(fx)
		fx.global_position = global_position + Vector3(0, 1.0, 0)
		if fx.has_method("set_scale_factor"):
			fx.set_scale_factor(2.5)
		if fx.has_method("explode"):
			fx.explode()

	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 15.0
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.collision_mask = 0xFF

	var results := space.intersect_shape(query, 64)
	for r in results:
		var body = r["collider"]
		if body == self:
			continue
		var dist := global_position.distance_to(body.global_position)
		var falloff := 1.0 - clampf(dist / 15.0, 0.0, 1.0)

		# Massive damage to cars
		if body is VehicleBody3D and body.has_node("DamageSystem"):
			var dmg_sys = body.get_node("DamageSystem")
			dmg_sys.take_damage(dmg_sys.DamageZone.CHASSIS, 80.0 * falloff)
			dmg_sys.take_damage(dmg_sys.DamageZone.ENGINE, 40.0 * falloff)
			var push = (body.global_position - global_position).normalized()
			body.apply_central_impulse(push * 15000.0 * falloff)

		# Destroy nearby destructibles
		if body is DestructibleBase and not body.is_destroyed:
			body.take_damage(200.0, self )

		# Fling any RigidBody3D
		if body is RigidBody3D and body != self:
			var push = (body.global_position - global_position).normalized()
			body.apply_central_impulse(push * 8000.0 * falloff)
