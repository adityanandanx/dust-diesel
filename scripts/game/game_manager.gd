extends Node3D

## Last Driver Standing game mode controller.
## Spawns cars, tracks eliminations, declares winner.

signal player_eliminated(player_name: String, killer_name: String)
signal match_ended(winner_name: String)

const WreckScene := preload("res://scenes/vehicles/CarWreck.tscn")
const DefaultSpawnPointsScene := preload("res://scenes/game/SpawnPoints.tscn")
const BotDriverScript := preload("res://scripts/car/bot_driver.gd")

@export_group("Respawn")
@export var respawn_enabled: bool = true
@export var respawn_delay_seconds: float = 5.0

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
@onready var pause_menu: PauseMenu = $HUDLayer/PauseMenu
@onready var top_down_camera: Camera3D = $TopDownCamera
@onready var pickup_spawner: Node3D = $PickupSpawner

var alive_cars: Array[Car] = []
var kill_feed: Array[Dictionary] = [] # {victim, killer, cause, time}
var player_kills: Dictionary = {} # stats_key -> kill_count
var player_kill_names: Dictionary = {} # stats_key -> display_name
var connected_cars: Dictionary = {}
var spawn_points: Node3D = null
var _active_map_root: Node3D = null
var _local_respawn_seq: int = 0
var _game_mode: String = "free_for_all"
var _match_time_seconds: int = 300
var _match_timer_running: bool = false
var _match_has_ended: bool = false
var _round_restart_in_progress: bool = false
var _waiting_for_host_restart: bool = false
var _processed_damage_event_ids: Dictionary = {}
var _respawn_seq_by_session: Dictionary = {}
var _applied_respawn_events: Dictionary = {}


func _is_multiplayer_session() -> bool:
	return NakamaManager.current_match != null


func _ready() -> void:
	if pause_menu:
		pause_menu.resume_requested.connect(_on_pause_resume_requested)
		pause_menu.main_menu_requested.connect(_on_pause_main_menu_requested)
	if hud:
		if hud.has_signal("match_end_restart_requested") and not hud.is_connected("match_end_restart_requested", Callable(self , "_on_match_end_restart_requested")):
			hud.connect("match_end_restart_requested", Callable(self , "_on_match_end_restart_requested"))
		if hud.has_signal("match_end_rejoin_requested") and not hud.is_connected("match_end_rejoin_requested", Callable(self , "_on_match_end_rejoin_requested")):
			hud.connect("match_end_rejoin_requested", Callable(self , "_on_match_end_rejoin_requested"))
		if hud.has_signal("match_end_back_to_menu_requested") and not hud.is_connected("match_end_back_to_menu_requested", Callable(self , "_on_match_end_back_to_menu_requested")):
			hud.connect("match_end_back_to_menu_requested", Callable(self , "_on_match_end_back_to_menu_requested"))
		if hud.has_signal("match_end_settings_changed") and not hud.is_connected("match_end_settings_changed", Callable(self , "_on_match_end_settings_changed")):
			hud.connect("match_end_settings_changed", Callable(self , "_on_match_end_settings_changed"))
	if not match_ended.is_connected(_on_match_ended):
		match_ended.connect(_on_match_ended)
	if NakamaManager.current_match and not NakamaManager.game_settings_updated.is_connected(_on_game_settings_updated):
		NakamaManager.game_settings_updated.connect(_on_game_settings_updated)
	_apply_game_settings()
	_load_selected_map()
	if NakamaManager.current_match:
		_spawn_networked_players()
	else:
		_spawn_players()
	_start_match_timer_if_needed()


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
		var is_bot: bool = bool(p_data.get("is_bot", false))
		var is_locally_owned: bool = is_me or (is_bot and NakamaManager.is_host)
		
		var v_id: String = p_data.get("selected_vehicle", "sedan")
		if is_bot:
			v_id = _pick_random_bot_vehicle_id(str(sess_id))
		var v_data = VehicleRegistry.get_by_id(v_id)
		var car_scene: PackedScene = load(v_data.scene_path)
		var car: Car = car_scene.instantiate()
		car.vehicle_data_id = v_id
		VehicleRegistry.apply_tuning(car, v_id)
		
		car.is_player = is_locally_owned
		car.uses_player_input = is_me
		car.is_bot = is_bot
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
		_ensure_player_kills_entry_for_car(car)
		
		_equip_random_starting_weapons(car, str(sess_id))
		if is_bot and NakamaManager.is_host:
			_attach_bot_driver(car)
		
		if is_me and hud and hud.has_method("bind_car"):
			hud.bind_car(car)
		if is_me and top_down_camera and top_down_camera.has_method("set_target"):
			top_down_camera.set_target(car)
			
	if not NakamaManager.player_joined.is_connected(_on_network_player_joined):
		NakamaManager.player_joined.connect(_on_network_player_joined)
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
		var event_id: String = str(data.get("event_id", ""))
		if not _should_apply_damage_event(event_id):
			return
			
		var target_id: String = str(data["target"])
		var attacker_session_id: String = str(data.get("attacker_session_id", ""))
		var attacker_name: String = str(data.get("attacker_name", ""))
		# Apply the damage to the target car on this client.
		# self_user check is NOT done here — every client applies damage to whatever
		# car was hit. The broadcaster already applied it locally before sending.
		# We skip only if we are the shooter (i.e. the sender) to avoid double-damage,
		# but since Nakama relayed messages are NOT echoed back to the sender we are safe.
		var car: Car = _get_live_connected_car(target_id)
		if car and car.has_node("DamageSystem"):
			car.get_node("DamageSystem")._apply_damage_internal(
				int(data["zone"]), float(data["amount"]), null, attacker_session_id, attacker_name)

	elif match_state.op_code == NakamaManager.OpCodes.PLAYER_RESPAWN:
		var data: Dictionary = JSON.parse_string(match_state.data)
		if data == null or not "session_id" in data:
			return
		_on_player_respawn_event(data)
				
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
		var killer_session_id: String = str(data.get("killer_session_id", ""))
		var killer_name: String = str(data.get("killer_name", ""))
		var car: Car = _get_live_connected_car(sess_id)
		if car:
			_eliminate_car(car, cause, killer_session_id, killer_name)
	
	elif match_state.op_code == NakamaManager.OpCodes.ROUND_RESTART:
		_restart_round_local()


