extends Node3D

## Last Driver Standing game mode controller.
## Spawns cars, tracks eliminations, declares winner.

signal player_eliminated(player_name: String, killer_name: String)
signal match_ended(winner_name: String)

const WreckScene := preload("res://scenes/vehicles/CarWreck.tscn")
const WeaponScene := preload("res://scenes/weapons/ScrapCannon.tscn")
const WeaponScene2 := preload("res://scenes/weapons/MineLayer.tscn")
const DefaultSpawnPointsScene := preload("res://scenes/game/SpawnPoints.tscn")

# Must match the order in weapon_pickup.gd _weapon_scenes
var WEAPON_SCENES: Array[PackedScene] = [
	preload("res://scenes/weapons/RivetCannon.tscn"),
	preload("res://scenes/weapons/ScrapCannon.tscn"),
	preload("res://scenes/weapons/FlameProjector.tscn"),
	preload("res://scenes/weapons/HarpoonLauncher.tscn"),
	preload("res://scenes/weapons/OilSlick.tscn"),
	preload("res://scenes/weapons/MineLayer.tscn"),
	preload("res://scenes/weapons/EMPBlaster.tscn"),
]

@onready var cars_container: Node3D = $Cars
@onready var wrecks_container: Node3D = $Wrecks
@onready var hud: Control = $HUDLayer/HUD
@onready var top_down_camera: Camera3D = $TopDownCamera
@onready var pickup_spawner: Node3D = $PickupSpawner

var alive_cars: Array[Car] = []
var kill_feed: Array[Dictionary] = [] # {victim, killer, cause, time}
var connected_cars: Dictionary = {}
var spawn_points: Node3D = null
var _active_map_root: Node3D = null


func _ready() -> void:
	_load_selected_map()
	if NakamaManager.current_match:
		_spawn_networked_players()
	else:
		_spawn_players()


func _load_selected_map() -> void:
	var map_registry: Node = get_node_or_null("/root/MapRegistry")
	if map_registry == null:
		return

	var map_id := "boneyard"
	if NakamaManager.current_match:
		map_id = NakamaManager.selected_map

	if not map_registry.has_id(map_id):
		map_id = "boneyard"
		NakamaManager.selected_map = map_id

	var map_data = map_registry.get_by_id(map_id)
	var map_scene: PackedScene = load(map_data.scene_path)
	if map_scene == null:
		map_scene = load("res://scenes/game/Boneyard.tscn")
		NakamaManager.selected_map = "boneyard"

	var map_instance: Node3D = map_scene.instantiate()
	map_instance.name = "Map"
	add_child(map_instance)
	move_child(map_instance, 0)
	_active_map_root = map_instance

	spawn_points = map_instance.get_node_or_null("SpawnPoints")
	if spawn_points == null:
		spawn_points = DefaultSpawnPointsScene.instantiate()
		spawn_points.name = "SpawnPoints"
		add_child(spawn_points)

	if pickup_spawner and pickup_spawner.has_method("set_spawn_positions"):
		var pickup_points_root: Node3D = map_instance.get_node_or_null("PickupPoints")
		if pickup_points_root != null:
			var positions: Array[Vector3] = []
			for child in pickup_points_root.get_children():
				if child is Marker3D:
					positions.append(child.global_position)
			if positions.size() > 0:
				pickup_spawner.set_spawn_positions(positions)


