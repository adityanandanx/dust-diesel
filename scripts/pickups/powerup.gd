extends PickupBase

## Powerup — one of 6 types, applies a temporary or instant effect.

enum PowerupType {
	NITRO_SURGE,
	ARMOR_PLATING,
	FUEL_CAN,
	REPAIR_KIT,
	WEAPON_AMMO,
	DOUBLE_DAMAGE,
}

@export var powerup_type: PowerupType = PowerupType.FUEL_CAN
@export var show_type_label: bool = true
@export var type_label_height: float = 1.25

@onready var type_label: Label3D = $TypeLabel


func _ready() -> void:
	super._ready()
	_sanitize_powerup_type()
	_update_type_label()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_POST_SAVE:
		_update_type_label()


func _validate_property(_property: Dictionary) -> void:
	# Keep in-editor label current when properties are adjusted.
	_update_type_label()


func apply(car: VehicleBody3D) -> void:
	_sanitize_powerup_type()
	var car_node: Car = car as Car
	if car_node:
		car_node.register_powerup(PowerupType.keys()[int(powerup_type)], _get_display_duration())
	match powerup_type:
		PowerupType.NITRO_SURGE:
			_apply_nitro(car)
		PowerupType.ARMOR_PLATING:
			_apply_armor(car)
		PowerupType.FUEL_CAN:
			_apply_fuel(car)
		PowerupType.REPAIR_KIT:
			_apply_repair(car)
		PowerupType.WEAPON_AMMO:
			_apply_ammo(car)
		PowerupType.DOUBLE_DAMAGE:
			_apply_double_damage(car)


func _get_display_duration() -> float:
	match powerup_type:
		PowerupType.NITRO_SURGE:
			return 4.0
		PowerupType.ARMOR_PLATING:
			return 10.0
		PowerupType.DOUBLE_DAMAGE:
			return 15.0
		_:
			return 2.0


func _apply_nitro(car: VehicleBody3D) -> void:
	## Fill boost meter + temporary speed burst
	if "boost_meter" in car:
		car.boost_meter = car.boost_meter_max
	if "is_boosting" in car:
		car.is_boosting = true
		# Auto-disable after 4 seconds
		get_tree().create_timer(4.0).timeout.connect(func():
			if is_instance_valid(car):
				car.is_boosting = false
		)


func _apply_armor(car: VehicleBody3D) -> void:
	## 50% damage reduction for 10 seconds
	var dmg = car.get_node_or_null("DamageSystem")
	if not dmg:
		return
	if "damage_multiplier" not in dmg:
		return
	dmg.damage_multiplier = 0.5
	get_tree().create_timer(10.0).timeout.connect(func():
		if is_instance_valid(dmg):
			dmg.damage_multiplier = 1.0
	)


func _apply_fuel(car: VehicleBody3D) -> void:
	## +40 fuel
	var fuel_sys = car.get_node_or_null("FuelSystem")
	if fuel_sys and fuel_sys.has_method("refuel"):
		fuel_sys.refuel(40.0)


func _apply_repair(car: VehicleBody3D) -> void:
	## Repair worst-damaged zone by 50 HP
	var dmg = car.get_node_or_null("DamageSystem")
	if not dmg:
		return
	if dmg.has_method("get_worst_zone") and dmg.has_method("repair_zone"):
		var worst_zone = dmg.get_worst_zone()
		dmg.repair_zone(worst_zone, 50.0)


func _apply_ammo(car: VehicleBody3D) -> void:
	## Refill current weapon ammo
	if "primary_weapon" in car and car.primary_weapon:
		var w = car.primary_weapon
		if w.max_ammo > 0:
			w.ammo = w.max_ammo
	if "secondary_weapon" in car and car.secondary_weapon:
		var w = car.secondary_weapon
		if w.max_ammo > 0:
			w.ammo = w.max_ammo


func _apply_double_damage(car: VehicleBody3D) -> void:
	## 2× weapon damage for 15 seconds
	var weapons: Array = []
	if "primary_weapon" in car and car.primary_weapon:
		weapons.append(car.primary_weapon)
	if "secondary_weapon" in car and car.secondary_weapon:
		weapons.append(car.secondary_weapon)
	for w in weapons:
		w.damage *= 2.0
	get_tree().create_timer(15.0).timeout.connect(func():
		for w in weapons:
			if is_instance_valid(w):
				w.damage /= 2.0
	)


func _update_type_label() -> void:
	if type_label == null:
		return
	_sanitize_powerup_type()
	type_label.visible = show_type_label
	type_label.position = Vector3(0.0, type_label_height, 0.0)
	type_label.text = _get_type_display_name()


func _get_type_display_name() -> String:
	var keys: PackedStringArray = PowerupType.keys()
	if keys.is_empty():
		return "Powerup"
	var idx: int = clampi(int(powerup_type), 0, keys.size() - 1)
	var enum_name: String = keys[idx]
	var words: PackedStringArray = enum_name.split("_")
	for i in range(words.size()):
		words[i] = String(words[i]).capitalize()
	return " ".join(words)


func _sanitize_powerup_type() -> void:
	var keys: PackedStringArray = PowerupType.keys()
	if keys.is_empty():
		return
	powerup_type = clampi(int(powerup_type), 0, keys.size() - 1) as PowerupType


func _get_log_kind() -> String:
	return "powerup"


func _get_log_detail() -> String:
	return _get_type_display_name()
