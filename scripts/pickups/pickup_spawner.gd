extends Node3D

## Pickup Spawner — manages timed spawn of weapons, powerups, and fuel cans.

const WeaponPickupScene := preload("res://scenes/pickups/WeaponPickup.tscn")
const PowerupScene := preload("res://scenes/pickups/Powerup.tscn")
const FuelCanScene := preload("res://scenes/pickups/FuelCan.tscn")
const POWERUP_TYPE_COUNT: int = 6
const POWERUP_DEFAULT_TYPE: int = 2 # FUEL_CAN

@export var weapon_spawn_interval: float = 15.0
@export var powerup_spawn_interval: float = 20.0
@export var fuel_spawn_interval: float = 25.0
@export var max_active_pickups: int = 8

var _weapon_timer: float = 5.0 # first weapon spawns at 5s
var _powerup_timer: float = 10.0
var _fuel_timer: float = 8.0
var _active_pickups: Dictionary = {} # id -> pickup node
var _next_pickup_id: int = 1

# Spawn positions around the arena
var _spawn_positions: Array[Vector3] = [
	Vector3(20, 0, 0),
	Vector3(-20, 0, 0),
	Vector3(0, 0, 20),
	Vector3(0, 0, -20),
	Vector3(15, 0, 15),
	Vector3(-15, 0, 15),
	Vector3(15, 0, -15),
	Vector3(-15, 0, -15),
	Vector3(35, 0, 0),
	Vector3(-35, 0, 0),
	Vector3(0, 0, 35),
	Vector3(0, 0, -35),
]


func set_spawn_positions(positions: Array[Vector3]) -> void:
	if positions.is_empty():
		return
	_spawn_positions = positions.duplicate()


func _ready() -> void:
	if NakamaManager.current_match:
		NakamaManager.socket.received_match_state.connect(_on_remote_match_state)


func _on_remote_match_state(match_state: NakamaRTAPI.MatchData) -> void:
	if match_state.op_code == NakamaManager.OpCodes.SPAWN_PICKUP:
		if NakamaManager.is_host: return # Host spawned it locally
		var data: Dictionary = JSON.parse_string(match_state.data)
		if data == null or not "id" in data: return
		
		# Loot drops from destructibles use px/py/pz; spawner uses pos index
		if "px" in data:
			_spawn_pickup_at_pos(int(data["id"]), int(data["cat"]), int(data["sub"]),
				Vector3(float(data["px"]), float(data["py"]), float(data["pz"])))
		else:
			spawn_pickup_local(int(data["id"]), int(data["cat"]), int(data["sub"]), int(data["pos"]))
		
	elif match_state.op_code == NakamaManager.OpCodes.PICKUP_CLAIM:
		var data: Dictionary = JSON.parse_string(match_state.data)
		if data == null or not "id" in data: return
		claim_pickup_local(int(data["id"]))
		if "collector" in data and "kind" in data:
			_emit_pickup_log(str(data["collector"]), str(data["kind"]), str(data.get("detail", "")))


func _physics_process(delta: float) -> void:
	# Only the host or singleplayer runs spawn logic
	if NakamaManager.current_match and not NakamaManager.is_host:
		return
		
	_weapon_timer -= delta
	_powerup_timer -= delta
	_fuel_timer -= delta

	if _weapon_timer <= 0.0:
		_weapon_timer = weapon_spawn_interval
		_host_spawn_pickup(0, -1) # 0 = Weapon

	if _powerup_timer <= 0.0:
		_powerup_timer = powerup_spawn_interval
		# PowerupType enum is 0..5
		_host_spawn_pickup(1, randi() % POWERUP_TYPE_COUNT)

	if _fuel_timer <= 0.0:
		_fuel_timer = fuel_spawn_interval
		_host_spawn_pickup(2, -1)


func _host_spawn_pickup(category: int, sub_type: int) -> void:
	if _active_pickups.size() >= max_active_pickups:
		return
		
	var pos_index := randi() % _spawn_positions.size()
	var p_id := _next_pickup_id
	_next_pickup_id += 1
	
	if NakamaManager.current_match:
		var data = {"id": p_id, "cat": category, "sub": sub_type, "pos": pos_index}
		NakamaManager.send_match_state(NakamaManager.OpCodes.SPAWN_PICKUP, JSON.stringify(data))
		
	# Spawn it locally
	spawn_pickup_local(p_id, category, sub_type, pos_index)


func spawn_pickup_local(p_id: int, category: int, sub_type: int, pos_index: int) -> void:
	var scene: PackedScene
	if category == 0:
		scene = WeaponPickupScene
	elif category == 1:
		scene = PowerupScene
	elif category == 2:
		scene = FuelCanScene
	else:
		return

	var pickup: PickupBase = scene.instantiate()
	pickup.pickup_id = p_id
	if category == 1:
		pickup.powerup_type = _sanitize_powerup_subtype(sub_type)
		
	add_child(pickup)
	pickup.global_position = _spawn_positions[pos_index]
	_active_pickups[p_id] = pickup
	pickup.tree_exited.connect(func(): _active_pickups.erase(p_id))


func claim_pickup_local(p_id: int) -> void:
	if _active_pickups.has(p_id):
		var p: Node = _active_pickups[p_id]
		if is_instance_valid(p):
			p.queue_free()
		_active_pickups.erase(p_id)


func _spawn_pickup_at_pos(p_id: int, category: int, sub_type: int, pos: Vector3) -> void:
	var scene: PackedScene
	if category == 0:
		scene = WeaponPickupScene
	elif category == 1:
		scene = PowerupScene
	elif category == 2:
		scene = FuelCanScene
	else:
		return

	var pickup: PickupBase = scene.instantiate()
	pickup.pickup_id = p_id
	if category == 1:
		pickup.powerup_type = _sanitize_powerup_subtype(sub_type)
		
	get_tree().current_scene.add_child(pickup)
	pickup.global_position = pos
	_active_pickups[p_id] = pickup
	pickup.tree_exited.connect(func(): _active_pickups.erase(p_id))


func _sanitize_powerup_subtype(sub_type: int) -> int:
	if sub_type < 0 or sub_type >= POWERUP_TYPE_COUNT:
		return POWERUP_DEFAULT_TYPE
	return sub_type


func _emit_pickup_log(collector: String, kind: String, detail: String) -> void:
	var hud_nodes: Array = get_tree().get_nodes_in_group("hud_log_feed")
	if hud_nodes.is_empty():
		return

	var hud_node: Node = hud_nodes[0]
	if hud_node.has_method("add_pickup_log"):
		hud_node.add_pickup_log(collector, kind, detail)
