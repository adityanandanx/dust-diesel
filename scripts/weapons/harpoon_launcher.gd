extends WeaponBase

## Harpoon Launcher — fires a chain-linked spear, tethers enemy car.
## Visual tether line drawn between cars while connected.

const HarpoonSpearScene := preload("res://scenes/weapons/HarpoonSpear.tscn")

@export var spear_speed: float = 50.0
@export var spear_damage: float = 15.0
@export var tether_break_time: float = 3.0
@export var yank_force: float = 50000.0
@export var max_tether_length: float = 40.0

var tether_timer: float = 0.0
var _tethered_car: VehicleBody3D = null
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

	# Prepare the tether line visual
	_tether_mesh = ImmediateMesh.new()
	_tether_material = StandardMaterial3D.new()
	_tether_material.albedo_color = Color(0.8, 0.6, 0.2, 1)
	_tether_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tether_material.no_depth_test = true

	_tether_line = MeshInstance3D.new()
	_tether_line.mesh = _tether_mesh
	_tether_line.material_override = _tether_material
	_tether_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tether_line.top_level = true # world-space coordinates
	_tether_line.visible = false


func _do_fire() -> void:
	if not owner_car or _tethered_car:
		return
	var spear = HarpoonSpearScene.instantiate()
	get_tree().current_scene.add_child(spear)
	# Spawn slightly ahead of the car to avoid self-collision
	var forward = owner_car.global_basis.z.normalized()
	spear.global_position = owner_car.global_position + forward * 3.0 + Vector3.UP * 0.5
	spear.launch(forward, owner_car)
	spear.speed = spear_speed
	spear.damage = spear_damage
	spear.hit.connect(_on_spear_hit)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)

	# Add tether line to scene if needed
	if _tether_line and not _tether_line.is_inside_tree():
		if is_inside_tree():
			get_tree().current_scene.add_child(_tether_line)

	if _tethered_car and is_instance_valid(_tethered_car):
		# Update visual tether
		_draw_tether_line()

		# Auto-break if too far
		var dist: float = owner_car.global_position.distance_to(_tethered_car.global_position)
		if dist > max_tether_length:
			_break_tether()
			return

		# Check if target is driving away hard enough to break free
		var pull_dir: Vector3 = (owner_car.global_position - _tethered_car.global_position).normalized()
		var target_vel_along: float = _tethered_car.linear_velocity.dot(-pull_dir)
		if target_vel_along > 5.0:
			tether_timer += delta
			if tether_timer >= tether_break_time:
				_break_tether()
				return
		else:
			tether_timer = maxf(tether_timer - delta, 0.0)

		# Continuous pull toward owner (always active while tethered)
		_tethered_car.apply_central_force(pull_dir * yank_force * delta)

		# Extra yank on fire input
		if Input.is_action_pressed("fire_primary"):
			_tethered_car.apply_central_force(pull_dir * yank_force * 3.0 * delta)
	elif _tethered_car:
		_break_tether()


func _on_spear_hit(target: Node) -> void:
	if target is VehicleBody3D and target != owner_car:
		_tethered_car = target
		tether_timer = 0.0
		_tether_line.visible = true


func _break_tether() -> void:
	_tethered_car = null
	tether_timer = 0.0
	if _tether_line:
		_tether_line.visible = false


func _draw_tether_line() -> void:
	if not _tether_mesh or not owner_car or not _tethered_car:
		return
	_tether_mesh.clear_surfaces()
	_tether_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_tether_mesh.surface_add_vertex(owner_car.global_position + Vector3.UP * 0.5)
	_tether_mesh.surface_add_vertex(_tethered_car.global_position + Vector3.UP * 0.5)
	_tether_mesh.surface_end()
