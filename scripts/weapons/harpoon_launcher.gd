extends WeaponBase

## Harpoon Launcher — fires a chain-linked spear, tethers enemy car.
## Applies spring-like force through a visual chain to any stuck target.

const HarpoonSpearScene: PackedScene = preload("res://scenes/weapons/HarpoonSpear.tscn")

@export var spear_speed: float = 50.0
@export var spear_damage: float = 15.0
@export var spring_strength: float = 18000.0
@export var spring_damping: float = 9800.0
@export var pull_boost_multiplier: float = 1.9
@export var max_tether_force: float = 24000.0
@export var max_owner_tether_accel: float = 22.0
@export var max_target_tether_accel: float = 14.0
@export var tether_break_time: float = 2.2
@export var min_tether_length: float = 5.0
@export var max_tether_length: float = 40.0
@export var chain_segments: int = 14
@export var chain_sag: float = 0.06

@onready var rope_origin: Node3D = get_node_or_null("RopeOrigin")

var tether_timer: float = 0.0
var _tethered_target: Node3D = null
var _tether_anchor_local: Vector3 = Vector3.ZERO
var _tether_anchor_world: Vector3 = Vector3.ZERO
var _tether_rest_length: float = 0.0
var _active_spear: Node3D = null
var _tether_line: MeshInstance3D = null
var _tether_mesh: ImmediateMesh = null
var _tether_material: StandardMaterial3D = null


func _ready() -> void:
	super._ready()
	mount_type = MountType.PRIMARY
	fire_rate = 0.5
	damage = spear_damage
	reload_type = ReloadType.NONE
	max_ammo = -1
	recoil_impulse = 90.0
	recoil_torque_impulse = 6.0

	# Prepare the tether line visual
	_tether_mesh = ImmediateMesh.new()
	_tether_material = StandardMaterial3D.new()
	_tether_material.albedo_color = Color(0.8, 0.6, 0.2, 1)
	_tether_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tether_material.no_depth_test = false
	_tether_material.emission_enabled = true
	_tether_material.emission = Color(0.9, 0.7, 0.35, 1.0)
	_tether_material.emission_energy_multiplier = 0.25

	_tether_line = MeshInstance3D.new()
	_tether_line.mesh = _tether_mesh
	_tether_line.material_override = _tether_material
	_tether_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tether_line.top_level = true # world-space coordinates
	_tether_line.visible = false


func _do_fire() -> void:
	if not owner_car or _tethered_target:
		return
	if _active_spear and is_instance_valid(_active_spear):
		return
	var spear: Node3D = HarpoonSpearScene.instantiate() as Node3D
	if spear == null:
		return
	get_tree().current_scene.add_child(spear)
	var forward: Vector3 = get_muzzle_direction()
	spear.global_position = get_muzzle_position(3.0, 0.2)
	if spear.has_method("launch"):
		spear.launch(forward, owner_car)
	spear.set("speed", spear_speed)
	spear.set("damage", spear_damage)
	if spear.has_signal("stuck"):
		spear.stuck.connect(_on_spear_stuck)
	_active_spear = spear
	_tether_line.visible = true


func _physics_process(delta: float) -> void:
	super._physics_process(delta)

	# Harpoon is hold-to-maintain. Releasing fire resets flying spear or active tether.
	var trigger_held: bool = Input.is_action_pressed("fire_primary")
	if not trigger_held and (_tethered_target or (_active_spear and is_instance_valid(_active_spear))):
		_break_tether()
		return

	# Add tether line to scene if needed
	if _tether_line and not _tether_line.is_inside_tree():
		if is_inside_tree():
			get_tree().current_scene.add_child(_tether_line)

	if not owner_car:
		_break_tether()
		return

	if _active_spear and not is_instance_valid(_active_spear):
		_active_spear = null
		if not (_tethered_target and is_instance_valid(_tethered_target)):
			_tether_line.visible = false

	var harpoon_active: bool = (_tethered_target and is_instance_valid(_tethered_target)) or (_active_spear and is_instance_valid(_active_spear))
	if trigger_held and harpoon_active:
		# Keep the weapon in a cooldown state while the held harpoon is active.
		_fire_timer = maxf(_fire_timer, get_fire_cooldown_duration())

	if _tethered_target and is_instance_valid(_tethered_target):
		var anchor_world: Vector3 = _get_anchor_world_position()
		_draw_tether_line(anchor_world)

		var owner_pos: Vector3 = owner_car.global_position + Vector3.UP * 0.5
		var delta_vec: Vector3 = anchor_world - owner_pos
		var dist: float = delta_vec.length()
		if dist <= 0.001:
			return

		if dist > max_tether_length:
			_break_tether()
			return

		var dir: Vector3 = delta_vec / dist
		if dist <= min_tether_length:
			# Hard stop: never apply pull force when already within minimum tether distance.
			tether_timer = maxf(tether_timer - delta * 1.5, 0.0)
			return
		var effective_rest: float = maxf(_tether_rest_length, min_tether_length)
		var stretch: float = maxf(dist - effective_rest, 0.0)

		var owner_velocity: Vector3 = owner_car.linear_velocity if owner_car is VehicleBody3D else Vector3.ZERO
		var target_velocity: Vector3 = _get_target_velocity()
		# Positive means endpoints are separating along the tether axis.
		var separation_speed: float = (target_velocity - owner_velocity).dot(dir)

		# Stable spring-damper: damping reduces pull while closing, increases while separating.
		var pull_force_mag: float = stretch * spring_strength + separation_speed * spring_damping
		if Input.is_action_pressed("fire_primary"):
			pull_force_mag *= lerpf(1.0, pull_boost_multiplier, 0.55)

		pull_force_mag = clampf(pull_force_mag, 0.0, max_tether_force)

		if pull_force_mag > 0.0:
			_apply_tether_force(owner_car, dir * pull_force_mag, max_owner_tether_accel)
			_apply_tether_force(_tethered_target, -dir * pull_force_mag, max_target_tether_accel)

		# Sustained outward force breaks the tether over time.
		if separation_speed > 8.0 and dist > effective_rest * 1.08:
			tether_timer += delta
			if tether_timer >= tether_break_time:
				_break_tether()
				return
		else:
			tether_timer = maxf(tether_timer - delta * 1.5, 0.0)
	elif _active_spear and is_instance_valid(_active_spear):
		# Keep rope visible during spear flight before it attaches.
		_draw_tether_line(_active_spear.global_position)
	elif _tethered_target:
		_break_tether()


