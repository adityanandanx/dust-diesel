extends WeaponBase

## Scrap Cannon — single heavy projectile, splash damage, one wall-bounce.

const ScrapChunkScene := preload("res://scenes/weapons/ScrapChunk.tscn")
const SPLASH_DAMAGE_SCALE: float = 0.4166667

@export var chunk_speed: float = 40.0
@export var chunk_splash_radius: float = 5.0


func _do_fire() -> void:
	if not owner_car:
		return
	var chunk: CharacterBody3D = ScrapChunkScene.instantiate()
	get_tree().current_scene.add_child(chunk)
	chunk.global_position = get_muzzle_position(2.6, 0.2)
	var forward: Vector3 = get_muzzle_direction()
	chunk.launch(forward, owner_car)
	chunk.speed = chunk_speed
	chunk.damage = damage
	chunk.splash_radius = chunk_splash_radius
	chunk.splash_damage = damage * SPLASH_DAMAGE_SCALE
	chunk.max_bounces = 1
	chunk._bounces_left = 1
