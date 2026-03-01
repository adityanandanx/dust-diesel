extends WeaponBase

## Flame Projector — short-range fire cone, DoT, ignites oil puddles.

@export var cone_range: float = 8.0
@export var cone_angle_deg: float = 30.0
@export var dot_duration: float = 3.0
@export var fire_puddle_duration: float = 4.0

var _is_firing: bool = false
@onready var _flame_particles: GPUParticles3D = %FlameParticles
@onready var _smoke_particles: GPUParticles3D = %SmokeParticles


func _do_fire() -> void:
	if not owner_car:
		return
	_is_firing = true
	if _flame_particles:
		_flame_particles.emitting = true
	if _smoke_particles:
		_smoke_particles.emitting = true
	# Cone damage check — find all cars in range and angle
	var origin: Vector3 = get_muzzle_position()
	var forward: Vector3 = get_muzzle_direction()

	for body in _get_bodies_in_range(origin, cone_range):
		if body == owner_car:
			continue
		var to_target: Vector3 = (body.global_position - origin).normalized()
		var angle: float = forward.angle_to(to_target)
		if angle <= deg_to_rad(cone_angle_deg):
			_apply_flame_damage(body)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not Input.is_action_pressed("fire_primary") or is_overheated:
		_is_firing = false
		if _flame_particles:
			_flame_particles.emitting = false
		if _smoke_particles:
			_smoke_particles.emitting = false


func _apply_flame_damage(body: Node3D) -> void:
	if body is VehicleBody3D and body.has_node("DamageSystem"):
		var dmg_sys = body.get_node("DamageSystem")
		dmg_sys.take_damage(dmg_sys.DamageZone.ENGINE, damage)
		# Apply burning DoT via metadata
		if body.has_method("apply_burning"):
			body.apply_burning(damage, dot_duration)


func _get_bodies_in_range(origin: Vector3, radius: float) -> Array:
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, origin)
	query.collision_mask = 1 # car layer

	var results := space.intersect_shape(query, 16)
	var bodies: Array = []
	for r in results:
		if r["collider"] not in bodies:
			bodies.append(r["collider"])
	return bodies
