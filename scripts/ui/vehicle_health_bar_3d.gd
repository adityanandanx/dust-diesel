extends Node3D

@export var show_radius_m: float = 25.0
@export var hide_local_player_bar: bool = true
@export var damaged_threshold_ratio: float = 0.999
@export var height_offset: float = 2.2
@export var viewport_size_px: Vector2i = Vector2i(220, 30)
@export var inner_padding_px: int = 2
@export var bar_width: float = 1.6
@export var bar_height: float = 0.14

@onready var bar_sprite: Sprite3D = $Billboard
@onready var bar_viewport: SubViewport = $BarViewport
@onready var canvas_root: Control = $BarViewport/Canvas
@onready var bar_bg: ColorRect = $BarViewport/Canvas/BarBg
@onready var bar_fill: ColorRect = $BarViewport/Canvas/BarFill

var _car: Car = null
var _damage_system: CarDamageSystem = null
var _fill_width_px: float = 0.0


func _ready() -> void:
	_car = get_parent() as Car
	if _car:
		_damage_system = _car.get_node_or_null("DamageSystem") as CarDamageSystem

	position = Vector3(0.0, height_offset, 0.0)
	visible = false

	_setup_viewport_canvas()
	_setup_billboard()
	_set_fill_ratio(1.0)


func _process(_delta: float) -> void:
	if not _is_runtime_valid():
		visible = false
		return

	var local_car: Car = _find_local_player_car()
	if local_car == null:
		visible = false
		return

	if hide_local_player_bar and _car == local_car:
		visible = false
		return

	if _car.global_position.distance_to(local_car.global_position) > show_radius_m:
		visible = false
		return

	var ratio: float = _get_total_health_ratio()
	_set_fill_ratio(ratio)
	_set_fill_color(_color_for_ratio(ratio))

	if ratio >= damaged_threshold_ratio:
		visible = false
		return

	visible = true


func _is_runtime_valid() -> bool:
	if _car == null or _damage_system == null:
		return false
	if not is_instance_valid(_car) or _car.is_queued_for_deletion():
		return false
	if not _car.is_inside_tree():
		return false
	if not _car.is_alive:
		return false
	return true


func _get_total_health_ratio() -> float:
	var wheel_current: float = 0.0
	for value_variant in _damage_system.wheel_hp:
		wheel_current += float(value_variant)

	var current_total: float = _damage_system.engine_hp + _damage_system.chassis_hp + _damage_system.weapon_mount_hp + wheel_current
	var max_total: float = _damage_system.max_engine_hp + _damage_system.max_chassis_hp + _damage_system.max_weapon_hp + (_damage_system.max_wheel_hp * 4.0)
	if max_total <= 0.001:
		return 0.0
	return clampf(current_total / max_total, 0.0, 1.0)


func _find_local_player_car() -> Car:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null

	for node_variant in tree.get_nodes_in_group("cars"):
		var candidate: Car = node_variant as Car
		if candidate == null:
			continue
		if not is_instance_valid(candidate) or candidate.is_queued_for_deletion():
			continue
		if candidate.uses_player_input:
			return candidate
	return null


func _setup_viewport_canvas() -> void:
	var vp_size := Vector2i(maxi(viewport_size_px.x, 8), maxi(viewport_size_px.y, 6))
	bar_viewport.size = vp_size
	bar_viewport.transparent_bg = true
	bar_viewport.disable_3d = true
	bar_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var canvas_size := Vector2(vp_size.x, vp_size.y)
	canvas_root.size = canvas_size

	bar_bg.position = Vector2.ZERO
	bar_bg.size = canvas_size
	bar_bg.color = Color(0.04, 0.04, 0.04, 0.72)

	var inset: int = maxi(inner_padding_px, 0)
	bar_fill.position = Vector2(inset, inset)
	bar_fill.size = Vector2(maxf(float(vp_size.x - inset * 2), 1.0), maxf(float(vp_size.y - inset * 2), 1.0))
	bar_fill.color = Color(0.28, 0.95, 0.44, 0.95)
	_fill_width_px = bar_fill.size.x


func _setup_billboard() -> void:
	bar_sprite.texture = bar_viewport.get_texture()
	bar_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bar_sprite.no_depth_test = true
	bar_sprite.shaded = false
	bar_sprite.double_sided = true
	bar_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var pixel_size := bar_width / maxf(float(bar_viewport.size.x), 1.0)
	bar_sprite.pixel_size = pixel_size

	var natural_height: float = float(bar_viewport.size.y) * pixel_size
	if natural_height > 0.0001:
		bar_sprite.scale = Vector3(1.0, bar_height / natural_height, 1.0)
	else:
		bar_sprite.scale = Vector3.ONE


func _set_fill_ratio(ratio: float) -> void:
	if bar_fill == null or _fill_width_px <= 0.0:
		return

	var clamped_ratio: float = clampf(ratio, 0.0, 1.0)
	bar_fill.size.x = _fill_width_px * clamped_ratio


func _set_fill_color(color: Color) -> void:
	if bar_fill:
		bar_fill.color = color


func _color_for_ratio(ratio: float) -> Color:
	if ratio > 0.6:
		return Color(0.28, 0.95, 0.44, 0.95)
	if ratio > 0.3:
		return Color(0.95, 0.75, 0.2, 0.95)
	return Color(1.0, 0.25, 0.2, 0.95)
