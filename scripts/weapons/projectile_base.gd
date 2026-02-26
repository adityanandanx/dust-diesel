extends CharacterBody3D
class_name ProjectileBase

## Base for physical projectiles — bolts, spears, scrap chunks.

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

	# Don't hit our own car
	if collider == owner_car:
		return

	hit.emit(collider)

	# Direct damage
	if collider.has_method("take_hit"):
		collider.take_hit(damage, global_position, owner_car)
	elif collider is VehicleBody3D and collider.has_node("DamageSystem"):
		var dmg_sys = collider.get_node("DamageSystem")
		dmg_sys.take_collision_damage(damage)
	elif collider is DestructibleBase and not collider.is_destroyed:
		collider.take_damage(damage, owner_car)

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


func _apply_splash(center: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = splash_radius
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, center)
	query.collision_mask = collision_mask

	var results := space.intersect_shape(query, 16)
	for result in results:
		var body = result["collider"]
		if body == owner_car:
			continue
		var dist := center.distance_to(body.global_position)
		var falloff := 1.0 - clampf(dist / splash_radius, 0.0, 1.0)
		if body is VehicleBody3D and body.has_node("DamageSystem"):
			body.get_node("DamageSystem").take_collision_damage(splash_damage * falloff)
		elif body is DestructibleBase and not body.is_destroyed:
			body.take_damage(splash_damage * falloff, owner_car)
