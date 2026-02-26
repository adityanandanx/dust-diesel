extends PickupBase

## Powerup — one of 7 types, applies a temporary or instant effect.

enum PowerupType {
	NITRO_SURGE,
	ARMOR_PLATING,
	FUEL_CAN,
	REPAIR_KIT,
	WEAPON_AMMO,
	DOUBLE_DAMAGE,
	GHOST_MODE,
}

@export var powerup_type: PowerupType = PowerupType.FUEL_CAN


func apply(car: VehicleBody3D) -> void:
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
		PowerupType.GHOST_MODE:
			_apply_ghost(car)


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
	if fuel_sys and "fuel" in fuel_sys:
		fuel_sys.fuel = minf(fuel_sys.fuel + 40.0, fuel_sys.max_fuel)


func _apply_repair(car: VehicleBody3D) -> void:
	## Repair worst-damaged zone by 50 HP
	var dmg = car.get_node_or_null("DamageSystem")
	if not dmg:
		return
	# Find the zone with the lowest HP ratio
	var zones := {
		"engine": [dmg.engine_hp, dmg.max_engine_hp],
		"chassis": [dmg.chassis_hp, dmg.max_chassis_hp],
		"wheels": [dmg.wheel_hp, dmg.max_wheel_hp],
		"weapon_mount": [dmg.weapon_mount_hp, dmg.max_weapon_mount_hp],
	}
	var worst_zone := ""
	var worst_ratio := 1.1
	for zone_name in zones:
		var ratio: float = zones[zone_name][0] / zones[zone_name][1]
		if ratio < worst_ratio:
			worst_ratio = ratio
			worst_zone = zone_name

	if worst_zone == "engine":
		dmg.engine_hp = minf(dmg.engine_hp + 50.0, dmg.max_engine_hp)
	elif worst_zone == "chassis":
		dmg.chassis_hp = minf(dmg.chassis_hp + 50.0, dmg.max_chassis_hp)
	elif worst_zone == "wheels":
		dmg.wheel_hp = minf(dmg.wheel_hp + 50.0, dmg.max_wheel_hp)
	elif worst_zone == "weapon_mount":
		dmg.weapon_mount_hp = minf(dmg.weapon_mount_hp + 50.0, dmg.max_weapon_mount_hp)


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


func _apply_ghost(car: VehicleBody3D) -> void:
	## Disable car-to-car collisions for 5 seconds
	var original_layer: int = car.collision_layer
	var original_mask: int = car.collision_mask
	car.collision_layer = 0 # invisible to other cars
	car.collision_mask &= ~1 # don't collide with cars
	get_tree().create_timer(5.0).timeout.connect(func():
		if is_instance_valid(car):
			car.collision_layer = original_layer
			car.collision_mask = original_mask
	)
