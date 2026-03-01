extends Area3D

## Proximity Mine — arms after delay, detonates on car proximity.

@export var arm_delay: float = 1.5
@export var damage: float = 40.0
@export var knockback_force: float = 8000.0
@export var detection_radius: float = 3.0
@export var explosion_scene: PackedScene

var owner_car: Node = null
var is_armed: bool = false
var _arm_timer: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if not is_armed:
		_arm_timer += delta
		if _arm_timer >= arm_delay:
			is_armed = true


func _on_body_entered(body: Node3D) -> void:
	if not is_armed:
		return
	if body == owner_car:
		return
	if body is VehicleBody3D:
		_detonate(body)


func _detonate(target: VehicleBody3D = null) -> void:
	# Spawn explosion particles
	if explosion_scene:
		var fx: Node3D = explosion_scene.instantiate()
		get_tree().current_scene.add_child(fx)
		fx.global_position = global_position + Vector3(0, 0.3, 0)
		if fx.has_method("set_scale_factor"):
			fx.set_scale_factor(0.6)
		if fx.has_method("explode"):
			fx.explode()

	# Direct damage to trigger target
	if target and target.has_node("DamageSystem"):
		var dmg = target.get_node("DamageSystem")
		dmg.take_damage(dmg.DamageZone.CHASSIS, damage)
		# Knockback
		var dir := (target.global_position - global_position).normalized()
		target.apply_central_impulse(dir * knockback_force)

	# Splash damage to nearby cars
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = detection_radius * 2.0
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.collision_mask = 0xFF # Hit cars and destructibles

	var results := space.intersect_shape(query, 16)
	for r in results:
		var body = r["collider"]
		if body == target or body == owner_car:
			continue
		if body is VehicleBody3D and body.has_node("DamageSystem"):
			var dist := global_position.distance_to(body.global_position)
			var falloff := 1.0 - clampf(dist / (detection_radius * 2.0), 0.0, 1.0)
			body.get_node("DamageSystem").take_damage(
				body.get_node("DamageSystem").DamageZone.CHASSIS,
				damage * falloff * 0.5
			)
			var push = (body.global_position - global_position).normalized()
			body.apply_central_impulse(push * knockback_force * falloff * 0.5)
		elif body is DestructibleBase and not body.is_destroyed:
			# Damage destructibles (like barrels) with splash
			var dist := global_position.distance_to(body.global_position)
			var falloff := 1.0 - clampf(dist / (detection_radius * 2.0), 0.0, 1.0)
			body.take_damage(damage * falloff * 0.5)

	# Chain reaction — detonate nearby mines
	for r in results:
		var body = r["collider"]
		if body != self and body is Area3D and body.has_method("_detonate"):
			body.call_deferred("_detonate")

	_deferred_cleanup()


## Allow remote detonation (shot by projectile)
func take_hit(_dmg: float, _pos: Vector3, _attacker: Node) -> void:
	if is_armed:
		_detonate()


func _deferred_cleanup() -> void:
	if is_queued_for_deletion():
		return
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	call_deferred("queue_free")