func _spawn_networked_players() -> void:
	if spawn_points == null:
		return
	var points := spawn_points.get_children()
	if points.is_empty():
		return
	var index := 0
	
	# Sort session IDs so everyone assigns the same spawn logic
	var session_ids = NakamaManager.connected_players.keys()
	session_ids.sort()
	
	for sess_id in session_ids:
		var p_data: Dictionary = NakamaManager.connected_players[sess_id]
		var is_me = (sess_id == NakamaManager.current_match.self_user.session_id)
		
		var v_id = p_data.get("selected_vehicle", "sedan")
		var v_data = VehicleRegistry.get_by_id(v_id)
		var car_scene: PackedScene = load(v_data.scene_path)
		var car: Car = car_scene.instantiate()
		
		car.is_player = is_me
		car.network_id = sess_id
		car.name = p_data.get("username", "Unknown")
		cars_container.add_child(car)
		
		var pt = points[index % points.size()]
		index += 1
		car.global_transform = pt.global_transform
		
		car.car_destroyed.connect(_on_car_destroyed)
		car.car_stalled.connect(_on_car_stalled)
		alive_cars.append(car)
		connected_cars[sess_id] = car
		
		# Default weapons for now
		car.equip_weapon(WeaponScene.instantiate())
		car.equip_weapon(WeaponScene2.instantiate())
		
		if is_me and hud and hud.has_method("bind_car"):
			hud.bind_car(car)
		if is_me and top_down_camera and top_down_camera.has_method("set_target"):
			top_down_camera.set_target(car)
			
	NakamaManager.player_left.connect(_on_player_left)
	NakamaManager.socket.received_match_state.connect(_on_remote_match_state)


func _on_remote_match_state(match_state: NakamaRTAPI.MatchData) -> void:
	if match_state.op_code == NakamaManager.OpCodes.FIRE_WEAPON:
		var data: Dictionary = JSON.parse_string(match_state.data)
		if data == null or not "session_id" in data:
			return
			
		var sess_id = data["session_id"]
		if sess_id == NakamaManager.current_match.self_user.session_id:
			return # It's us, already fired locally
			
		var car: Car = _get_live_connected_car(sess_id)
		if car:
			var slot := int(data["slot"])
			if slot == 0 and car.primary_weapon:
				car.primary_weapon._do_fire()
			elif slot == 1 and car.secondary_weapon:
				car.secondary_weapon._do_fire()
					
	elif match_state.op_code == NakamaManager.OpCodes.DAMAGE_EVENT:
		var data: Dictionary = JSON.parse_string(match_state.data)
		if data == null or not "target" in data:
			return
			
		var target_id: String = str(data["target"])
		# Apply the damage to the target car on this client.
		# self_user check is NOT done here — every client applies damage to whatever
		# car was hit. The broadcaster already applied it locally before sending.
		# We skip only if we are the shooter (i.e. the sender) to avoid double-damage,
		# but since Nakama relayed messages are NOT echoed back to the sender we are safe.
		var car: Car = _get_live_connected_car(target_id)
		if car and car.has_node("DamageSystem"):
			car.get_node("DamageSystem")._apply_damage_internal(
				int(data["zone"]), float(data["amount"]))
				
	elif match_state.op_code == NakamaManager.OpCodes.ENV_DAMAGE:
		var data: Dictionary = JSON.parse_string(match_state.data)
		if data == null or not "id" in data:
			return
		
		# Prevent infinite loop if we already applied this locally
		# In a robust system we'd track sender, but for relayed simple state we just apply it.
		var node = get_node_or_null(data["id"])
		if node and node.has_method("_apply_damage_internal"):
			node._apply_damage_internal(data["amount"])
	
	elif match_state.op_code == NakamaManager.OpCodes.WEAPON_EQUIP:
		var data: Dictionary = JSON.parse_string(match_state.data)
		if data == null or not "session_id" in data:
			return
		
		var sess_id: String = data["session_id"]
		if sess_id == NakamaManager.current_match.self_user.session_id:
			return # Already equipped locally
		
		var weapon_idx := int(data["weapon_idx"])
		if weapon_idx >= 0 and weapon_idx < WEAPON_SCENES.size():
			var car: Car = _get_live_connected_car(sess_id)
			if car and car.has_method("equip_weapon"):
				var weapon = WEAPON_SCENES[weapon_idx].instantiate()
				car.equip_weapon(weapon)
	
	elif match_state.op_code == NakamaManager.OpCodes.PLAYER_DEATH:
		var data: Dictionary = JSON.parse_string(match_state.data)
		if data == null or not "session_id" in data:
			return
		
		var sess_id: String = data["session_id"]
		if sess_id == NakamaManager.current_match.self_user.session_id:
			return # Already handled locally
		
		var cause: String = data.get("cause", "destroyed")
		var car: Car = _get_live_connected_car(sess_id)
		if car:
			_eliminate_car(car, cause)


