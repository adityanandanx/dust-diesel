extends Camera3D

## Camera bridge that drives PhantomCamera3D while preserving the old set_target API.

const SHAKE_GROUP := "camera_shake_listener"

@export var phantom_camera_path: NodePath = NodePath("../PlayerPhantomCamera3D")
@export var host_layers: int = 1
@export var active_priority: int = 10

@export_group("Third Person")
@export var follow_offset: Vector3 = Vector3(0.0, 3.0, 0.0)
@export var follow_distance: float = 7.0
@export var spring_length: float = 7.0
@export var vertical_rotation_offset: float = 0.0
@export var collision_mask: int = 1
@export var chase_pitch_degrees: float = -18.0
@export var chase_yaw_offset_degrees: float = 180.0
@export var rotation_smoothing_speed: float = 8.0
@export var movement_yaw_influence: float = 0.65
@export var movement_yaw_min_speed_kmh: float = 8.0
@export var movement_yaw_full_blend_speed_kmh: float = 55.0
@export var reverse_straight_lateral_deadzone_mps: float = 0.6

@export_group("Shake")
@export var shake_enabled: bool = true
@export var shake_layer: int = 1
@export var explosion_max_distance: float = 45.0
@export var explosion_distance_falloff: float = 1.8

@export_group("Weapon Recoil")
@export var recoil_camera_kick_enabled: bool = true
@export var recoil_pitch_kick_min_deg: float = 0.25
@export var recoil_pitch_kick_max_deg: float = 2.8
@export var recoil_pitch_kick_limit_deg: float = 4.0
@export var recoil_pitch_return_speed: float = 10.0

@export_group("Glare Card")
@export var glare_enabled: bool = false
@export var glare_shader_path: String = "res://resources/glare.gdshader"
@export var light_source_path: NodePath = NodePath("")
@export var glare_distance: float = 0.3

var _target: Node3D
var _phantom_camera: Node = null
var _shake_emitter: PhantomCameraNoiseEmitter3D = null
var _shake_noise: PhantomCameraNoise3D = null
var _current_yaw_rad: float = 0.0
var _current_pitch_rad: float = 0.0
var _rotation_initialized: bool = false
var _damage_hp_cache: Dictionary = {}
var _recoil_pitch_offset_deg: float = 0.0
var _glare_mesh_instance: MeshInstance3D = null
var _light_source: DirectionalLight3D = null


func _ready() -> void:
	add_to_group(SHAKE_GROUP)
	_ensure_shake_emitter()
	_setup_glare_card()
	_resolve_light_source()
	_update_glare_light_dir()

	_phantom_camera = get_node_or_null(phantom_camera_path)
	if _phantom_camera == null:
		push_warning("Phantom camera node missing at path: %s" % phantom_camera_path)
		return

	_configure_phantom_camera()
	make_current()
	set_physics_process(false)

func set_target(target: Node3D) -> void:
	_unbind_target_signals(_target)
	_target = target
	if _phantom_camera == null:
		_phantom_camera = get_node_or_null(phantom_camera_path)
		if _phantom_camera == null:
			return
		_configure_phantom_camera()

	_phantom_camera.set("follow_target", _target)
	if _target:
		_phantom_camera.set("priority", active_priority)
		make_current()
		_rotation_initialized = false
		_bind_target_signals(_target)
		set_physics_process(true)
	else:
		_phantom_camera.set("priority", 0)
		_rotation_initialized = false
		set_physics_process(false)


func _configure_phantom_camera() -> void:
	_phantom_camera.set("host_layers", host_layers)
	_phantom_camera.set("follow_mode", 6) # PhantomCamera3D.FollowMode.THIRD_PERSON
	_phantom_camera.set("look_at_mode", 0) # LookAtMode.NONE; third-person handles its own look-at
	_phantom_camera.set("noise_emitter_layer", shake_layer)
	_phantom_camera.set("follow_damping", true)
	_phantom_camera.set("follow_offset", follow_offset)
	_phantom_camera.set("follow_distance", follow_distance)
	_phantom_camera.set("spring_length", spring_length)
	_phantom_camera.set("vertical_rotation_offset", vertical_rotation_offset)
	_phantom_camera.set("collision_mask", collision_mask)
	_phantom_camera.set("priority", 0)


