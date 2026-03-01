extends Control

## In-game HUD — speed, fuel/boost, dual weapons, powerups, damage, and vehicle part health.

signal match_end_restart_requested()
signal match_end_rejoin_requested()
signal match_end_back_to_menu_requested()
signal match_end_settings_changed(game_mode: String, match_time_seconds: int, map_id: String, bot_count: int)

const MATCH_END_DIALOG_SCENE: PackedScene = preload("res://scenes/ui/MatchEndDialog.tscn")

@export_group("Debug")
@export var debug_overlay_enabled: bool = false
@export var debug_overlay_position: Vector2 = Vector2(16.0, 16.0)
@export var debug_overlay_font_size: int = 14

@export_group("Minimap")
@export var minimap_world_radius: float = 90.0
@export var minimap_max_dots: int = 16
@export var minimap_camera_height: float = 260.0
@export var minimap_rotation_lerp: float = 10.0

@onready var speed_label: Label = %SpeedValue
@onready var fuel_bar: ProgressBar = %FuelBar
@onready var fuel_label: Label = %FuelLabel
@onready var boost_bar: ProgressBar = %BoostBar
@onready var log_feed_container: VBoxContainer = %KillFeed
@onready var powerup_list: VBoxContainer = %PowerupList
@onready var minimap_canvas: Control = %MinimapCanvas
@onready var minimap_view: TextureRect = %MinimapView
@onready var minimap_subviewport: SubViewport = %MinimapSubViewport
@onready var minimap_camera: Camera3D = %MinimapCamera

@onready var damage_left: ColorRect = %Left
@onready var damage_right: ColorRect = %Right
@onready var damage_top: ColorRect = %Top
@onready var damage_bottom: ColorRect = %Bottom
@onready var emp_overlay: ColorRect = %EMPOverlay

@onready var engine_icon: TextureRect = %EngineIcon
@onready var chassis_icon: TextureRect = %ChassisIcon
@onready var weapon_mount_icon: TextureRect = %WeaponMountIcon
@onready var wheel_fl_icon: TextureRect = %WheelFLIcon
@onready var wheel_fr_icon: TextureRect = %WheelFRIcon
@onready var wheel_rl_icon: TextureRect = %WheelRLIcon
@onready var wheel_rr_icon: TextureRect = %WheelRRIcon
@onready var primary_marker: TextureRect = %PrimaryWeaponMarker
@onready var secondary_marker: TextureRect = %SecondaryWeaponMarker

@onready var engine_value: Label = %EngineValue
@onready var chassis_value: Label = %ChassisValue
@onready var wheel_value: Label = %WheelValue
@onready var weapon_mount_value: Label = %WeaponMountValue

@onready var primary_name: Label = %PrimaryName
@onready var primary_icon: TextureRect = %PrimaryIcon
@onready var primary_ammo: Label = %PrimaryAmmo
@onready var primary_heat: ProgressBar = %PrimaryHeat
@onready var primary_status: Label = %PrimaryStatus
@onready var primary_cooldown: RadialCooldown = %PrimaryCooldown

@onready var secondary_name: Label = %SecondaryName
@onready var secondary_icon: TextureRect = %SecondaryIcon
@onready var secondary_ammo: Label = %SecondaryAmmo
@onready var secondary_heat: ProgressBar = %SecondaryHeat
@onready var secondary_status: Label = %SecondaryStatus
@onready var secondary_cooldown: RadialCooldown = %SecondaryCooldown

var _bound_car: Car = null
var _damage_flash_timers: Dictionary = {}
var _debug_overlay_label: Label = null
var _powerup_rows: Dictionary = {}
var _minimap_dots: Dictionary = {}
var _minimap_heading_dir: Vector2 = Vector2(0.0, -1.0)
var _minimap_env_applied: bool = false
var _respawn_countdown_label: Label = null
var _match_timer_label: Label = null
var _match_result_overlay = null

var _part_textures: Dictionary = {}
var _weapon_textures: Dictionary = {}
var _powerup_textures: Dictionary = {}
var _crosshair_root: Control = null


func _ready() -> void:
	add_to_group("hud_log_feed")
	_ensure_debug_overlay_label()
	_ensure_crosshair()
	_ensure_respawn_countdown_label()
	_ensure_match_timer_label()
	_ensure_match_result_overlay()
	_set_debug_overlay_visible(debug_overlay_enabled)
	_build_placeholder_textures()
	_apply_static_placeholder_textures()
	_setup_minimap_view()
	if not minimap_canvas.resized.is_connected(_on_minimap_canvas_resized):
		minimap_canvas.resized.connect(_on_minimap_canvas_resized)
	call_deferred("_ensure_minimap_environment")


