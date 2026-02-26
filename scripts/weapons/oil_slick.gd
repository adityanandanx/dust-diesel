extends WeaponBase

## Oil Slick Dropper — rear-mount, ejects traction-kill oil puddle behind car.

const OilPuddleScene := preload("res://scenes/weapons/OilPuddle.tscn")

@export var puddle_lifetime: float = 12.0
@export var drop_offset: float = -3.0 ## behind the car


func _ready() -> void:
	super._ready()
	mount_type = MountType.SECONDARY
	fire_rate = 0.5 ## 2 seconds between drops
	damage = 0.0
	max_ammo = 5
	ammo = max_ammo
	reload_type = ReloadType.NONE


func _do_fire() -> void:
	if not owner_car:
		return
	var puddle = OilPuddleScene.instantiate()
	get_tree().current_scene.add_child(puddle)
	# Drop behind the car
	var behind = owner_car.global_basis.z.normalized() * drop_offset
	puddle.global_position = owner_car.global_position + behind
	puddle.global_position.y = 0.05 ## just above ground
	puddle.lifetime = puddle_lifetime
