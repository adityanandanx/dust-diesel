extends CharacterBody3D
class_name HarpoonSpear

## Harpoon projectile that embeds into the first collider it hits.
## Emits a `stuck` signal and stays attached to moving targets.

const HitParticlesScene := preload("res://scenes/particles/CollisionSparks.tscn")

signal stuck(collider: Node, hit_position: Vector3, hit_normal: Vector3)

@export var speed: float = 50.0
@export var damage: float = 15.0
@export var lifetime: float = 6.0

var owner_car: Node = null

var _age: float = 0.0
var _direction: Vector3 = Vector3.FORWARD
var _is_stuck: bool = false
var _stuck_collider: Node = null
var _stuck_parent: Node3D = null
var _stuck_local_position: Vector3 = Vector3.ZERO
var _stuck_local_normal: Vector3 = Vector3.FORWARD


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return

	if _is_stuck:
		_update_stuck_transform()
		return

	velocity = _direction * speed
	var collision: KinematicCollision3D = move_and_collide(velocity * delta)
	if collision:
		var collider: Node = collision.get_collider()
		if collider == owner_car:
			global_position += _direction * speed * delta
			return
		_on_hit(collision)


func launch(dir: Vector3, from_car: Node = null) -> void:
	_direction = dir.normalized()
	owner_car = from_car
	look_at(global_position + _direction, Vector3.UP)


func _on_hit(collision: KinematicCollision3D) -> void:
	var collider: Node = collision.get_collider()
	var valid_owner: Node = _get_valid_owner_car()
	_spawn_hit_particles(collision)

	if _is_same_or_ancestor(collider, valid_owner):
		return

	_apply_impact_damage(collider, collision.get_position(), valid_owner)
	_embed(collider, collision.get_position(), collision.get_normal())


func _apply_impact_damage(collider: Node, hit_position: Vector3, valid_owner: Node) -> void:
	# Remote projectiles deal no damage to prevent double-dipping in multiplayer.
	if valid_owner and not valid_owner.is_player and NakamaManager.current_match:
		return

	var damage_target: Node = _resolve_damage_target(collider)

	if damage_target and damage_target.has_method("take_hit"):
		damage_target.take_hit(damage, hit_position, valid_owner)
	elif damage_target is VehicleBody3D and damage_target.has_node("DamageSystem"):
		var dmg_sys: Node = damage_target.get_node("DamageSystem")
		if dmg_sys and dmg_sys.has_method("take_collision_damage"):
			dmg_sys.take_collision_damage(damage)
	elif damage_target is DestructibleBase and not damage_target.is_destroyed:
		damage_target.take_damage(damage, valid_owner)


func _embed(collider: Node, hit_position: Vector3, hit_normal: Vector3) -> void:
	_is_stuck = true
	_stuck_collider = collider
	velocity = Vector3.ZERO

	if collider is Node3D:
		_stuck_parent = collider as Node3D
		_stuck_local_position = _stuck_parent.to_local(hit_position)
		var local_normal_basis: Basis = _stuck_parent.global_basis.inverse()
		_stuck_local_normal = (local_normal_basis * hit_normal).normalized()
	else:
		_stuck_parent = null
		_stuck_local_position = hit_position
		_stuck_local_normal = hit_normal.normalized()

	var shape: CollisionShape3D = get_node_or_null("CollisionShape3D")
	if shape:
		shape.disabled = true
	collision_layer = 0
	collision_mask = 0

	_update_stuck_transform()
	stuck.emit(collider, global_position, _get_world_normal())


func _update_stuck_transform() -> void:
	if _stuck_parent and is_instance_valid(_stuck_parent):
		global_position = _stuck_parent.to_global(_stuck_local_position)
	else:
		global_position = _stuck_local_position

	var world_normal: Vector3 = _get_world_normal()
	if world_normal.length_squared() < 0.001:
		world_normal = _direction
	var up: Vector3 = Vector3.UP
	if absf(world_normal.normalized().dot(up)) > 0.995:
		up = Vector3.FORWARD
	look_at(global_position + world_normal, up)


func _get_world_normal() -> Vector3:
	if _stuck_parent and is_instance_valid(_stuck_parent):
		return (_stuck_parent.global_basis * _stuck_local_normal).normalized()
	return _stuck_local_normal.normalized()


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
