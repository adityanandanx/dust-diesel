extends DestructibleBase

## Scrap Pile — blocks paths, reveals a random pickup when destroyed.


func _ready() -> void:
	super._ready()
	max_hp = 80.0
	hp = max_hp
	ram_damage_to_car = 15.0
	loot_table = [
		preload("res://scenes/pickups/WeaponPickup.tscn"),
		preload("res://scenes/pickups/Powerup.tscn"),
	]
	loot_count = 1
	mass = 500.0 # heavy, not easily pushed