func bind_car(car: Car) -> void:
	if _bound_car == car:
		return
	_disconnect_bound_car()
	_bound_car = car
	if car == null:
		return

	if car.fuel_system:
		car.fuel_system.fuel_changed.connect(_on_fuel_changed)
		car.fuel_system.fuel_critical.connect(_on_fuel_critical)
		_on_fuel_changed(car.fuel_system.fuel, car.fuel_system.max_fuel)
	if car.damage_system:
		car.damage_system.zone_damaged.connect(_on_zone_damaged)

	car.powerup_started.connect(_on_powerup_started)
	car.powerup_ended.connect(_on_powerup_ended)
	_sync_powerup_rows()


func _process(delta: float) -> void:
	_set_debug_overlay_visible(debug_overlay_enabled)
	_update_debug_overlay()

	if _bound_car == null:
		return

	speed_label.text = "%d km/h" % int(_bound_car.current_speed_kmh)
	boost_bar.value = _bound_car.boost_meter
	boost_bar.max_value = _bound_car.boost_meter_max

	_update_weapon_panels()
	_update_vehicle_health_panel()
	_update_powerup_rows()
	_ensure_minimap_environment()
	_update_minimap_camera(delta)
	_update_minimap()

	emp_overlay.visible = _bound_car.is_emp_disabled

	for dir_key_variant in _damage_flash_timers.keys():
		var dir_key: String = str(dir_key_variant)
		_damage_flash_timers[dir_key] = float(_damage_flash_timers[dir_key]) - delta
		var panel: ColorRect = _get_damage_panel(dir_key)
		if panel:
			panel.modulate.a = clampf(float(_damage_flash_timers[dir_key]) / 0.5, 0.0, 0.8)
		if float(_damage_flash_timers[dir_key]) <= 0.0:
			_damage_flash_timers.erase(dir_key)