func _on_player_left(sess_id: String) -> void:
	var car: Car = _get_live_connected_car(sess_id)
	if car:
		_eliminate_car(car, "disconnected")
	connected_cars.erase(sess_id)


func _on_network_player_joined(sess_id: String, _user_id: String, _username: String) -> void:
	if not NakamaManager.current_match:
		return
	if connected_cars.has(sess_id):
		return
	if not (sess_id in NakamaManager.connected_players):
		return

	var p_data: Dictionary = NakamaManager.connected_players[sess_id]
	var is_me: bool = (sess_id == NakamaManager.current_match.self_user.session_id)
	var is_bot: bool = bool(p_data.get("is_bot", false))
	var is_locally_owned: bool = is_me or (is_bot and NakamaManager.is_host)

	var v_id: String = p_data.get("selected_vehicle", "sedan")
	if is_bot:
		v_id = _pick_random_bot_vehicle_id(str(sess_id))
	var v_data = VehicleRegistry.get_by_id(v_id)
	var car_scene: PackedScene = load(v_data.scene_path)
	var car: Car = car_scene.instantiate()
	car.vehicle_data_id = v_id
	VehicleRegistry.apply_tuning(car, v_id)

	car.is_player = is_locally_owned
	car.uses_player_input = is_me
	car.is_bot = is_bot
	car.network_id = sess_id
	car.name = p_data.get("username", "Unknown")
	cars_container.add_child(car)

	var spawn_transform: Transform3D = Transform3D.IDENTITY
	var spawn_index: int = _get_spawn_index_for_session(sess_id)
	spawn_transform = _get_spawn_transform_for_index(spawn_index)
	car.global_transform = spawn_transform

	car.car_destroyed.connect(_on_car_destroyed)
	car.car_stalled.connect(_on_car_stalled)
	alive_cars.append(car)
	connected_cars[sess_id] = car
	_ensure_player_kills_entry_for_car(car)

	_equip_random_starting_weapons(car, str(sess_id))
	if is_bot and NakamaManager.is_host:
		_attach_bot_driver(car)

	if is_me and hud and hud.has_method("bind_car"):
		hud.bind_car(car)
	if is_me and top_down_camera and top_down_camera.has_method("set_target"):
		top_down_camera.set_target(car)


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
	car.vehicle_data_id = v_id
	VehicleRegistry.apply_tuning(car, v_id)
	car.is_player = true
	cars_container.add_child(car)
	car.global_transform = points[0].global_transform
	car.car_destroyed.connect(_on_car_destroyed)
	car.car_stalled.connect(_on_car_stalled)
	alive_cars.append(car)
	_ensure_player_kills_entry_for_car(car)

	# Connect HUD to this car
	if hud and hud.has_method("bind_car"):
		hud.bind_car(car)

	if top_down_camera and top_down_camera.has_method("set_target"):
		top_down_camera.set_target(car)

	# Equip random starting weapons.
	_equip_random_starting_weapons(car)

	if points.size() > 3:
		var dummy_vehicle_id: String = _pick_random_bot_vehicle_id()
		v_data = VehicleRegistry.get_by_id(dummy_vehicle_id)
		car_scene = load(v_data.scene_path)
		var dummy: Car = car_scene.instantiate()
		dummy.vehicle_data_id = dummy_vehicle_id
		VehicleRegistry.apply_tuning(dummy, dummy_vehicle_id)
		dummy.is_bot = true
		cars_container.add_child(dummy)
		dummy.global_transform = points[0].global_transform
		dummy.car_destroyed.connect(_on_car_destroyed)
		dummy.car_stalled.connect(_on_car_stalled)
		alive_cars.append(dummy)
		_ensure_player_kills_entry_for_car(dummy)
		_equip_random_starting_weapons(dummy)
		_attach_bot_driver(dummy)

