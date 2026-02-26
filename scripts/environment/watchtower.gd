extends DestructibleBase

## Watchtower — tall structure, collapses into physics debris on destroy.


func _ready() -> void:
	super._ready()
	max_hp = 120.0
	hp = max_hp
	ram_damage_to_car = 20.0
	loot_table = [
		preload("res://scenes/pickups/WeaponPickup.tscn"),
		preload("res://scenes/pickups/Powerup.tscn"),
		preload("res://scenes/pickups/FuelCan.tscn"),
	]
	loot_count = 2
	mass = 2000.0 # very heavy


func _on_destroyed() -> void:
	# Spawn falling debris chunks
	for i in 4:
		var debris := RigidBody3D.new()
		var mesh := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = Vector3(
			randf_range(0.5, 1.5),
			randf_range(0.3, 1.0),
			randf_range(0.5, 1.5)
		)
		mesh.mesh = box_mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.4, 0.35, 0.3, 1)
		mesh.set_surface_override_material(0, mat)
		debris.add_child(mesh)

		var col := CollisionShape3D.new()
		var col_shape := BoxShape3D.new()
		col_shape.size = box_mesh.size
		col.shape = col_shape
		debris.add_child(col)

		debris.mass = 200.0
		get_tree().current_scene.add_child(debris)
		debris.global_position = global_position + Vector3(
			randf_range(-1.5, 1.5),
			randf_range(2.0, 5.0),
			randf_range(-1.5, 1.5)
		)
		# Scatter outward
		var scatter_dir := Vector3(randf_range(-1, 1), 0.5, randf_range(-1, 1)).normalized()
		debris.apply_central_impulse(scatter_dir * 2000.0)

		# Auto-cleanup debris after 10s
		get_tree().create_timer(10.0).timeout.connect(func():
			if is_instance_valid(debris):
				debris.queue_free()
		)