func _on_spear_stuck(target: Node, hit_position: Vector3, _hit_normal: Vector3) -> void:
	if target == owner_car:
		if _active_spear and is_instance_valid(_active_spear):
			_active_spear.queue_free()
		_active_spear = null
		return

	if not (target is Node3D):
		if _active_spear and is_instance_valid(_active_spear):
			_active_spear.queue_free()
		_active_spear = null
		return

	_tethered_target = target as Node3D
	_tether_anchor_world = hit_position
	_tether_anchor_local = _tethered_target.to_local(hit_position)
	_tether_rest_length = maxf(owner_car.global_position.distance_to(hit_position), min_tether_length)
	tether_timer = 0.0
	_tether_line.visible = true


func _break_tether() -> void:
	_tethered_target = null
	tether_timer = 0.0
	_tether_rest_length = 0.0
	if _tether_line:
		_tether_line.visible = false
	if _active_spear and is_instance_valid(_active_spear):
		_active_spear.queue_free()
	_active_spear = null


func _draw_tether_line(anchor_world: Vector3) -> void:
	if not _tether_mesh or not owner_car:
		return

	var start: Vector3
	if rope_origin and is_instance_valid(rope_origin):
		start = rope_origin.global_position
	else:
		start = owner_car.global_position + Vector3.UP * 0.55
	var end: Vector3 = anchor_world
	var distance: float = start.distance_to(end)
	var sag_amount: float = distance * chain_sag
	var segments: int = maxi(chain_segments, 3)

	_tether_mesh.clear_surfaces()
	_tether_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(segments):
		var t0: float = float(i) / float(segments)
		var t1: float = float(i + 1) / float(segments)
		_tether_mesh.surface_add_vertex(_curve_point(start, end, t0, sag_amount))
		_tether_mesh.surface_add_vertex(_curve_point(start, end, t1, sag_amount))
	_tether_mesh.surface_end()


func _curve_point(start: Vector3, end: Vector3, t: float, sag_amount: float) -> Vector3:
	var p: Vector3 = start.lerp(end, t)
	var sag_weight: float = sin(PI * t)
	p += Vector3.DOWN * sag_amount * sag_weight
	return p


func _get_anchor_world_position() -> Vector3:
	if _tethered_target and is_instance_valid(_tethered_target):
		return _tethered_target.to_global(_tether_anchor_local)
	return _tether_anchor_world


func _get_target_velocity() -> Vector3:
	if _tethered_target is VehicleBody3D:
		return (_tethered_target as VehicleBody3D).linear_velocity
	if _tethered_target is RigidBody3D:
		return (_tethered_target as RigidBody3D).linear_velocity
	return Vector3.ZERO


func _apply_tether_force(target: Node3D, force: Vector3, max_accel: float) -> void:
	if force.length_squared() <= 0.000001:
		return

	var mass: float = 1.0
	if target is VehicleBody3D:
		mass = maxf((target as VehicleBody3D).mass, 0.1)
	elif target is RigidBody3D:
		mass = maxf((target as RigidBody3D).mass, 0.1)
	else:
		return

	var force_limit: float = mass * maxf(max_accel, 0.0)
	var capped_force: Vector3 = force.limit_length(force_limit)

	if target is VehicleBody3D:
		(target as VehicleBody3D).apply_central_force(capped_force)
	elif target is RigidBody3D:
		(target as RigidBody3D).apply_central_force(capped_force)