func _on_car_destroyed(car: Car) -> void:
	if _match_has_ended:
		return
	_eliminate_car(car, "destroyed")


func _on_car_stalled(car: Car) -> void:
	if _match_has_ended:
		return
	_eliminate_car(car, "out of fuel")


func _eliminate_car(car: Car, cause: String, killer_session_id: String = "", killer_name: String = "") -> void:
	if _match_has_ended:
		return
	if not is_instance_valid(car):
		return
	if car.is_queued_for_deletion():
		return
	if not alive_cars.has(car):
		# Already eliminated on this client.
		return

	var resolved_killer_session_id: String = killer_session_id
	var resolved_killer_name: String = killer_name
	if cause == "destroyed" and resolved_killer_session_id == "" and resolved_killer_name == "":
		var killer_info: Dictionary = _resolve_recent_killer_info(car)
		resolved_killer_session_id = str(killer_info.get("session_id", ""))
		resolved_killer_name = str(killer_info.get("name", ""))
	elif cause != "destroyed":
		resolved_killer_session_id = ""
		resolved_killer_name = ""

	if resolved_killer_name == "" and resolved_killer_session_id != "":
		resolved_killer_name = _resolve_player_name_from_session(resolved_killer_session_id)

	if _is_same_player_as_victim(car, resolved_killer_session_id, resolved_killer_name):
		resolved_killer_session_id = ""
		resolved_killer_name = ""

	var killer_kill_total: int = -1
	if cause == "destroyed" and (resolved_killer_session_id != "" or resolved_killer_name != ""):
		killer_kill_total = _increment_player_kills(resolved_killer_session_id, resolved_killer_name)
		if resolved_killer_name == "":
			resolved_killer_name = _resolve_player_name_from_session(resolved_killer_session_id)

	var respawn_snapshot: Dictionary = _build_respawn_snapshot(car)

	# Broadcast death only for the locally controlled player car.
	if NakamaManager.current_match and car.uses_player_input:
		var data = {
			"session_id": NakamaManager.current_match.self_user.session_id,
			"cause": cause
		}
		if resolved_killer_session_id != "":
			data["killer_session_id"] = resolved_killer_session_id
		if resolved_killer_name != "":
			data["killer_name"] = resolved_killer_name
		NakamaManager.send_match_state(NakamaManager.OpCodes.PLAYER_DEATH, JSON.stringify(data))
	
	alive_cars.erase(car)

	# Spawn wreck at car position
	var wreck: RigidBody3D = WreckScene.instantiate()
	wrecks_container.add_child(wreck)
	wreck.global_transform = car.global_transform
	wreck.linear_velocity = car.linear_velocity * 0.5

	# Log elimination
	var entry := {"victim": car.name, "killer": resolved_killer_name, "cause": cause, "time": Time.get_ticks_msec()}
	kill_feed.append(entry)
	if hud:
		if hud.has_method("add_elimination_log"):
			hud.add_elimination_log(car.name, cause, resolved_killer_name)
		elif hud.has_method("add_kill_feed_entry"):
			if resolved_killer_name == "":
				hud.add_kill_feed_entry("[KILL] %s (%s)" % [car.name, cause])
			else:
				hud.add_kill_feed_entry("[KILL] %s -> %s (%s)" % [resolved_killer_name, car.name, cause])
		if killer_kill_total >= 0 and hud.has_method("add_log_entry"):
			hud.add_log_entry("[SCORE] %s: %d kills" % [resolved_killer_name, killer_kill_total], Color(0.75, 0.9, 1.0))
	player_eliminated.emit(car.name, resolved_killer_name)

	# Detach camera only if the eliminated car is the locally controlled one.
	if car.uses_player_input and top_down_camera and top_down_camera.has_method("set_target"):
		top_down_camera.set_target(null)
	if car.uses_player_input and hud and hud.has_method("bind_car"):
		hud.bind_car(null)

	# Remove the car
	car.queue_free()

	# Remove stale network mapping for this car.
	if car.network_id != "":
		connected_cars.erase(car.network_id)

	if respawn_enabled and cause != "disconnected":
		_schedule_respawn(respawn_snapshot)
		return

	# Check win condition when respawns are disabled.
	if alive_cars.size() <= 1 and alive_cars.size() > 0:
		var winner: Car = alive_cars[0]
		match_ended.emit(winner.name)
	elif alive_cars.is_empty():
		match_ended.emit("Nobody")


