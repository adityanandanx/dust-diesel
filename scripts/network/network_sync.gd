extends Node

## Synchronizes Car position, rotation, and inputs over the network via Nakama.

@export var sync_rate: float = 15.0 # Hz
var _sync_timer: float = 0.0

@onready var car: VehicleBody3D = get_parent()

# Interpolation targets for remote cars
var target_pos: Vector3
var target_rot: Quaternion
var target_vel: Vector3
var target_steering: float = 0.0


func _ready() -> void:
	if not car is VehicleBody3D:
		set_physics_process(false)
		return
		
	target_pos = car.global_position
	target_rot = car.global_transform.basis.get_rotation_quaternion()
	target_vel = Vector3.ZERO
	
	if NakamaManager.current_match:
		NakamaManager.socket.received_match_state.connect(_on_match_state)


func _physics_process(delta: float) -> void:
	if not NakamaManager.current_match:
		return
		
	if car.is_player:
		# We own this car, broadcast our state
		_sync_timer += delta
		if _sync_timer >= 1.0 / sync_rate:
			_sync_timer = 0.0
			_send_sync_packet()
	else:
		# We don't own this car — steer via physics so collisions still work
		var pos_diff := target_pos - car.global_position
		# If too far away (>10m), snap to avoid huge desync
		if pos_diff.length() > 10.0:
			car.global_position = target_pos
			car.linear_velocity = target_vel
		else:
			# Drive toward target via velocity (physics-friendly)
			car.linear_velocity = pos_diff * 10.0 + target_vel * 0.3
		
		# Slerp rotation
		var current_rot := car.global_transform.basis.get_rotation_quaternion().normalized()
		var new_rot := current_rot.slerp(target_rot, clampf(delta * 10.0, 0.0, 1.0))
		car.global_transform.basis = Basis(new_rot)
		
		car.steering = lerp(car.steering, target_steering, clampf(delta * 10.0, 0.0, 1.0))
		
		# Prevent physics rotation from fighting
		car.angular_velocity = Vector3.ZERO


func _send_sync_packet() -> void:
	var quat := car.global_transform.basis.get_rotation_quaternion()
	var state = {
		"session_id": NakamaManager.current_match.self_user.session_id,
		"px": snappedf(car.global_position.x, 0.01),
		"py": snappedf(car.global_position.y, 0.01),
		"pz": snappedf(car.global_position.z, 0.01),
		"rw": snappedf(quat.w, 0.001),
		"rx": snappedf(quat.x, 0.001),
		"ry": snappedf(quat.y, 0.001),
		"rz": snappedf(quat.z, 0.001),
		"vx": snappedf(car.linear_velocity.x, 0.01),
		"vy": snappedf(car.linear_velocity.y, 0.01),
		"vz": snappedf(car.linear_velocity.z, 0.01),
		"st": snappedf(car.steering, 0.01),
		"spd": snappedf(car.current_speed_kmh, 1.0),
		"boost": snappedf(car.boost_meter, 1.0),
	}
	# Stats for debug label sync
	var dmg = car.get_node_or_null("DamageSystem")
	if dmg:
		state["ehp"] = snappedf(dmg.engine_hp, 1.0)
		state["chp"] = snappedf(dmg.chassis_hp, 1.0)
		state["whp"] = snappedf(dmg.weapon_mount_hp, 1.0)
		state["wlhp"] = snappedf(dmg.wheel_hp[0], 1.0)
	var fuel = car.get_node_or_null("FuelSystem")
	if fuel and "fuel" in fuel:
		state["fuel"] = snappedf(fuel.fuel, 1.0)
	NakamaManager.send_match_state(NakamaManager.OpCodes.POSITION_SYNC, JSON.stringify(state))


func _on_match_state(match_state: NakamaRTAPI.MatchData) -> void:
	if car.is_player or match_state.op_code != NakamaManager.OpCodes.POSITION_SYNC:
		return
		
	var data: Dictionary = JSON.parse_string(match_state.data)
	if data == null or not "session_id" in data:
		return
		
	# Only apply if it's meant for this remote car
	if data["session_id"] != car.network_id:
		return
		
	target_pos = Vector3(data["px"], data["py"], data["pz"])
	target_rot = Quaternion(data["rx"], data["ry"], data["rz"], data["rw"]).normalized()
	target_vel = Vector3(data["vx"], data["vy"], data["vz"])
	target_steering = data["st"]
	
	# Apply stats so debug label works for remote cars
	car.current_speed_kmh = float(data.get("spd", 0.0))
	car.boost_meter = float(data.get("boost", 0.0))
	var dmg = car.get_node_or_null("DamageSystem")
	if dmg and "ehp" in data:
		dmg.engine_hp = float(data["ehp"])
		dmg.chassis_hp = float(data["chp"])
		dmg.weapon_mount_hp = float(data["whp"])
		if "wlhp" in data:
			for i in range(4):
				dmg.wheel_hp[i] = float(data["wlhp"])
	var fuel = car.get_node_or_null("FuelSystem")
	if fuel and "fuel" in data:
		fuel.fuel = float(data["fuel"])
