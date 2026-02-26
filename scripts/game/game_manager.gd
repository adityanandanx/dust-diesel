extends Node3D

## Last Driver Standing game mode controller.
## Spawns cars, tracks eliminations, declares winner.

signal player_eliminated(player_name: String, killer_name: String)
signal match_ended(winner_name: String)

const CarScene := preload("res://scenes/vehicles/Car.tscn")
const WreckScene := preload("res://scenes/vehicles/CarWreck.tscn")
const WeaponScene := preload("res://scenes/weapons/ScrapCannon.tscn")
const WeaponScene2 := preload("res://scenes/weapons/MineLayer.tscn")

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

@onready var spawn_points: Node3D = $SpawnPoints
@onready var cars_container: Node3D = $Cars
@onready var wrecks_container: Node3D = $Wrecks
@onready var hud: Control = $HUDLayer/HUD

var alive_cars: Array[Car] = []
var kill_feed: Array[Dictionary] = [] # {victim, killer, cause, time}
var connected_cars: Dictionary = {}


func _ready() -> void:
	if NakamaManager.current_match:
		_spawn_networked_players()
	else:
		_spawn_players()


func _spawn_networked_players() -> void:
	var points := spawn_points.get_children()
	var index := 0
	
	# Sort session IDs so everyone assigns the same spawn logic
	var session_ids = NakamaManager.connected_players.keys()
	session_ids.sort()
	
	for sess_id in session_ids:
		var p_data: Dictionary = NakamaManager.connected_players[sess_id]
		var is_me = (sess_id == NakamaManager.current_match.self_user.session_id)
		
		var car: Car = CarScene.instantiate()
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
			
		if sess_id in connected_cars:
			var car: Car = connected_cars[sess_id]
			if is_instance_valid(car):
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
		if target_id in connected_cars:
			var car: Car = connected_cars[target_id]
			if is_instance_valid(car) and car.has_node("DamageSystem"):
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
		if sess_id in connected_cars and weapon_idx >= 0 and weapon_idx < WEAPON_SCENES.size():
			var car: Car = connected_cars[sess_id]
			if is_instance_valid(car) and car.has_method("equip_weapon"):
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
		if sess_id in connected_cars:
			var car: Car = connected_cars[sess_id]
			if is_instance_valid(car):
				_eliminate_car(car, cause)


func _on_player_left(sess_id: String) -> void:
	if sess_id in connected_cars:
		var car: Car = connected_cars[sess_id]
		if is_instance_valid(car):
			_eliminate_car(car, "disconnected")
		connected_cars.erase(sess_id)


func _spawn_players() -> void:
	var points := spawn_points.get_children()
	# For Phase 1: spawn 1 player car at first spawn point
	var car: Car = CarScene.instantiate()
	car.is_player = true
	cars_container.add_child(car)
	car.global_transform = points[0].global_transform
	car.car_destroyed.connect(_on_car_destroyed)
	car.car_stalled.connect(_on_car_stalled)
	alive_cars.append(car)

	# Connect HUD to this car
	if hud and hud.has_method("bind_car"):
		hud.bind_car(car)

	# Equip starting weapon
	car.equip_weapon(WeaponScene.instantiate())
	car.equip_weapon(WeaponScene2.instantiate())

	# Spawn a dummy target car for testing
	if points.size() > 3:
		var dummy: Car = CarScene.instantiate()
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

	# Check win condition
	if alive_cars.size() <= 1 and alive_cars.size() > 0:
		var winner: Car = alive_cars[0]
		match_ended.emit(winner.name)
	elif alive_cars.is_empty():
		match_ended.emit("Nobody")