func _apply_game_settings() -> void:
	_game_mode = str(NakamaManager.selected_game_mode).to_lower()
	if _game_mode == "":
		_game_mode = "free_for_all"
	_match_time_seconds = clampi(int(NakamaManager.selected_match_time_seconds), 60, 3600)
	if _game_mode == "free_for_all":
		respawn_enabled = true


func _start_match_timer_if_needed() -> void:
	if _game_mode != "free_for_all":
		return
	if _match_timer_running:
		return
	_match_timer_running = true
	_run_match_timer()


func _run_match_timer() -> void:
	var remaining: int = _match_time_seconds
	while remaining >= 0 and not _match_has_ended:
		if hud and hud.has_method("show_match_timer"):
			hud.show_match_timer(remaining)
		await get_tree().create_timer(1.0).timeout
		remaining -= 1

	if _match_has_ended:
		return

	if hud and hud.has_method("hide_match_timer"):
		hud.hide_match_timer()
	_end_match_by_kills()


func _end_match_by_kills() -> void:
	if _match_has_ended:
		return
	_match_has_ended = true
	_match_timer_running = false
	respawn_enabled = false
	match_ended.emit(_resolve_winner_from_kills())


func _resolve_winner_from_kills() -> String:
	var best_kills: int = -1
	var leaders: Array[String] = []
	for key_variant in player_kills.keys():
		var key: String = str(key_variant)
		var kills: int = int(player_kills.get(key, 0))
		var player_name: String = str(player_kill_names.get(key, key))
		if kills > best_kills:
			best_kills = kills
			leaders.clear()
			leaders.append(player_name)
		elif kills == best_kills:
			leaders.append(player_name)

	if leaders.is_empty():
		return "Nobody"
	if leaders.size() == 1:
		return leaders[0]
	leaders.sort()
	return "Tie (%d kills): %s" % [best_kills, ", ".join(leaders)]


func _on_match_ended(winner_name: String) -> void:
	_match_has_ended = true
	_match_timer_running = false
	respawn_enabled = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if top_down_camera:
		top_down_camera.set("mouse_capture_enabled", false)
	_freeze_match_entities()
	if hud and hud.has_method("show_match_results"):
		hud.show_match_results(winner_name, get_kill_counts())
	if hud and hud.has_method("configure_match_end_menu"):
		hud.configure_match_end_menu(NakamaManager.is_host, NakamaManager.get_game_settings())
	if hud and hud.has_method("set_match_end_waiting"):
		hud.set_match_end_waiting(false, NakamaManager.is_host)
	if hud and hud.has_method("add_log_entry"):
		hud.add_log_entry("[MATCH] Time up. Winner: %s" % winner_name, Color(0.98, 0.95, 0.62))
	if hud and hud.has_method("hide_respawn_countdown"):
		hud.hide_respawn_countdown()
	if hud and hud.has_method("hide_match_timer"):
		hud.hide_match_timer()


func _on_match_end_restart_requested() -> void:
	if not _match_has_ended:
		return
	if not NakamaManager.is_host:
		return
	_restart_match_for_all()


