extends PickupBase

## Weapon Pickup — grants a random weapon when collected.

const WEAPON_POOL: Array[PackedScene] = []

# Populated in _ready since const arrays can't hold preloads
var _weapon_scenes: Array[PackedScene] = []
var _last_weapon_name: String = "Weapon"


func _ready() -> void:
	super._ready()
	_weapon_scenes = [
		preload("res://scenes/weapons/RivetCannon.tscn"),
		preload("res://scenes/weapons/ScrapCannon.tscn"),
		preload("res://scenes/weapons/FlameProjector.tscn"),
		preload("res://scenes/weapons/HarpoonLauncher.tscn"),
		preload("res://scenes/weapons/OilSlick.tscn"),
		preload("res://scenes/weapons/MineLayer.tscn"),
		preload("res://scenes/weapons/EMPBlaster.tscn"),
	]


func apply(car: VehicleBody3D) -> void:
	if _weapon_scenes.is_empty():
		return

	var owned_ids: Dictionary = _collect_owned_weapon_ids(car)
	var candidate_indices: Array[int] = []
	for i in range(_weapon_scenes.size()):
		var weapon_id: String = _weapon_scenes[i].resource_path
		if not owned_ids.has(weapon_id):
			candidate_indices.append(i)

	var idx: int
	if candidate_indices.is_empty():
		idx = randi() % _weapon_scenes.size()
	else:
		idx = candidate_indices[randi() % candidate_indices.size()]

	var scene: PackedScene = _weapon_scenes[idx]
	var weapon = scene.instantiate()
	_last_weapon_name = _weapon_name_from_scene(scene, weapon)
	if car.has_method("equip_weapon"):
		car.equip_weapon(weapon)
		
		# Sync the weapon equip to remote players
		if NakamaManager.current_match and car.is_player:
			var data = {
				"session_id": NakamaManager.current_match.self_user.session_id,
				"weapon_idx": idx,
				"slot": weapon.mount_type # PRIMARY=0, SECONDARY=1
			}
			NakamaManager.send_match_state(NakamaManager.OpCodes.WEAPON_EQUIP, JSON.stringify(data))


func _collect_owned_weapon_ids(car: VehicleBody3D) -> Dictionary:
	var ids: Dictionary = {}
	if "primary_weapon" in car and car.primary_weapon:
		var primary_id: String = _weapon_id_from_node(car.primary_weapon)
		if primary_id != "":
			ids[primary_id] = true
	if "secondary_weapon" in car and car.secondary_weapon:
		var secondary_id: String = _weapon_id_from_node(car.secondary_weapon)
		if secondary_id != "":
			ids[secondary_id] = true
	return ids


func _weapon_id_from_node(weapon: Node) -> String:
	if weapon == null:
		return ""
	if weapon.scene_file_path != "":
		return weapon.scene_file_path
	var script_ref: Variant = weapon.get_script()
	if script_ref is Script:
		var script_path: String = (script_ref as Script).resource_path
		if script_path != "":
			return script_path
	return weapon.name


func _weapon_name_from_scene(scene: PackedScene, fallback_node: Node) -> String:
	if scene and scene.resource_path != "":
		var file_name: String = scene.resource_path.get_file().trim_suffix(".tscn")
		return file_name
	if fallback_node:
		return fallback_node.name
	return "Weapon"


func _get_log_kind() -> String:
	return "weapon"


func _get_log_detail() -> String:
	return _last_weapon_name