func _on_player_left(sess_id: String) -> void:
	var car: Car = _get_live_connected_car(sess_id)
	if car:
		_eliminate_car(car, "disconnected")
	connected_cars.erase(sess_id)


func _spawn_players() -> void:
	if spawn_points == null:
		return
	var points := spawn_points.get_children()
	if points.is_empty():
		return
	# For Phase 1: spawn 1 player car at first spawn point
	# Read chosen vehicle from NakamaManager if available
	var v_id = "sedan"
	if NakamaManager.current_match:
		var my_sess_id = NakamaManager.current_match.self_user.session_id
		if my_sess_id in NakamaManager.connected_players:
			v_id = NakamaManager.connected_players[my_sess_id].get("selected_vehicle", "sedan")
			
	var v_data = VehicleRegistry.get_by_id(v_id)
	var car_scene: PackedScene = load(v_data.scene_path)
	var car: Car = car_scene.instantiate()
	car.is_player = true
	cars_container.add_child(car)
	car.global_transform = points[0].global_transform
	car.car_destroyed.connect(_on_car_destroyed)
	car.car_stalled.connect(_on_car_stalled)
	alive_cars.append(car)

	# Connect HUD to this car
	if hud and hud.has_method("bind_car"):
		hud.bind_car(car)

	if top_down_camera and top_down_camera.has_method("set_target"):
		top_down_camera.set_target(car)

	# Equip starting weapon
	car.equip_weapon(WeaponScene.instantiate())
	car.equip_weapon(WeaponScene2.instantiate())

	if points.size() > 3:
		v_data = VehicleRegistry.get_by_id("ambulance")
		car_scene = load(v_data.scene_path)
		var dummy: Car = car_scene.instantiate()
		cars_container.add_child(dummy)
		dummy.global_transform = points[0].global_transform
		dummy.car_destroyed.connect(_on_car_destroyed)
		dummy.car_stalled.connect(_on_car_stalled)
		alive_cars.append(dummy)

func _on_car_destroyed(car: Car) -> void:
	_eliminate_car(car, "destroyed")


func _on_car_stalled(car: Car) -> void:
	_eliminate_car(car, "out of fuel")


func _eliminate_car(car: Car, cause: String) -> void:
	if not is_instance_valid(car):
		return
	if car.is_queued_for_deletion():
		return
	if not alive_cars.has(car):
		# Already eliminated on this client.
		return

	# Broadcast death to remote players if this is our local car
	if NakamaManager.current_match and car.is_player:
		var data = {
			"session_id": NakamaManager.current_match.self_user.session_id,
			"cause": cause
		}
		NakamaManager.send_match_state(NakamaManager.OpCodes.PLAYER_DEATH, JSON.stringify(data))
	
	alive_cars.erase(car)

	# Spawn wreck at car position
	var wreck: RigidBody3D = WreckScene.instantiate()
	wrecks_container.add_child(wreck)
	wreck.global_transform = car.global_transform
	wreck.linear_velocity = car.linear_velocity * 0.5

	# Log elimination
	var entry := {"victim": car.name, "killer": "", "cause": cause, "time": Time.get_ticks_msec()}
	kill_feed.append(entry)
	player_eliminated.emit(car.name, "")

	# Remove the car
	car.queue_free()

	# Remove stale network mapping for this car.
	if car.network_id != "":
		connected_cars.erase(car.network_id)

	# Check win condition
	if alive_cars.size() <= 1 and alive_cars.size() > 0:
		var winner: Car = alive_cars[0]
		match_ended.emit(winner.name)
	elif alive_cars.is_empty():
		match_ended.emit("Nobody")


func _get_live_connected_car(sess_id: String) -> Car:
	if not (sess_id in connected_cars):
		return null
	var car_value: Variant = connected_cars[sess_id]
	if not (car_value is Car):
		connected_cars.erase(sess_id)
		return null
	var car: Car = car_value
	if not is_instance_valid(car) or car.is_queued_for_deletion():
		connected_cars.erase(sess_id)
		return null
	return car


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if NakamaManager.current_match:
			NakamaManager.leave_match()
		get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