func _on_match_end_rejoin_requested() -> void:
	if not _match_has_ended:
		return
	if NakamaManager.is_host:
		return
	_waiting_for_host_restart = true
	if hud and hud.has_method("set_match_end_waiting"):
		hud.set_match_end_waiting(true, false)
	if hud and hud.has_method("add_log_entry"):
		hud.add_log_entry("[MATCH] Waiting for host restart...", Color(0.88, 0.9, 1.0))


func _on_match_end_back_to_menu_requested() -> void:
	_on_pause_main_menu_requested()


func _on_match_end_settings_changed(game_mode: String, match_time_seconds: int, map_id: String, bot_count: int) -> void:
	if not NakamaManager.is_host:
		return
	NakamaManager.set_game_settings(game_mode, match_time_seconds, map_id, bot_count, true)
	_apply_game_settings()


func _on_game_settings_updated(settings: Dictionary) -> void:
	_game_mode = str(settings.get("game_mode", "free_for_all")).to_lower()
	_match_time_seconds = clampi(int(settings.get("match_time_seconds", 300)), 60, 3600)
	if _match_has_ended and hud and hud.has_method("configure_match_end_menu"):
		hud.configure_match_end_menu(NakamaManager.is_host, settings)
	if _match_has_ended and hud and hud.has_method("set_match_end_waiting"):
		hud.set_match_end_waiting(_waiting_for_host_restart, NakamaManager.is_host)


func _restart_match_for_all() -> void:
	if _round_restart_in_progress:
		return
	_round_restart_in_progress = true

	var bot_entries: Array[Dictionary] = _build_bot_roster_from_settings()
	NakamaManager.sync_bot_roster(bot_entries)
	if NakamaManager.current_match:
		NakamaManager.send_match_state(NakamaManager.OpCodes.ROUND_RESTART, JSON.stringify({
			"at": Time.get_ticks_msec()
		}))
	_restart_round_local(true)


func _restart_round_local(force: bool = false) -> void:
	if _round_restart_in_progress and not force:
		return
	_round_restart_in_progress = true
	get_tree().paused = false
	_waiting_for_host_restart = false
	if hud and hud.has_method("hide_match_results"):
		hud.hide_match_results()
	get_tree().change_scene_to_file("res://scenes/game/Game.tscn")


func _freeze_match_entities() -> void:
	for child in cars_container.get_children():
		if child is Car:
			_freeze_car(child as Car)
	for child in wrecks_container.get_children():
		if child is RigidBody3D:
			var body: RigidBody3D = child as RigidBody3D
			body.freeze = true
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
	if pickup_spawner:
		pickup_spawner.set_process(false)
		pickup_spawner.set_physics_process(false)


func _freeze_car(car: Car) -> void:
	if car == null:
		return
	car.is_alive = false
	car.is_player = false
	car.uses_player_input = false
	car.engine_force = 0.0
	car.brake = car.max_brake_force
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.freeze = true
	var bot_driver: Node = car.get_node_or_null("BotDriver")
	if bot_driver:
		bot_driver.set_process(false)
		bot_driver.set_physics_process(false)


func _build_bot_roster_from_settings() -> Array[Dictionary]:
	var bots: Array[Dictionary] = []
	for i in range(NakamaManager.selected_bot_count):
		var bot_id: String = "bot_%d" % [i + 1]
		bots.append({
			"session_id": bot_id,
			"user_id": bot_id,
			"username": "BOT %d" % [i + 1],
			"selected_vehicle": "sedan",
		})
	return bots


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


func get_kill_counts() -> Dictionary:
	var kills_by_player: Dictionary = {}
	for key_variant in player_kills.keys():
		var key: String = str(key_variant)
		var count: int = int(player_kills.get(key, 0))
		var player_name: String = str(player_kill_names.get(key, key))
		kills_by_player[key] = {
			"name": player_name,
			"kills": count,
		}
	return kills_by_player


func _resolve_recent_killer_info(victim: Car) -> Dictionary:
	if victim == null:
		return {}
	if not victim.has_method("get_recent_attacker_info"):
		return {}
	var info: Dictionary = victim.get_recent_attacker_info()
	var session_id: String = str(info.get("session_id", ""))
	var attacker_name: String = str(info.get("name", ""))
	if session_id == "" and attacker_name == "":
		return {}
	if attacker_name == "" and session_id != "":
		attacker_name = _resolve_player_name_from_session(session_id)
	return {
		"session_id": session_id,
		"name": attacker_name,
	}


func _is_same_player_as_victim(victim: Car, killer_session_id: String, killer_name: String) -> bool:
	if victim == null:
		return false
	if killer_session_id != "" and victim.network_id != "" and killer_session_id == victim.network_id:
		return true
	if killer_session_id == "" and victim.network_id == "" and killer_name != "" and killer_name == victim.name:
		return true
	return false


