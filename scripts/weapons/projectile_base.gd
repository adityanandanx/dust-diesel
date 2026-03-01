extends CharacterBody3D
class_name ProjectileBase

## Base for physical projectiles — bolts, spears, scrap chunks.

const HitParticlesScene := preload("res://scenes/particles/CollisionSparks.tscn")

signal hit(collider: Node)

@export var speed: float = 60.0
@export var damage: float = 10.0
@export var lifetime: float = 3.0
@export var splash_radius: float = 0.0 ## 0 = no splash
@export var splash_damage: float = 0.0
@export var max_bounces: int = 0 ## 0 = no bounce

var owner_car: Node = null
var _bounces_left: int = 0
var _age: float = 0.0
var _direction: Vector3 = Vector3.FORWARD


func _ready() -> void:
	_bounces_left = max_bounces


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return

	velocity = _direction * speed
	var collision := move_and_collide(velocity * delta)
	if collision:
		var collider := collision.get_collider()
		if collider == owner_car:
			# Pass through owner — move past the collision
			global_position += _direction * speed * delta
			return
		_on_hit(collision)


func launch(dir: Vector3, from_car: Node = null) -> void:
	_direction = dir.normalized()
	owner_car = from_car


func _on_hit(collision: KinematicCollision3D) -> void:
	var collider := collision.get_collider()
	var hit_position: Vector3 = collision.get_position()
	var valid_owner: Node = _get_valid_owner_car()
	_spawn_hit_particles(collision)

	# Don't hit our own car
	if _is_same_or_ancestor(collider, valid_owner):
		return

	hit.emit(collider)

	# Remote projectiles deal no damage to prevent double-dipping in multiplayer
	if valid_owner and not valid_owner.is_player and NakamaManager.current_match:
		queue_free()
		return

	# Direct damage
	var damage_target: Node = _resolve_damage_target(collider)
	if damage_target and damage_target.has_method("take_hit"):
		damage_target.take_hit(damage, hit_position, valid_owner)
	elif damage_target is VehicleBody3D and damage_target.has_node("DamageSystem"):
		var dmg_sys: Node = damage_target.get_node("DamageSystem")
		if dmg_sys and dmg_sys.has_method("take_collision_damage"):
			dmg_sys.take_collision_damage(damage)
	elif damage_target is DestructibleBase and not damage_target.is_destroyed:
		damage_target.take_damage(damage, valid_owner)

	# Splash damage
	if splash_radius > 0.0:
		_apply_splash(global_position)

	# Bounce off static geometry
	if _bounces_left > 0 and collider is StaticBody3D:
		_bounces_left -= 1
		var normal := collision.get_normal()
		_direction = _direction.bounce(normal).normalized()
		return # Don't destroy — keep going

	queue_free()


func _spawn_hit_particles(collision: KinematicCollision3D) -> void:
	if HitParticlesScene == null:
		return

	var fx: Node3D = HitParticlesScene.instantiate()
	get_tree().current_scene.add_child(fx)

	var hit_pos: Vector3 = collision.get_position()
	var hit_normal: Vector3 = collision.get_normal().normalized()
	fx.global_position = hit_pos + hit_normal * 0.03

	if fx.has_method("set"):
		fx.set("auto_free", true)
	if fx.has_method("emit_at"):
		fx.emit_at(fx.global_position)


func _apply_splash(center: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = splash_radius
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, center)
	query.collision_mask = collision_mask

	var results := space.intersect_shape(query, 16)
	var valid_owner: Node = _get_valid_owner_car()
	for result in results:
		var body: Node = result["collider"]
		var damage_target: Node = _resolve_damage_target(body)
		if _is_same_or_ancestor(damage_target, valid_owner):
			continue
		if not (damage_target is Node3D):
			continue
		var dist := center.distance_to((damage_target as Node3D).global_position)
		var falloff := 1.0 - clampf(dist / splash_radius, 0.0, 1.0)
		if damage_target and damage_target.has_method("take_hit"):
			damage_target.take_hit(splash_damage * falloff, center, valid_owner)
		elif damage_target is VehicleBody3D and damage_target.has_node("DamageSystem"):
			damage_target.get_node("DamageSystem").take_collision_damage(splash_damage * falloff)
		elif damage_target is DestructibleBase and not damage_target.is_destroyed:
			damage_target.take_damage(splash_damage * falloff, valid_owner)


func _resolve_damage_target(collider: Node) -> Node:
	var current: Node = collider
	while current:
		if current.has_method("take_hit"):
			return current
		if current is VehicleBody3D and current.has_node("DamageSystem"):
			return current
		if current is DestructibleBase:
			return current
		current = current.get_parent()
	return collider


func _is_same_or_ancestor(node: Node, candidate_ancestor: Variant) -> bool:
	if node == null:
		return false
	if candidate_ancestor == null:
		return false
	if not (candidate_ancestor is Node):
		return false
	if not is_instance_valid(candidate_ancestor):
		return false
	var ancestor: Node = candidate_ancestor as Node
	var current: Node = node
	while current:
		if current == ancestor:
			return true
		current = current.get_parent()
	return false


func _get_valid_owner_car() -> Node:
	if owner_car == null:
		return null
	if not is_instance_valid(owner_car):
		owner_car = null
		return null
	return owner_car
