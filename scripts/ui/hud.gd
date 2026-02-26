extends Control

## In-game HUD — fuel gauge, boost bar, minimap placeholder, kill feed, damage indicators.

@onready var fuel_bar: ProgressBar = $FuelGauge/FuelBar
@onready var fuel_label: Label = $FuelGauge/FuelLabel
@onready var boost_bar: ProgressBar = $BoostGauge/BoostBar
@onready var speed_label: Label = $SpeedLabel
@onready var kill_feed_container: VBoxContainer = $KillFeed
@onready var damage_left: ColorRect = $DamageIndicators/Left
@onready var damage_right: ColorRect = $DamageIndicators/Right
@onready var damage_top: ColorRect = $DamageIndicators/Top
@onready var damage_bottom: ColorRect = $DamageIndicators/Bottom

var _bound_car: Car = null
var _damage_flash_timers: Dictionary = {} # direction -> float


func bind_car(car: Car) -> void:
	_bound_car = car
	if car.fuel_system:
		car.fuel_system.fuel_changed.connect(_on_fuel_changed)
		car.fuel_system.fuel_critical.connect(_on_fuel_critical)
	if car.damage_system:
		car.damage_system.zone_damaged.connect(_on_zone_damaged)


func _process(delta: float) -> void:
	if not _bound_car:
		return

	# Speed display
	speed_label.text = "%d km/h" % int(_bound_car.current_speed_kmh)

	# Boost bar
	boost_bar.value = _bound_car.boost_meter
	boost_bar.max_value = _bound_car.boost_meter_max

	# Fade damage indicators
	for dir_key in _damage_flash_timers.keys():
		_damage_flash_timers[dir_key] -= delta
		var panel: ColorRect = _get_damage_panel(dir_key)
		if panel:
			panel.modulate.a = clampf(_damage_flash_timers[dir_key] / 0.5, 0.0, 0.8)
		if _damage_flash_timers[dir_key] <= 0.0:
			_damage_flash_timers.erase(dir_key)


func _on_fuel_changed(current: float, max_fuel: float) -> void:
	fuel_bar.value = current
	fuel_bar.max_value = max_fuel
	fuel_label.text = "%d%%" % int((current / max_fuel) * 100.0)


func _on_fuel_critical() -> void:
	# Pulse the fuel bar red
	var tween := create_tween().set_loops()
	tween.tween_property(fuel_bar, "modulate", Color.RED, 0.3)
	tween.tween_property(fuel_bar, "modulate", Color.WHITE, 0.3)


func _on_zone_damaged(zone: String, _current_hp: float, _max_hp: float) -> void:
	# Flash corresponding damage indicator
	var dir_key := "top" # default
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


func add_kill_feed_entry(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1, 0.85, 0.6))
	kill_feed_container.add_child(label)
	# Fade out after 5 seconds
	var tween := create_tween()
	tween.tween_interval(4.0)
	tween.tween_property(label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(label.queue_free)
	# Cap visible entries
	while kill_feed_container.get_child_count() > 6:
		kill_feed_container.get_child(0).queue_free()


func _get_damage_panel(dir_key: String) -> ColorRect:
	match dir_key:
		"left": return damage_left
		"right": return damage_right
		"top": return damage_top
		"bottom": return damage_bottom
	return null