func _ensure_player_kills_entry_for_car(car: Car) -> void:
	if car == null:
		return
	var stats_key: String = _make_player_stats_key(car.network_id, car.name)
	if stats_key == "":
		return
	if not player_kills.has(stats_key):
		player_kills[stats_key] = 0
	player_kill_names[stats_key] = car.name


func _increment_player_kills(session_id: String, player_name: String) -> int:
	var resolved_name: String = player_name
	if resolved_name == "" and session_id != "":
		resolved_name = _resolve_player_name_from_session(session_id)
	var stats_key: String = _make_player_stats_key(session_id, resolved_name)
	if stats_key == "":
		return -1
	var current_kills: int = int(player_kills.get(stats_key, 0)) + 1
	player_kills[stats_key] = current_kills
	if resolved_name != "":
		player_kill_names[stats_key] = resolved_name
	return current_kills


func _make_player_stats_key(session_id: String, player_name: String) -> String:
	if session_id != "":
		return "session:%s" % session_id
	if player_name != "":
		return "name:%s" % player_name
	return ""


func _resolve_player_name_from_session(session_id: String) -> String:
	if session_id == "":
		return ""
	var live_car: Car = _get_live_connected_car(session_id)
	if live_car:
		return live_car.name
	if session_id in NakamaManager.connected_players:
		var player_data: Dictionary = NakamaManager.connected_players[session_id]
		var username: String = str(player_data.get("username", ""))
		if username != "":
			return username
	var stats_key: String = _make_player_stats_key(session_id, "")
	if player_kill_names.has(stats_key):
		return str(player_kill_names[stats_key])
	return ""


func _attach_bot_driver(car: Car) -> void:
	if car == null:
		return
	if car.get_node_or_null("BotDriver") != null:
		return
	var bot_driver := Node.new()
	bot_driver.name = "BotDriver"
	bot_driver.set_script(BotDriverScript)
	car.add_child(bot_driver)


func _build_respawn_snapshot(car: Car) -> Dictionary:
	return {
		"vehicle_data_id": car.vehicle_data_id,
		"name": car.name,
		"network_id": car.network_id,
		"is_player": car.is_player,
		"uses_player_input": car.uses_player_input,
		"is_bot": car.is_bot,
	}


func _schedule_respawn(snapshot: Dictionary) -> void:
	if _match_has_ended:
		return
	if not _can_schedule_local_respawn(snapshot):
		return
	var session_id: String = str(snapshot.get("network_id", ""))
	var seq: int = _next_respawn_seq_for_session(session_id)
	if bool(snapshot.get("uses_player_input", false)):
		_local_respawn_seq = seq
	_respawn_after_delay(snapshot, seq)


func _respawn_after_delay(snapshot: Dictionary, respawn_seq: int) -> void:
	if _match_has_ended:
		return
	var local_player_respawn: bool = bool(snapshot.get("uses_player_input", false))
	var countdown: int = maxi(1, int(ceil(respawn_delay_seconds)))

	while countdown > 0:
		if _match_has_ended:
			return
		if local_player_respawn and respawn_seq == _local_respawn_seq and hud and hud.has_method("show_respawn_countdown"):
			hud.show_respawn_countdown(countdown)
		await get_tree().create_timer(1.0).timeout
		countdown -= 1

	if not is_inside_tree():
		return
	if _match_has_ended:
		return

	if local_player_respawn and respawn_seq == _local_respawn_seq and hud and hud.has_method("hide_respawn_countdown"):
		hud.hide_respawn_countdown()

	_announce_and_apply_respawn(snapshot, respawn_seq)


func _announce_and_apply_respawn(snapshot: Dictionary, respawn_seq: int) -> void:
	var session_id: String = str(snapshot.get("network_id", ""))
	var payload := {
		"session_id": session_id,
		"vehicle_id": str(snapshot.get("vehicle_data_id", "sedan")),
		"name": str(snapshot.get("name", "Unknown")),
		"is_player": bool(snapshot.get("is_player", false)),
		"uses_player_input": bool(snapshot.get("uses_player_input", false)),
		"is_bot": bool(snapshot.get("is_bot", false)),
		"respawn_seq": respawn_seq,
		"spawn_index": _get_respawn_spawn_index(session_id, respawn_seq),
	}
	_on_player_respawn_event(payload)
	if NakamaManager.current_match:
		NakamaManager.send_match_state(NakamaManager.OpCodes.PLAYER_RESPAWN, JSON.stringify(payload))


