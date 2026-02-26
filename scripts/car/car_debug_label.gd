extends Label3D

## Debug overlay — shows live stats above each car.
## Attach as a child of the Car node.

var car: VehicleBody3D


func _ready() -> void:
	car = get_parent()
	top_level = false
	position = Vector3(0, 4, 0) # float above car
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	font_size = 32
	outline_size = 8
	modulate = Color.WHITE
	outline_modulate = Color.BLACK
	no_depth_test = true
	pixel_size = 0.01


func _process(_delta: float) -> void:
	if not is_instance_valid(car):
		return
	
	var lines := PackedStringArray()
	
	# Identity
	var role := "LOCAL" if car.is_player else "REMOTE"
	lines.append("[%s] %s" % [role, car.network_id.left(6) if car.network_id != "" else "solo"])
	
	# Speed
	lines.append("SPD: %d km/h" % int(car.current_speed_kmh))
	
	# Fuel
	var fuel_sys = car.get_node_or_null("FuelSystem")
	if fuel_sys and "fuel" in fuel_sys:
		lines.append("FUEL: %.0f/%.0f" % [fuel_sys.fuel, fuel_sys.max_fuel])
	
	# Damage zones
	var dmg = car.get_node_or_null("DamageSystem")
	if dmg:
		lines.append("ENG: %.0f  CHS: %.0f" % [dmg.engine_hp, dmg.chassis_hp])
		lines.append("WHL: %.0f  WPN: %.0f" % [dmg.wheel_hp, dmg.weapon_mount_hp])
	
	# Weapons
	var pri := "none"
	var sec := "none"
	if car.primary_weapon:
		pri = car.primary_weapon.weapon_name if "weapon_name" in car.primary_weapon else car.primary_weapon.name
		pri += " [%d]" % car.primary_weapon.ammo if "ammo" in car.primary_weapon else ""
	if car.secondary_weapon:
		sec = car.secondary_weapon.weapon_name if "weapon_name" in car.secondary_weapon else car.secondary_weapon.name
		sec += " [%d]" % car.secondary_weapon.ammo if "ammo" in car.secondary_weapon else ""
	lines.append("PRI: %s" % pri)
	lines.append("SEC: %s" % sec)
	
	# Boost
	if "boost_meter" in car:
		lines.append("BOOST: %.0f" % car.boost_meter)
	
	text = "\n".join(lines)
