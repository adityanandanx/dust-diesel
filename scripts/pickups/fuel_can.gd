extends PickupBase

## Fuel Can — gives +40 fuel on collect.


func apply(car: VehicleBody3D) -> void:
	var fuel_sys = car.get_node_or_null("FuelSystem")
	if fuel_sys and "fuel" in fuel_sys:
		fuel_sys.fuel = minf(fuel_sys.fuel + 40.0, fuel_sys.max_fuel)
		if fuel_sys.has_signal("fuel_changed"):
			fuel_sys.fuel_changed.emit(fuel_sys.fuel, fuel_sys.max_fuel)


func _get_log_kind() -> String:
	return "fuel"


func _get_log_detail() -> String:
	return "Fuel Can"