func _on_player_respawn_event(payload: Dictionary) -> void:
	var session_id: String = str(payload.get("session_id", ""))
	var respawn_seq: int = int(payload.get("respawn_seq", -1))
	if session_id == "" or respawn_seq < 0:
		return
	var event_key: String = "%s:%d" % [session_id, respawn_seq]
	if _applied_respawn_events.has(event_key):
		return
	_applied_respawn_events[event_key] = Time.get_ticks_msec()

	var existing: Car = _get_live_connected_car(session_id)
	if existing:
		return

	_respawn_car(payload)


func _respawn_car(snapshot: Dictionary) -> void:
	if _match_has_ended:
		return
	var vehicle_id: String = str(snapshot.get("vehicle_id", "sedan"))
	if vehicle_id == "":
		vehicle_id = str(snapshot.get("vehicle_data_id", "sedan"))
	var vehicle_data: Variant = VehicleRegistry.get_by_id(vehicle_id)
	var scene_path: String = ""
	if vehicle_data != null and "scene_path" in vehicle_data:
		scene_path = str(vehicle_data.scene_path)
	if scene_path == "":
		vehicle_id = "sedan"
		vehicle_data = VehicleRegistry.get_by_id(vehicle_id)
		if vehicle_data != null and "scene_path" in vehicle_data:
			scene_path = str(vehicle_data.scene_path)
		if scene_path == "":
			scene_path = "res://scenes/vehicles/cars/Sedan.tscn"

	var car_scene: PackedScene = load(scene_path)
	if car_scene == null:
		return

	var car: Car = car_scene.instantiate()
	car.vehicle_data_id = vehicle_id
	VehicleRegistry.apply_tuning(car, vehicle_id)

	car.is_player = bool(snapshot.get("is_player", false))
	car.uses_player_input = bool(snapshot.get("uses_player_input", false))
	car.is_bot = bool(snapshot.get("is_bot", false))
	car.network_id = str(snapshot.get("session_id", ""))
	if car.network_id == "":
		car.network_id = str(snapshot.get("network_id", ""))
	car.name = str(snapshot.get("name", "Unknown"))

	cars_container.add_child(car)
	var spawn_index: int = int(snapshot.get("spawn_index", -1))
	if spawn_index < 0:
		spawn_index = _get_respawn_spawn_index(car.network_id, int(snapshot.get("respawn_seq", 0)))
	car.global_transform = _get_spawn_transform_for_index(spawn_index)

	car.car_destroyed.connect(_on_car_destroyed)
	car.car_stalled.connect(_on_car_stalled)
	alive_cars.append(car)
	_ensure_player_kills_entry_for_car(car)

	if car.network_id != "":
		connected_cars[car.network_id] = car

	var weapon_seed: String = car.network_id
	_equip_random_starting_weapons(car, weapon_seed)
	if car.is_bot and NakamaManager.is_host:
		_attach_bot_driver(car)

	if car.uses_player_input:
		if hud and hud.has_method("bind_car"):
			hud.bind_car(car)
		if top_down_camera and top_down_camera.has_method("set_target"):
			top_down_camera.set_target(car)


func _pick_respawn_transform() -> Transform3D:
	return _get_spawn_transform_for_index(_get_respawn_spawn_index("", 0))


func _get_spawn_transform_for_index(index: int) -> Transform3D:
	if spawn_points and spawn_points.get_child_count() > 0:
		var safe_index: int = posmod(index, spawn_points.get_child_count())
		var marker: Node3D = spawn_points.get_child(safe_index) as Node3D
		if marker:
			return marker.global_transform
	return Transform3D.IDENTITY


func _get_spawn_index_for_session(session_id: String) -> int:
	if spawn_points == null or spawn_points.get_child_count() <= 0:
		return 0
	var session_ids: Array = NakamaManager.connected_players.keys()
	session_ids.sort()
	var session_pos: int = session_ids.find(session_id)
	if session_pos >= 0:
		return session_pos % spawn_points.get_child_count()
	if session_id == "":
		return 0
	return absi(hash(session_id)) % spawn_points.get_child_count()


func _get_respawn_spawn_index(session_id: String, respawn_seq: int) -> int:
	if spawn_points == null or spawn_points.get_child_count() <= 0:
		return 0
	var key: String = "%s:%d" % [session_id, respawn_seq]
	return absi(hash(key)) % spawn_points.get_child_count()


