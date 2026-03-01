extends Area3D
class_name PickupBase

## Base pickup — Area3D trigger, bob animation, auto-despawn, apply on collect.

signal collected(car: Node)

@export var despawn_time: float = 30.0
@export var bob_height: float = 0.3
@export var bob_speed: float = 2.0
@export var spin_speed: float = 1.5
@export var pickup_effect_scene: PackedScene
@export var pickup_effect_color: Color = Color(1.0, 0.85, 0.2, 1.0)

var _age: float = 0.0
var _start_y: float = 0.0
var _is_collected: bool = false
var pickup_id: int = -1


func _ready() -> void:
	_start_y = global_position.y + 1.0 # float above ground
	global_position.y = _start_y
	body_entered.connect(_on_body_entered)
	collision_layer = 16 # pickup layer
	collision_mask = 1 # cars only


func _process(delta: float) -> void:
	if _is_collected:
		return
	_age += delta

	# Bob animation
	global_position.y = _start_y + sin(_age * bob_speed) * bob_height

	# Spin
	rotate_y(spin_speed * delta)

	# Auto-despawn
	if _age >= despawn_time:
		_deferred_cleanup()


func _on_body_entered(body: Node3D) -> void:
	if _is_collected:
		return
	if body is VehicleBody3D:
		# In singleplayer (no match), any car can pick up
		# In multiplayer, only the local player claims officially
		if NakamaManager.current_match and not body.is_player:
			return
		
		_is_collected = true
		apply(body)
		_spawn_pickup_effect()
		_emit_pickup_log(body)
		collected.emit(body)
		
		if NakamaManager.current_match:
			var data = {
				"id": pickup_id,
				"collector": body.name,
				"kind": _get_log_kind(),
				"detail": _get_log_detail(),
			}
			NakamaManager.send_match_state(NakamaManager.OpCodes.PICKUP_CLAIM, JSON.stringify(data))

		_deferred_cleanup()


## Override in subclasses to apply effect
func apply(_car: VehicleBody3D) -> void:
	pass


func _spawn_pickup_effect() -> void:
	if not pickup_effect_scene:
		return
	var fx: GPUParticles3D = pickup_effect_scene.instantiate()
	get_tree().current_scene.add_child(fx)
	fx.global_position = global_position
	if "particle_color" in fx:
		fx.particle_color = pickup_effect_color
	if fx.has_method("play"):
		fx.play()


func _get_log_kind() -> String:
	return "pickup"


func _get_log_detail() -> String:
	return name


func _emit_pickup_log(body: Node) -> void:
	var hud_nodes: Array = get_tree().get_nodes_in_group("hud_log_feed")
	if hud_nodes.is_empty():
		return

	var hud_node: Node = hud_nodes[0]
	if not hud_node.has_method("add_pickup_log"):
		return

	var collector_name: String = "Unknown"
	if body != null:
		collector_name = str(body.name)
	hud_node.add_pickup_log(collector_name, _get_log_kind(), _get_log_detail())


func _deferred_cleanup() -> void:
	if is_queued_for_deletion():
		return
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	call_deferred("queue_free")
