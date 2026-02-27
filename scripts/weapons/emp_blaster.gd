extends WeaponBase

## EMP Blaster — charged shot that disables target for 3 seconds.

@export var emp_range: float = 30.0
@export var emp_disable_duration: float = 3.0


func _ready() -> void:
	super._ready()
	mount_type = MountType.PRIMARY
	fire_rate = 0.2 ## 5 second recharge
	damage = 0.0 ## no direct damage
	reload_type = ReloadType.NONE
	max_ammo = -1
	recoil_impulse = 65.0
	recoil_torque_impulse = 4.0


func _do_fire() -> void:
	if not owner_car:
		return
	# Raycast forward to find target
	var origin := global_position
	var forward = owner_car.global_basis.z.normalized()
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * emp_range)
	query.exclude = [owner_car.get_rid()]
	query.collision_mask = 1 # car layer

	var result := space.intersect_ray(query)
	if result.is_empty():
		return

	var target = result["collider"]
	if target is VehicleBody3D and target.has_method("apply_emp"):
		target.apply_emp(emp_disable_duration)