func _can_schedule_local_respawn(snapshot: Dictionary) -> bool:
	if not NakamaManager.current_match:
		return true
	if bool(snapshot.get("uses_player_input", false)):
		return true
	if bool(snapshot.get("is_bot", false)) and NakamaManager.is_host:
		return true
	return false


func _next_respawn_seq_for_session(session_id: String) -> int:
	var key: String = session_id if session_id != "" else "local"
	var next_seq: int = int(_respawn_seq_by_session.get(key, 0)) + 1
	_respawn_seq_by_session[key] = next_seq
	return next_seq


func _should_apply_damage_event(event_id: String) -> bool:
	if event_id == "":
		return true
	if _processed_damage_event_ids.has(event_id):
		return false
	_processed_damage_event_ids[event_id] = Time.get_ticks_msec()
	if _processed_damage_event_ids.size() > 512:
		var now_ms: int = Time.get_ticks_msec()
		for key in _processed_damage_event_ids.keys():
			if now_ms - int(_processed_damage_event_ids[key]) > 15000:
				_processed_damage_event_ids.erase(key)
	return true


func _pick_random_bot_vehicle_id(seed_key: String = "") -> String:
	var vehicles: Array = VehicleRegistry.get_all()
	if vehicles.is_empty():
		return "sedan"

	var idx: int = 0
	if seed_key != "":
		idx = absi(hash(seed_key)) % vehicles.size()
	else:
		idx = randi() % vehicles.size()

	var data: Variant = vehicles[idx]
	if data is VehicleData:
		var vehicle_data: VehicleData = data as VehicleData
		if vehicle_data.id != "":
			return vehicle_data.id
	return "sedan"


func _equip_random_starting_weapons(car: Car, seed_key: String = "") -> void:
	if car == null:
		return

	var primary_paths: PackedStringArray = [
		"res://scenes/weapons/RivetCannon.tscn",
		"res://scenes/weapons/ScrapCannon.tscn",
		"res://scenes/weapons/FlameProjector.tscn",
		"res://scenes/weapons/HarpoonLauncher.tscn",
	]
	var secondary_paths: PackedStringArray = [
		"res://scenes/weapons/OilSlick.tscn",
		"res://scenes/weapons/MineLayer.tscn",
		"res://scenes/weapons/EMPBlaster.tscn",
	]

	var primary_candidates: Array[int] = []
	var secondary_candidates: Array[int] = []
	for i in range(WEAPON_SCENES.size()):
		var scene_path: String = WEAPON_SCENES[i].resource_path
		if primary_paths.has(scene_path):
			primary_candidates.append(i)
		elif secondary_paths.has(scene_path):
			secondary_candidates.append(i)

	if not primary_candidates.is_empty():
		var p_idx: int = _pick_seeded_index(primary_candidates, "%s:primary" % seed_key)
		car.equip_weapon(WEAPON_SCENES[p_idx].instantiate())
	if not secondary_candidates.is_empty():
		var s_idx: int = _pick_seeded_index(secondary_candidates, "%s:secondary" % seed_key)
		car.equip_weapon(WEAPON_SCENES[s_idx].instantiate())


func _pick_seeded_index(candidates: Array[int], seed_key: String = "") -> int:
	if candidates.is_empty():
		return 0
	if seed_key == "":
		return candidates[randi() % candidates.size()]
	var idx: int = absi(hash(seed_key)) % candidates.size()
	return candidates[idx]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if pause_menu and pause_menu.visible:
			_on_pause_resume_requested()
		else:
			if _is_multiplayer_session():
				_open_multiplayer_menu()
			else:
				_open_pause_menu()


func _open_pause_menu() -> void:
	if pause_menu == null:
		return
	pause_menu.configure_for_multiplayer(false)
	get_tree().paused = true
	pause_menu.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _open_multiplayer_menu() -> void:
	if pause_menu == null:
		return
	pause_menu.configure_for_multiplayer(true)
	get_tree().paused = false
	pause_menu.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _on_pause_resume_requested() -> void:
	get_tree().paused = false
	if pause_menu:
		pause_menu.visible = false
	if _match_has_ended:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return
	if top_down_camera and top_down_camera.get("mouse_capture_enabled"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _on_pause_main_menu_requested() -> void:
	get_tree().paused = false
	if pause_menu:
		pause_menu.visible = false
	if NakamaManager.current_match:
		NakamaManager.leave_match()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
