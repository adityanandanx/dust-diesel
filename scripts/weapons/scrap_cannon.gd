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


func _do_fire() -> void:
	if not owner_car:
		return
	var chunk: CharacterBody3D = ScrapChunkScene.instantiate()
	get_tree().current_scene.add_child(chunk)
	chunk.global_position = global_position
	var forward = owner_car.global_basis.z.normalized()
	chunk.launch(forward, owner_car)
	chunk.speed = chunk_speed
	chunk.damage = chunk_damage
	chunk.splash_radius = chunk_splash_radius
	chunk.splash_damage = chunk_splash_damage
	chunk.max_bounces = 1
	chunk._bounces_left = 1
