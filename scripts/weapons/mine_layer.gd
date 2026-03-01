extends WeaponBase

## Mine Layer — drops proximity mines behind the car.

const MineScene := preload("res://scenes/weapons/Mine.tscn")

@export var mine_arm_delay: float = 1.5
@export var mine_knockback: float = 8000.0
@export var drop_offset: float = -3.0


func _do_fire() -> void:
	if not owner_car:
		return
	var mine = MineScene.instantiate()
	get_tree().current_scene.add_child(mine)
	var behind = owner_car.global_basis.z.normalized() * drop_offset
	mine.global_position = owner_car.global_position + behind
	mine.global_position.y = 0.1
	mine.arm_delay = mine_arm_delay
	mine.damage = damage
	mine.knockback_force = mine_knockback
	mine.owner_car = owner_car
