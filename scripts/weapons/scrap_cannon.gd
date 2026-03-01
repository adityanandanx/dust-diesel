extends WeaponBase

## Scrap Cannon — single heavy projectile, splash damage, one wall-bounce.

const ScrapChunkScene := preload("res://scenes/weapons/ScrapChunk.tscn")

@export var chunk_speed: float = 40.0
@export var chunk_damage: float = 60.0
@export var chunk_splash_radius: float = 5.0
@export var chunk_splash_damage: float = 25.0


func _ready() -> void:
	super._ready()
	mount_type = MountType.PRIMARY
	fire_rate = 0.25 ## 4 second reload
	damage = chunk_damage
	reload_type = ReloadType.NONE
	max_ammo = -1 ## infinite, just slow fire rate
	recoil_impulse = 140.0
	recoil_torque_impulse = 9.0


func _do_fire() -> void:
	if not owner_car:
		return
	var chunk: CharacterBody3D = ScrapChunkScene.instantiate()
	get_tree().current_scene.add_child(chunk)
	chunk.global_position = get_muzzle_position(2.6, 0.2)
	var forward: Vector3 = get_muzzle_direction()
	chunk.launch(forward, owner_car)
	chunk.speed = chunk_speed
	chunk.damage = chunk_damage
	chunk.splash_radius = chunk_splash_radius
	chunk.splash_damage = chunk_splash_damage
	chunk.max_bounces = 1
	chunk._bounces_left = 1