func add_log_entry(text: String, color: Color = Color(1, 0.85, 0.6)) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color)
	log_feed_container.add_child(label)

	var tween := create_tween()
	tween.tween_interval(4.0)
	tween.tween_property(label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(label.queue_free)

	while log_feed_container.get_child_count() > 6:
		log_feed_container.get_child(0).queue_free()


func add_kill_feed_entry(text: String) -> void:
	# Backward-compatible alias for older callers.
	add_log_entry(text, Color(1, 0.74, 0.52))


func add_elimination_log(victim_name: String, cause: String, killer_name: String = "") -> void:
	var killer_label: String = killer_name.strip_edges()
	if killer_label.is_empty():
		killer_label = "Unknown"
	var msg: String = "[KILL] %s -> %s (%s)" % [killer_label, victim_name, cause]
	add_log_entry(msg, Color(1.0, 0.72, 0.52))


func add_pickup_log(car_name: String, pickup_kind: String, detail: String = "") -> void:
	var detail_text: String = detail.strip_edges()
	var kind_text: String = pickup_kind.strip_edges().to_upper()
	var msg: String = "[PICKUP/%s] %s" % [kind_text, car_name]
	if not detail_text.is_empty():
		msg += " collected %s" % detail_text
	add_log_entry(msg, Color(0.72, 0.95, 0.7))


func show_respawn_countdown(seconds_left: int) -> void:
	_ensure_respawn_countdown_label()
	if _respawn_countdown_label == null:
		return
	var secs: int = maxi(seconds_left, 0)
	_respawn_countdown_label.text = "RESPAWN IN %d" % secs
	_respawn_countdown_label.visible = true


func hide_respawn_countdown() -> void:
	if _respawn_countdown_label:
		_respawn_countdown_label.visible = false


func show_match_timer(seconds_left: int) -> void:
	_ensure_match_timer_label()
	if _match_timer_label == null:
		return
	var secs: int = maxi(seconds_left, 0)
	var mins: int = int(secs / 60.0)
	var rem: int = secs % 60
	_match_timer_label.text = "FFA %02d:%02d" % [mins, rem]
	_match_timer_label.visible = true


func hide_match_timer() -> void:
	if _match_timer_label:
		_match_timer_label.visible = false


func show_match_results(winner_name: String, kill_counts: Dictionary) -> void:
	_ensure_match_result_overlay()
	if _match_result_overlay == null:
		return
	_match_result_overlay.show_results(winner_name, kill_counts)


func hide_match_results() -> void:
	if _match_result_overlay:
		_match_result_overlay.hide_results()


func configure_match_end_menu(is_host: bool, settings: Dictionary) -> void:
	_ensure_match_result_overlay()
	if _match_result_overlay == null:
		return
	_match_result_overlay.configure_menu(is_host, settings)


func set_match_end_waiting(waiting: bool, is_host: bool = false) -> void:
	if _match_result_overlay == null:
		return
	_match_result_overlay.set_waiting(waiting, is_host)


func _setup_minimap_view() -> void:
	if minimap_view and minimap_subviewport:
		minimap_view.texture = minimap_subviewport.get_texture()
		minimap_view.material = _make_minimap_circle_material()
		minimap_subviewport.world_3d = get_viewport().world_3d
		minimap_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_resize_minimap_viewport()
	if minimap_camera:
		minimap_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		minimap_camera.size = minimap_world_radius * 2.0
		_ensure_minimap_environment()


func _ensure_crosshair() -> void:
	if _crosshair_root and is_instance_valid(_crosshair_root):
		return

	var root := Control.new()
	root.name = "Crosshair"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.position = Vector2.ZERO
	root.size = Vector2(32.0, 32.0)
	root.pivot_offset = root.size * 0.5
	add_child(root)

	# Four ticks + center dot to keep the target clear on bright scenes.
	var col: Color = Color(1.0, 0.9, 0.65, 0.95)
	var thickness: float = 2.0
	var tick_len: float = 6.0
	var gap: float = 4.0

	var top := ColorRect.new()
	top.color = col
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.position = Vector2(16.0 - thickness * 0.5, 16.0 - gap - tick_len)
	top.size = Vector2(thickness, tick_len)
	root.add_child(top)

	var bottom := ColorRect.new()
	bottom.color = col
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.position = Vector2(16.0 - thickness * 0.5, 16.0 + gap)
	bottom.size = Vector2(thickness, tick_len)
	root.add_child(bottom)

	var left := ColorRect.new()
	left.color = col
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.position = Vector2(16.0 - gap - tick_len, 16.0 - thickness * 0.5)
	left.size = Vector2(tick_len, thickness)
	root.add_child(left)

	var right := ColorRect.new()
	right.color = col
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.position = Vector2(16.0 + gap, 16.0 - thickness * 0.5)
	right.size = Vector2(tick_len, thickness)
	root.add_child(right)

	var dot := ColorRect.new()
	dot.color = Color(1.0, 0.98, 0.9, 0.95)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.position = Vector2(15.0, 15.0)
	dot.size = Vector2(2.0, 2.0)
	root.add_child(dot)

	_crosshair_root = root


func _ensure_minimap_environment() -> void:
	if _minimap_env_applied:
		return
	if minimap_camera == null:
		return
	var world: World3D = get_viewport().world_3d
	if world == null:
		return

	var source_env: Environment = world.environment
	var minimap_env: Environment
	if source_env:
		minimap_env = source_env.duplicate() as Environment
	else:
		minimap_env = Environment.new()
	if minimap_env == null:
		return
	minimap_env.fog_enabled = false
	minimap_env.volumetric_fog_enabled = false
	# Keep a readable minimap even when source environment is unavailable.
	if not source_env:
		minimap_env.background_mode = Environment.BG_COLOR
		minimap_env.background_color = Color(0.06, 0.08, 0.1, 1.0)
		minimap_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		minimap_env.ambient_light_color = Color(0.9, 0.9, 0.9, 1.0)
		minimap_env.ambient_light_energy = 1.0
	minimap_camera.environment = minimap_env
	_minimap_env_applied = true


func _make_minimap_circle_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float d = length(uv);
	if (d > 0.5) {
		discard;
	}
	vec4 src = texture(TEXTURE, UV);
	float ring = smoothstep(0.47, 0.5, d);
	vec3 ring_color = vec3(1.0, 0.82, 0.45);
	COLOR = vec4(mix(src.rgb, ring_color, ring), src.a);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat


func _on_minimap_canvas_resized() -> void:
	_resize_minimap_viewport()


func _resize_minimap_viewport() -> void:
	if minimap_subviewport == null or minimap_canvas == null:
		return
	var side_px: int = maxi(96, int(minf(minimap_canvas.size.x, minimap_canvas.size.y)))
	minimap_subviewport.size = Vector2i(side_px, side_px)


func _update_minimap_camera(delta: float) -> void:
	if minimap_camera == null or _bound_car == null:
		return

	var vel: Vector2 = Vector2(_bound_car.linear_velocity.x, _bound_car.linear_velocity.z)
	if vel.length_squared() > 1.0:
		var target_dir := vel.normalized()
		var t: float = clampf(delta * minimap_rotation_lerp, 0.0, 1.0)
		_minimap_heading_dir = _minimap_heading_dir.lerp(target_dir, t).normalized()
	else:
		var car_forward: Vector2 = Vector2(_bound_car.transform.basis.z.x, _bound_car.transform.basis.z.z)
		if car_forward.length_squared() > 0.001:
			_minimap_heading_dir = car_forward.normalized()

	var target: Vector3 = _bound_car.global_position
	var cam_pos: Vector3 = target + Vector3(0.0, minimap_camera_height, 0.0)
	var up_hint: Vector3 = Vector3(_minimap_heading_dir.x, 0.0, _minimap_heading_dir.y)
	if up_hint.length_squared() < 0.001:
		up_hint = Vector3.FORWARD

	minimap_camera.size = minimap_world_radius * 2.0
	minimap_camera.look_at_from_position(cam_pos, target, up_hint)


func _update_minimap() -> void:
	if minimap_canvas == null:
		return
	if _bound_car == null:
		_clear_minimap_dots()
		return
	if minimap_camera == null or minimap_subviewport == null:
		return

	var canvas_size: Vector2 = minimap_canvas.size
	if canvas_size.x <= 1.0 or canvas_size.y <= 1.0:
		return

	var center_px: Vector2 = canvas_size * 0.5
	var map_radius_px: float = minf(canvas_size.x, canvas_size.y) * 0.5 - 6.0
	var vp_size: Vector2 = Vector2(minimap_subviewport.size)
	if vp_size.x <= 1.0 or vp_size.y <= 1.0:
		return

	var live_ids: Dictionary = {}
	var dots_used: int = 0
	for node in get_tree().get_nodes_in_group("cars"):
		if dots_used >= minimap_max_dots:
			break
		if not (node is Car):
			continue

		var car: Car = node
		if not is_instance_valid(car) or car.is_queued_for_deletion() or not car.is_alive:
			continue
		if not _is_player_car_for_minimap(car):
			continue

		var id: int = car.get_instance_id()
		live_ids[id] = true
		dots_used += 1

		var dot: ColorRect = _ensure_minimap_dot(id)
		var projected: Vector2 = minimap_camera.unproject_position(car.global_position)
		var uv: Vector2 = Vector2(projected.x / vp_size.x, projected.y / vp_size.y)
		uv.x = clampf(uv.x, 0.0, 1.0)
		uv.y = clampf(uv.y, 0.0, 1.0)
		var local_px: Vector2 = Vector2(uv.x * canvas_size.x, uv.y * canvas_size.y)
		var offset_px: Vector2 = local_px - center_px
		if offset_px.length() > map_radius_px:
			offset_px = offset_px.normalized() * map_radius_px

		var dot_size: float = 8.0 if car == _bound_car else 6.0
		dot.size = Vector2(dot_size, dot_size)
		dot.position = center_px + offset_px - (dot.size * 0.5)
		dot.color = Color(0.25, 1.0, 0.92, 1.0) if car == _bound_car else Color(1.0, 0.45, 0.28, 1.0)

	for id_variant in _minimap_dots.keys():
		var dot_id: int = int(id_variant)
		if live_ids.has(dot_id):
			continue
		var stale_dot: ColorRect = _minimap_dots[dot_id]
		if is_instance_valid(stale_dot):
			stale_dot.queue_free()
		_minimap_dots.erase(dot_id)


func _is_player_car_for_minimap(car: Car) -> bool:
	if NakamaManager.current_match:
		return car.is_player or not car.network_id.is_empty()
	return car.is_player


func _ensure_minimap_dot(dot_id: int) -> ColorRect:
	if _minimap_dots.has(dot_id):
		var existing: ColorRect = _minimap_dots[dot_id]
		if is_instance_valid(existing):
			return existing

	var dot := ColorRect.new()
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.color = Color(1.0, 0.45, 0.28, 1.0)
	minimap_canvas.add_child(dot)
	_minimap_dots[dot_id] = dot
	return dot


func _clear_minimap_dots() -> void:
	for dot_variant in _minimap_dots.values():
		var dot: ColorRect = dot_variant
		if is_instance_valid(dot):
			dot.queue_free()
	_minimap_dots.clear()


func _update_weapon_panels() -> void:
	var primary: WeaponBase = _bound_car.primary_weapon
	var secondary: WeaponBase = _bound_car.secondary_weapon
	_update_weapon_slot(primary, true)
	_update_weapon_slot(secondary, false)

	primary_marker.texture = _get_weapon_texture(primary)
	secondary_marker.texture = _get_weapon_texture(secondary)
	primary_marker.modulate = Color(1.0, 1.0, 1.0, 1.0 if primary else 0.35)
	secondary_marker.modulate = Color(1.0, 1.0, 1.0, 1.0 if secondary else 0.35)


func _update_weapon_slot(weapon: WeaponBase, is_primary: bool) -> void:
	var name_label: Label = primary_name if is_primary else secondary_name
	var icon: TextureRect = primary_icon if is_primary else secondary_icon
	var ammo_label: Label = primary_ammo if is_primary else secondary_ammo
	var heat_bar: ProgressBar = primary_heat if is_primary else secondary_heat
	var status_label: Label = primary_status if is_primary else secondary_status
	var cooldown: RadialCooldown = primary_cooldown if is_primary else secondary_cooldown

	if weapon == null:
		name_label.text = "PRIMARY" if is_primary else "SECONDARY"
		icon.texture = _weapon_textures.get("NONE")
		ammo_label.text = "NO WEAPON"
		heat_bar.visible = false
		status_label.text = ""
		cooldown.ratio = 0.0
		return

	name_label.text = weapon.name.to_upper()
	icon.texture = _get_weapon_texture(weapon)
	ammo_label.text = "%d/%d" % [weapon.ammo, weapon.max_ammo] if weapon.max_ammo > 0 else "INF"

	heat_bar.visible = weapon.reload_type == weapon.ReloadType.OVERHEAT
	if heat_bar.visible:
		heat_bar.max_value = weapon.max_heat
		heat_bar.value = weapon.heat

	cooldown.ratio = weapon.get_fire_cooldown_ratio()

	if weapon.is_overheated:
		status_label.text = "OVERHEATED"
		status_label.add_theme_color_override("font_color", Color(1, 0.3, 0.1))
	elif weapon.is_reloading:
		status_label.text = "RELOADING"
		status_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	elif weapon.get_fire_cooldown_ratio() > 0.0:
		status_label.text = "COOLDOWN"
		status_label.add_theme_color_override("font_color", Color(0.7, 0.82, 1.0))
	else:
		status_label.text = "READY"
		status_label.add_theme_color_override("font_color", Color(0.3, 1, 0.4))


func _update_vehicle_health_panel() -> void:
	if _bound_car.damage_system == null:
		return

	var dmg: CarDamageSystem = _bound_car.damage_system
	var engine_hp: Dictionary = dmg.get_zone_health("engine")
	var chassis_hp: Dictionary = dmg.get_zone_health("chassis")
	var weapon_hp: Dictionary = dmg.get_zone_health("weapon")
	var wheel_0: Dictionary = dmg.get_zone_health("wheel_0")
	var wheel_1: Dictionary = dmg.get_zone_health("wheel_1")
	var wheel_2: Dictionary = dmg.get_zone_health("wheel_2")
	var wheel_3: Dictionary = dmg.get_zone_health("wheel_3")

	_update_zone_visual(engine_icon, engine_hp)
	_update_zone_visual(chassis_icon, chassis_hp)
	_update_zone_visual(weapon_mount_icon, weapon_hp)
	_update_zone_visual(wheel_fl_icon, wheel_0)
	_update_zone_visual(wheel_fr_icon, wheel_1)
	_update_zone_visual(wheel_rl_icon, wheel_2)
	_update_zone_visual(wheel_rr_icon, wheel_3)

	engine_value.text = "Engine %d/%d" % [int(engine_hp["current"]), int(engine_hp["max"])]
	chassis_value.text = "Chassis %d/%d" % [int(chassis_hp["current"]), int(chassis_hp["max"])]
	weapon_mount_value.text = "Weapon %d/%d" % [int(weapon_hp["current"]), int(weapon_hp["max"])]

	var wheel_current: float = float(wheel_0["current"]) + float(wheel_1["current"]) + float(wheel_2["current"]) + float(wheel_3["current"])
	var wheel_max: float = float(wheel_0["max"]) + float(wheel_1["max"]) + float(wheel_2["max"]) + float(wheel_3["max"])
	wheel_value.text = "Wheels %d/%d" % [int(wheel_current), int(wheel_max)]


func _update_zone_visual(icon: TextureRect, health: Dictionary) -> void:
	var current: float = float(health.get("current", 0.0))
	var max_hp: float = maxf(float(health.get("max", 1.0)), 0.001)
	var ratio: float = clampf(current / max_hp, 0.0, 1.0)
	icon.modulate = _severity_color(ratio)


func _severity_color(ratio: float) -> Color:
	if ratio > 0.6:
		return Color(0.28, 0.95, 0.44, 1.0)
	if ratio > 0.3:
		return Color(0.95, 0.75, 0.2, 1.0)
	return Color(1.0, 0.25, 0.2, 1.0)


func _on_fuel_changed(current: float, max_fuel: float) -> void:
	fuel_bar.value = current
	fuel_bar.max_value = max_fuel
	fuel_label.text = "FUEL %d%%" % int((current / maxf(max_fuel, 0.001)) * 100.0)


func _on_fuel_critical() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(fuel_bar, "modulate", Color.RED, 0.3)
	tween.tween_property(fuel_bar, "modulate", Color.WHITE, 0.3)


func _on_zone_damaged(zone: String, _current_hp: float, _max_hp: float) -> void:
	var dir_key := "top"
	if zone == "engine":
		dir_key = "top"
	elif zone.begins_with("wheel"):
		dir_key = "left" if zone.ends_with("0") or zone.ends_with("2") else "right"
	else:
		dir_key = "bottom"

	_damage_flash_timers[dir_key] = 0.5
	var panel := _get_damage_panel(dir_key)
	if panel:
		panel.modulate.a = 0.8


func _get_damage_panel(dir_key: String) -> ColorRect:
	match dir_key:
		"left": return damage_left
		"right": return damage_right
		"top": return damage_top
		"bottom": return damage_bottom
	return null


func _on_powerup_started(_id: String, _duration: float) -> void:
	_sync_powerup_rows()


func _on_powerup_ended(id: String) -> void:
	if _powerup_rows.has(id):
		(_powerup_rows[id] as HBoxContainer).queue_free()
		_powerup_rows.erase(id)


func _sync_powerup_rows() -> void:
	if _bound_car == null:
		return
	for entry_variant in _bound_car.get_active_powerups():
		var entry: Dictionary = entry_variant
		var id: String = str(entry.get("id", ""))
		if id.is_empty():
			continue
		if not _powerup_rows.has(id):
			_powerup_rows[id] = _create_powerup_row(id)


func _update_powerup_rows() -> void:
	if _bound_car == null:
		return
	var live_ids: Dictionary = {}
	for entry_variant in _bound_car.get_active_powerups():
		var entry: Dictionary = entry_variant
		var id: String = str(entry.get("id", ""))
		if id.is_empty():
			continue
		live_ids[id] = true
		if not _powerup_rows.has(id):
			_powerup_rows[id] = _create_powerup_row(id)

		var row: HBoxContainer = _powerup_rows[id]
		var time_label: Label = row.get_node("Text") as Label
		var bar: ProgressBar = row.get_node("Bar") as ProgressBar
		var remaining: float = float(entry.get("remaining", 0.0))
		var duration: float = maxf(float(entry.get("duration", 1.0)), 0.001)
		time_label.text = "%s  %.1fs" % [_pretty_powerup_name(id), remaining]
		bar.max_value = duration
		bar.value = remaining

	for key_variant in _powerup_rows.keys():
		var key: String = str(key_variant)
		if live_ids.has(key):
			continue
		var stale_row: HBoxContainer = _powerup_rows[key]
		stale_row.queue_free()
		_powerup_rows.erase(key)


func _create_powerup_row(id: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(320, 26)
	row.add_theme_constant_override("separation", 6)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(22, 22)
	icon.texture = _powerup_textures.get(id, _powerup_textures.get("DEFAULT"))
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)

	var text := Label.new()
	text.name = "Text"
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.text = _pretty_powerup_name(id)
	row.add_child(text)

	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.custom_minimum_size = Vector2(110, 12)
	bar.add_theme_stylebox_override("background", _make_stylebox(Color(0.12, 0.11, 0.1, 0.9)))
	bar.add_theme_stylebox_override("fill", _make_stylebox(Color(0.2, 0.8, 0.45, 1.0)))
	bar.show_percentage = false
	row.add_child(bar)

	powerup_list.add_child(row)
	return row


func _pretty_powerup_name(id: String) -> String:
	var words: PackedStringArray = id.to_lower().split("_")
	for i in range(words.size()):
		words[i] = words[i].capitalize()
	return " ".join(words)


func _get_weapon_texture(weapon: WeaponBase) -> Texture2D:
	if weapon == null:
		return _weapon_textures.get("NONE")
	return _weapon_textures.get(weapon.name.to_upper(), _weapon_textures.get("DEFAULT"))


func _build_placeholder_textures() -> void:
	_part_textures = {
		"CHASSIS": _make_placeholder_texture(Color(0.48, 0.35, 0.28), Color(0.28, 0.2, 0.16), Vector2i(120, 60)),
		"ENGINE": _make_placeholder_texture(Color(0.7, 0.25, 0.2), Color(0.42, 0.15, 0.12), Vector2i(90, 40)),
		"WEAPON_MOUNT": _make_placeholder_texture(Color(0.86, 0.67, 0.2), Color(0.5, 0.36, 0.12), Vector2i(70, 32)),
		"WHEEL": _make_placeholder_texture(Color(0.3, 0.3, 0.3), Color(0.12, 0.12, 0.12), Vector2i(30, 30)),
	}

	_weapon_textures = {
		"NONE": _make_placeholder_texture(Color(0.2, 0.2, 0.2), Color(0.1, 0.1, 0.1), Vector2i(60, 60)),
		"DEFAULT": _make_placeholder_texture(Color(0.35, 0.35, 0.35), Color(0.15, 0.15, 0.15), Vector2i(60, 60)),
		"EMPBLASTER": _make_placeholder_texture(Color(0.2, 0.58, 1.0), Color(0.08, 0.2, 0.42), Vector2i(60, 60)),
		"RIVETCANNON": _make_placeholder_texture(Color(0.9, 0.58, 0.2), Color(0.42, 0.24, 0.08), Vector2i(60, 60)),
		"SCRAPCANNON": _make_placeholder_texture(Color(0.72, 0.4, 0.2), Color(0.35, 0.2, 0.1), Vector2i(60, 60)),
		"HARPOONLAUNCHER": _make_placeholder_texture(Color(0.95, 0.82, 0.36), Color(0.48, 0.36, 0.15), Vector2i(60, 60)),
		"FLAMEPROJECTOR": _make_placeholder_texture(Color(1.0, 0.35, 0.1), Color(0.5, 0.12, 0.05), Vector2i(60, 60)),
		"MINELAYER": _make_placeholder_texture(Color(0.52, 0.45, 0.35), Color(0.26, 0.2, 0.14), Vector2i(60, 60)),
		"OILSLICK": _make_placeholder_texture(Color(0.12, 0.12, 0.12), Color(0.02, 0.02, 0.02), Vector2i(60, 60)),
	}

	_powerup_textures = {
		"DEFAULT": _make_placeholder_texture(Color(0.3, 0.7, 0.5), Color(0.12, 0.28, 0.2), Vector2i(24, 24)),
		"NITRO_SURGE": _make_placeholder_texture(Color(0.2, 0.7, 1.0), Color(0.08, 0.24, 0.4), Vector2i(24, 24)),
		"ARMOR_PLATING": _make_placeholder_texture(Color(0.6, 0.9, 0.65), Color(0.2, 0.36, 0.24), Vector2i(24, 24)),
		"FUEL_CAN": _make_placeholder_texture(Color(0.22, 0.85, 0.35), Color(0.08, 0.36, 0.16), Vector2i(24, 24)),
		"REPAIR_KIT": _make_placeholder_texture(Color(0.95, 0.42, 0.36), Color(0.5, 0.16, 0.12), Vector2i(24, 24)),
		"WEAPON_AMMO": _make_placeholder_texture(Color(0.96, 0.74, 0.25), Color(0.45, 0.3, 0.1), Vector2i(24, 24)),
		"DOUBLE_DAMAGE": _make_placeholder_texture(Color(0.95, 0.24, 0.24), Color(0.46, 0.08, 0.08), Vector2i(24, 24)),
	}


func _apply_static_placeholder_textures() -> void:
	chassis_icon.texture = _part_textures["CHASSIS"]
	engine_icon.texture = _part_textures["ENGINE"]
	weapon_mount_icon.texture = _part_textures["WEAPON_MOUNT"]
	wheel_fl_icon.texture = _part_textures["WHEEL"]
	wheel_fr_icon.texture = _part_textures["WHEEL"]
	wheel_rl_icon.texture = _part_textures["WHEEL"]
	wheel_rr_icon.texture = _part_textures["WHEEL"]
	primary_marker.texture = _weapon_textures["NONE"]
	secondary_marker.texture = _weapon_textures["NONE"]


func _make_stylebox(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	return sb


func _make_placeholder_texture(base: Color, accent: Color, tex_size: Vector2i) -> Texture2D:
	var image := Image.create(tex_size.x, tex_size.y, false, Image.FORMAT_RGBA8)
	image.fill(base)
	for y in range(tex_size.y):
		for x in range(tex_size.x):
			if ((x + y) % 7) < 3:
				image.set_pixel(x, y, accent)
	return ImageTexture.create_from_image(image)


func _disconnect_bound_car() -> void:
	if _bound_car == null:
		return
	if _bound_car.fuel_system:
		if _bound_car.fuel_system.fuel_changed.is_connected(_on_fuel_changed):
			_bound_car.fuel_system.fuel_changed.disconnect(_on_fuel_changed)
		if _bound_car.fuel_system.fuel_critical.is_connected(_on_fuel_critical):
			_bound_car.fuel_system.fuel_critical.disconnect(_on_fuel_critical)
	if _bound_car.damage_system and _bound_car.damage_system.zone_damaged.is_connected(_on_zone_damaged):
		_bound_car.damage_system.zone_damaged.disconnect(_on_zone_damaged)
	if _bound_car.powerup_started.is_connected(_on_powerup_started):
		_bound_car.powerup_started.disconnect(_on_powerup_started)
	if _bound_car.powerup_ended.is_connected(_on_powerup_ended):
		_bound_car.powerup_ended.disconnect(_on_powerup_ended)
	_bound_car = null


func _ensure_debug_overlay_label() -> void:
	if _debug_overlay_label:
		return
	_debug_overlay_label = Label.new()
	_debug_overlay_label.name = "DebugOverlay"
	_debug_overlay_label.position = debug_overlay_position
	_debug_overlay_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_overlay_label.modulate = Color(0.95, 1.0, 0.85, 0.95)
	_debug_overlay_label.add_theme_font_size_override("font_size", debug_overlay_font_size)
	add_child(_debug_overlay_label)


func _ensure_respawn_countdown_label() -> void:
	if _respawn_countdown_label:
		return
	var label := Label.new()
	label.name = "RespawnCountdown"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.size = Vector2(420.0, 64.0)
	label.position = Vector2(-210.0, -32.0)
	label.modulate = Color(1.0, 0.92, 0.72, 0.95)
	label.add_theme_font_size_override("font_size", 42)
	label.add_theme_color_override("font_shadow_color", Color(0.05, 0.05, 0.05, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.visible = false
	add_child(label)
	_respawn_countdown_label = label


func _ensure_match_timer_label() -> void:
	if _match_timer_label:
		return
	var label := Label.new()
	label.name = "MatchTimer"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.anchor_left = 0.5
	label.anchor_top = 0.0
	label.anchor_right = 0.5
	label.anchor_bottom = 0.0
	label.offset_left = -120.0
	label.offset_top = 18.0
	label.offset_right = 120.0
	label.offset_bottom = 48.0
	label.modulate = Color(1.0, 0.95, 0.78, 0.98)
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_shadow_color", Color(0.05, 0.05, 0.05, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.visible = false
	add_child(label)
	_match_timer_label = label


func _ensure_match_result_overlay() -> void:
	if _match_result_overlay:
		return
	var overlay_instance: Node = MATCH_END_DIALOG_SCENE.instantiate()
	if not (overlay_instance is Control):
		push_warning("MatchEndDialog scene root must inherit Control.")
		return
	if not overlay_instance.has_signal("restart_requested"):
		push_warning("MatchEndDialog scene is missing expected signals.")
		return
	_match_result_overlay = overlay_instance as Control
	_match_result_overlay.name = "MatchResultsOverlay"
	_match_result_overlay.restart_requested.connect(_on_match_end_dialog_restart_requested)
	_match_result_overlay.rejoin_requested.connect(_on_match_end_dialog_rejoin_requested)
	_match_result_overlay.back_to_menu_requested.connect(_on_match_end_dialog_back_to_menu_requested)
	_match_result_overlay.settings_changed.connect(_on_match_end_dialog_settings_changed)
	add_child(_match_result_overlay)


func _on_match_end_dialog_restart_requested() -> void:
	match_end_restart_requested.emit()


func _on_match_end_dialog_rejoin_requested() -> void:
	match_end_rejoin_requested.emit()


func _on_match_end_dialog_back_to_menu_requested() -> void:
	match_end_back_to_menu_requested.emit()


func _on_match_end_dialog_settings_changed(game_mode: String, match_time_seconds: int, map_id: String, bot_count: int) -> void:
	match_end_settings_changed.emit(game_mode, match_time_seconds, map_id, bot_count)


func _set_debug_overlay_visible(visible_state: bool) -> void:
	if _debug_overlay_label == null:
		_ensure_debug_overlay_label()
	_debug_overlay_label.visible = visible_state


func _update_debug_overlay() -> void:
	if _debug_overlay_label == null or not _debug_overlay_label.visible:
		return
	if _bound_car == null:
		_debug_overlay_label.text = "DEBUG\nNo car bound"
		return

	var lines: PackedStringArray = PackedStringArray()
	lines.append("DEBUG")
	lines.append("Vehicle: %s" % _bound_car.vehicle_data_id)
	lines.append("Speed: %3d km/h" % int(_bound_car.current_speed_kmh))
	lines.append("Top: %.1f" % _bound_car.max_speed_kmh)
	lines.append("Boost: %.0f / %.0f" % [_bound_car.boost_meter, _bound_car.boost_meter_max])
	lines.append("EMP: %s %.1fs" % ["ON" if _bound_car.is_emp_disabled else "OFF", _bound_car.get_emp_remaining()])
	lines.append("Powerups: %d" % _bound_car.get_active_powerups().size())

	_debug_overlay_label.position = debug_overlay_position
	_debug_overlay_label.add_theme_font_size_override("font_size", debug_overlay_font_size)
	_debug_overlay_label.text = "\n".join(lines)
