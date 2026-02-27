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
	# Spawn ahead of car to avoid self-collision
	var forward = owner_car.global_basis.z.normalized()
	bolt.global_position = owner_car.global_position + forward * 3.0 + Vector3.UP * 0.5
	var spread := Vector3(
		randf_range(-spread_angle, spread_angle),
		0,
		randf_range(-spread_angle, spread_angle)
	)
	bolt.launch(forward + spread, owner_car)
	bolt.speed = bolt_speed
	bolt.damage = bolt_damage