func _ensure_shake_emitter() -> void:
	if not shake_enabled:
		return
	if _shake_emitter and is_instance_valid(_shake_emitter):
		return

	_shake_noise = PhantomCameraNoise3D.new()
	_shake_noise.amplitude = 0.6
	_shake_noise.frequency = 7.0
	_shake_noise.rotational_noise = true
	_shake_noise.positional_noise = false
	_shake_noise.rotational_multiplier_x = 0.8
	_shake_noise.rotational_multiplier_y = 1.0
	_shake_noise.rotational_multiplier_z = 0.2

	_shake_emitter = PhantomCameraNoiseEmitter3D.new()
	_shake_emitter.name = "CameraShakeEmitter"
	_shake_emitter.noise = _shake_noise
	_shake_emitter.noise_emitter_layer = shake_layer
	_shake_emitter.duration = 0.14
	_shake_emitter.growth_time = 0.01
	_shake_emitter.decay_time = 0.14
	add_child(_shake_emitter)


func _bind_target_signals(target: Node3D) -> void:
	if target == null:
		return
	_damage_hp_cache.clear()
	var collision_callable := Callable(self, "_on_target_collision_impact")
	var weapon_callable := Callable(self, "_on_target_weapon_fired")
	var destroyed_callable := Callable(self, "_on_target_destroyed")
	var stalled_callable := Callable(self, "_on_target_stalled")

	if target.has_signal("collision_impact") and not target.is_connected("collision_impact", collision_callable):
		target.connect("collision_impact", collision_callable)
	if target.has_signal("weapon_fired") and not target.is_connected("weapon_fired", weapon_callable):
		target.connect("weapon_fired", weapon_callable)
	if target.has_signal("car_destroyed") and not target.is_connected("car_destroyed", destroyed_callable):
		target.connect("car_destroyed", destroyed_callable)
	if target.has_signal("car_stalled") and not target.is_connected("car_stalled", stalled_callable):
		target.connect("car_stalled", stalled_callable)

	var damage_node: Node = target.get_node_or_null("DamageSystem")
	var damage_callable := Callable(self, "_on_zone_damaged")
	if damage_node and damage_node.has_signal("zone_damaged") and not damage_node.is_connected("zone_damaged", damage_callable):
		damage_node.connect("zone_damaged", damage_callable)


func _unbind_target_signals(target: Node3D) -> void:
	if target == null:
		return
	var collision_callable := Callable(self, "_on_target_collision_impact")
	var weapon_callable := Callable(self, "_on_target_weapon_fired")
	var destroyed_callable := Callable(self, "_on_target_destroyed")
	var stalled_callable := Callable(self, "_on_target_stalled")
	if target.has_signal("collision_impact") and target.is_connected("collision_impact", collision_callable):
		target.disconnect("collision_impact", collision_callable)
	if target.has_signal("weapon_fired") and target.is_connected("weapon_fired", weapon_callable):
		target.disconnect("weapon_fired", weapon_callable)
	if target.has_signal("car_destroyed") and target.is_connected("car_destroyed", destroyed_callable):
		target.disconnect("car_destroyed", destroyed_callable)
	if target.has_signal("car_stalled") and target.is_connected("car_stalled", stalled_callable):
		target.disconnect("car_stalled", stalled_callable)

	var damage_node: Node = target.get_node_or_null("DamageSystem")
	var damage_callable := Callable(self, "_on_zone_damaged")
	if damage_node and damage_node.has_signal("zone_damaged") and damage_node.is_connected("zone_damaged", damage_callable):
		damage_node.disconnect("zone_damaged", damage_callable)


