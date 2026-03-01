extends WeaponBase

## Rivet Cannon — rapid-fire steel bolts, excellent at shredding wheels.

const RivetBoltScene := preload("res://scenes/weapons/RivetBolt.tscn")

@export var bolt_speed: float = 80.0
@export var bolt_damage: float = 5.0
@export var spread_angle: float = 0.03 ## radians of random spread


func _ready() -> void:
	super._ready()
	mount_type = MountType.PRIMARY
	fire_rate = 10.0
	damage = bolt_damage
	reload_type = ReloadType.OVERHEAT
	heat_per_shot = 10.0
	max_heat = 100.0
	cooldown_rate = 40.0
	overheat_penalty = 2.0
	recoil_impulse = 8.0
	recoil_torque_impulse = 1.2


func _do_fire() -> void:
	if not owner_car:
		return
	var bolt: CharacterBody3D = RivetBoltScene.instantiate()
	get_tree().current_scene.add_child(bolt)
	var forward: Vector3 = get_muzzle_direction()
	bolt.global_position = get_muzzle_position(2.8, 0.2)

	var right: Vector3 = forward.cross(Vector3.UP)
	if right.length_squared() <= 0.0001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	var up: Vector3 = right.cross(forward).normalized()
	var spread_dir: Vector3 = (
		forward
		+ right * randf_range(-spread_angle, spread_angle)
		+ up * randf_range(-spread_angle, spread_angle)
	).normalized()

	bolt.launch(spread_dir, owner_car)
	bolt.speed = bolt_speed
	bolt.damage = bolt_damage
