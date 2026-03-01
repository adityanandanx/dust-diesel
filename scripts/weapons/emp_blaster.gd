extends WeaponBase

## EMP Blaster — charged shot that disables target for 3 seconds.

const EMP_LIGHTNING_SHADER: Shader = preload("res://resources/emp_lightning.gdshader")

@export var emp_range: float = 6.0
@export var emp_disable_duration: float = 3.0
@export var emp_growth_time: float = 0.28
@export var sphere_shader_intensity: float = 1.2

@onready var impact_zone_sphere: MeshInstance3D = $ImpactZoneSphere

var _emp_zone_active: bool = false
var _emp_zone_timer: float = 0.0
var _emp_growth_tween: Tween = null
var _emp_end_tween: Tween = null
var _emp_affected: Dictionary = {}


func _ready() -> void:
	super._ready()
	_setup_impact_zone_material()
	impact_zone_sphere.visible = false
	impact_zone_sphere.scale = Vector3.ONE * 0.01


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not _emp_zone_active:
		return
	if not owner_car:
		_end_emp_zone()
		return

	_emp_zone_timer -= delta
	if _emp_zone_timer <= 0.0:
		_end_emp_zone()
		return

	impact_zone_sphere.global_position = owner_car.global_position
	_apply_emp_to_cars_in_zone()


func _do_fire() -> void:
	if not owner_car:
		return
	_start_emp_zone()


func _start_emp_zone() -> void:
	_emp_zone_active = true
	_emp_zone_timer = emp_disable_duration
	_emp_affected.clear()

	impact_zone_sphere.visible = true
	impact_zone_sphere.global_position = owner_car.global_position
	impact_zone_sphere.scale = Vector3.ONE * 0.01

	if _emp_end_tween and _emp_end_tween.is_valid():
		_emp_end_tween.kill()
	if _emp_growth_tween and _emp_growth_tween.is_valid():
		_emp_growth_tween.kill()

	_emp_growth_tween = create_tween()
	_emp_growth_tween.set_trans(Tween.TRANS_EXPO)
	_emp_growth_tween.set_ease(Tween.EASE_OUT)
	_emp_growth_tween.tween_property(impact_zone_sphere, "scale", Vector3.ONE * emp_range, emp_growth_time)

	# Immediate hit check at fire time so nearby cars are stunned instantly.
	_apply_emp_to_cars_in_zone()


func _end_emp_zone() -> void:
	_emp_zone_active = false
	_emp_zone_timer = 0.0
	_emp_affected.clear()

	if _emp_growth_tween and _emp_growth_tween.is_valid():
		_emp_growth_tween.kill()

	if _emp_end_tween and _emp_end_tween.is_valid():
		_emp_end_tween.kill()

	_emp_end_tween = create_tween()
	_emp_end_tween.set_trans(Tween.TRANS_CUBIC)
	_emp_end_tween.set_ease(Tween.EASE_IN)
	_emp_end_tween.tween_property(impact_zone_sphere, "scale", Vector3.ONE * 0.01, 0.18)
	_emp_end_tween.tween_callback(func() -> void:
		impact_zone_sphere.visible = false
	)


func _apply_emp_to_cars_in_zone() -> void:
	if not owner_car:
		return

	var cars: Array[Node] = get_tree().get_nodes_in_group("cars")
	var center: Vector3 = owner_car.global_position
	var radius: float = maxf(impact_zone_sphere.scale.x, 0.01)

	for node in cars:
		if node == owner_car:
			continue
		if not (node is Node3D):
			continue
		if not node.has_method("apply_emp"):
			continue

		var node_id: int = node.get_instance_id()
		if _emp_affected.has(node_id):
			continue

		var car_node: Node3D = node as Node3D
		var distance: float = center.distance_to(car_node.global_position)
		if distance <= radius:
			node.apply_emp(emp_disable_duration)
			_emp_affected[node_id] = true


func _setup_impact_zone_material() -> void:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = EMP_LIGHTNING_SHADER
	mat.set_shader_parameter("seed", Vector2(randf(), randf()))
	mat.set_shader_parameter("speed", 7.0)
	mat.set_shader_parameter("random_scale", 5.4)
	mat.set_shader_parameter("electro_scale", 15.0)
	mat.set_shader_parameter("intensity", sphere_shader_intensity)
	impact_zone_sphere.material_override = mat