func _emit_shake(amplitude: float, frequency: float, duration: float, growth: float, decay: float) -> void:
	if not shake_enabled:
		return
	if _shake_emitter == null or _shake_noise == null:
		_ensure_shake_emitter()
	if _shake_emitter == null or _shake_noise == null:
		return

	_shake_noise.amplitude = amplitude
	_shake_noise.frequency = frequency
	_shake_emitter.duration = duration
	_shake_emitter.growth_time = growth
	_shake_emitter.decay_time = decay
	_shake_emitter.emit()


func _physics_process(_delta: float) -> void:
	_update_glare_light_dir()

	if _target == null or _phantom_camera == null:
		return

	var target_yaw_rad: float = _get_desired_yaw_rad()
	_recoil_pitch_offset_deg = move_toward(_recoil_pitch_offset_deg, 0.0, recoil_pitch_return_speed * _delta)
	var target_pitch_rad: float = deg_to_rad(chase_pitch_degrees + _recoil_pitch_offset_deg)

	if not _rotation_initialized:
		_current_yaw_rad = target_yaw_rad
		_current_pitch_rad = target_pitch_rad
		_rotation_initialized = true

	var blend_t: float = clampf(rotation_smoothing_speed * _delta, 0.0, 1.0)
	_current_yaw_rad = lerp_angle(_current_yaw_rad, target_yaw_rad, blend_t)
	_current_pitch_rad = lerpf(_current_pitch_rad, target_pitch_rad, blend_t)

	var chase_rotation := Vector3(rad_to_deg(_current_pitch_rad), rad_to_deg(_current_yaw_rad), 0.0)
	_phantom_camera.call("set_third_person_rotation_degrees", chase_rotation)


func _setup_glare_card() -> void:
	if not glare_enabled: 
		return
	if _glare_mesh_instance and is_instance_valid(_glare_mesh_instance):
		return

	var glare_shader: Shader = load(glare_shader_path)
	if glare_shader == null:
		push_warning("Could not load glare shader at path: %s" % glare_shader_path)
		return

	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)

	var material := ShaderMaterial.new()
	material.shader = glare_shader

	_glare_mesh_instance = MeshInstance3D.new()
	_glare_mesh_instance.name = "GlareCard"
	_glare_mesh_instance.mesh = quad
	_glare_mesh_instance.material_override = material
	_glare_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glare_mesh_instance.position = Vector3(0.0, 0.0, -absf(glare_distance))
	add_child(_glare_mesh_instance)


func _resolve_light_source() -> void:
	_light_source = null
	if light_source_path != NodePath(""):
		var explicit_light := get_node_or_null(light_source_path)
		if explicit_light is DirectionalLight3D:
			_light_source = explicit_light
			return
		if explicit_light != null:
			push_warning("Node at light_source_path is not a DirectionalLight3D: %s" % light_source_path)

	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		scene_root = get_tree().root
	_light_source = _find_directional_light(scene_root)
	if _light_source == null:
		push_warning("No DirectionalLight3D found for glare light_world_dir.")


func _find_directional_light(root: Node) -> DirectionalLight3D:
	if root is DirectionalLight3D:
		return root
	for child in root.get_children():
		var found: DirectionalLight3D = _find_directional_light(child)
		if found:
			return found
	return null


func _update_glare_light_dir() -> void:
	if not glare_enabled: 
		return
	if _glare_mesh_instance == null or not is_instance_valid(_glare_mesh_instance):
		return
	if _light_source == null or not is_instance_valid(_light_source):
		_resolve_light_source()
	if _light_source == null:
		return
	_glare_mesh_instance.set_instance_shader_parameter("light_world_dir", -_light_source.global_transform.basis.z)


func _get_desired_yaw_rad() -> float:
	var heading_yaw_rad: float = _target.global_rotation.y
	var movement_yaw_rad: float = heading_yaw_rad
	var speed_kmh: float = 0.0
	var reverse_straight: bool = false

	var vel_value: Variant = _target.get("linear_velocity")
	if vel_value is Vector3:
		var vel: Vector3 = vel_value
		var horizontal: Vector3 = Vector3(vel.x, 0.0, vel.z)
		speed_kmh = horizontal.length() * 3.6

		var local_vel: Vector3 = _target.global_basis.inverse() * vel
		# Prevent left/right camera flipping when reversing nearly straight.
		reverse_straight = local_vel.z < -0.1 and abs(local_vel.x) <= reverse_straight_lateral_deadzone_mps
		if horizontal.length_squared() > 0.0001:
			movement_yaw_rad = atan2(horizontal.x, horizontal.z)

	var influence_t: float = clampf((speed_kmh - movement_yaw_min_speed_kmh) / maxf(movement_yaw_full_blend_speed_kmh - movement_yaw_min_speed_kmh, 0.001), 0.0, 1.0)
	var move_blend: float = 0.0
	if not reverse_straight:
		move_blend = clampf(influence_t * movement_yaw_influence, 0.0, 1.0)
	var base_yaw_rad: float = lerp_angle(heading_yaw_rad, movement_yaw_rad, move_blend)
	return base_yaw_rad + deg_to_rad(chase_yaw_offset_degrees)


func _on_zone_damaged(zone: String, current_hp: float, max_hp: float) -> void:
	if max_hp <= 0.0:
		return
	var prev_hp: float = max_hp
	if zone in _damage_hp_cache:
		prev_hp = float(_damage_hp_cache[zone])
	_damage_hp_cache[zone] = current_hp

	var delta: float = maxf(prev_hp - current_hp, 0.0)
	if delta <= 0.01:
		return

	var ratio: float = clampf(delta / max_hp, 0.0, 1.0)
	var amp: float = lerpf(0.55, 1.4, ratio)
	_emit_shake(amp, 9.0, 0.12, 0.0, 0.16)


func _on_target_collision_impact(impact_speed: float) -> void:
	var t: float = clampf(impact_speed / 40.0, 0.0, 1.0)
	_emit_shake(lerpf(0.6, 2.8, t), lerpf(8.0, 15.0, t), lerpf(0.08, 0.2, t), 0.0, lerpf(0.1, 0.28, t))


func _on_target_weapon_fired(_mount_slot: int, intensity: float) -> void:
	var t: float = clampf(intensity, 0.0, 1.5)
	_emit_shake(0.35 + t * 0.45, 11.0, 0.07, 0.0, 0.09)
	if recoil_camera_kick_enabled:
		var kick: float = lerpf(recoil_pitch_kick_min_deg, recoil_pitch_kick_max_deg, clampf(t / 1.5, 0.0, 1.0))
		_recoil_pitch_offset_deg = clampf(_recoil_pitch_offset_deg - kick, -recoil_pitch_kick_limit_deg, recoil_pitch_kick_limit_deg)


func _on_target_destroyed(_car: Node) -> void:
	_emit_shake(3.0, 9.0, 0.25, 0.0, 0.45)


func _on_target_stalled(_car: Node) -> void:
	_emit_shake(1.1, 7.5, 0.12, 0.0, 0.2)


func camera_shake_explosion(world_position: Vector3, strength_scale: float = 1.0) -> void:
	if not shake_enabled:
		return

	var listener_pos: Vector3 = global_position
	if _target:
		listener_pos = _target.global_position

	var distance: float = world_position.distance_to(listener_pos)
	var normalized: float = clampf(1.0 - distance / maxf(explosion_max_distance, 0.001), 0.0, 1.0)
	if normalized <= 0.0:
		return

	var falloff: float = pow(normalized, explosion_distance_falloff)
	var strength: float = maxf(strength_scale, 0.25) * falloff
	_emit_shake(1.2 + strength * 3.0, 7.5 + strength * 3.0, 0.16 + strength * 0.12, 0.0, 0.25 + strength * 0.2)
