extends Node3D

## Loads and attaches 3D car body + wheel models at runtime.

var _body_instance: Node3D = null


func load_model(vehicle_data) -> void:
	# --- Clear old model ---
	for child in get_children():
		child.queue_free()

	var car: VehicleBody3D = get_parent()

	# --- Body ---
	var body_scene: PackedScene = load(vehicle_data.model_path)
	if body_scene:
		_body_instance = body_scene.instantiate()
		add_child(_body_instance)
		# GLB models from the asset pack are oriented with +Z forward.
		# VehicleBody3D also uses +Z forward, so no rotation needed.
		# Center vertically: shift down so wheels sit at the axle height.
		_body_instance.position = Vector3.ZERO
	else:
		printerr("VehicleModelLoader: failed to load body: ", vehicle_data.model_path)

	# --- Wheels ---
	_apply_wheel_model(vehicle_data.wheel_path, car.get_node_or_null("FrontLeft/WheelMesh"))
	_apply_wheel_model(vehicle_data.wheel_path, car.get_node_or_null("FrontRight/WheelMesh"))
	_apply_wheel_model(vehicle_data.wheel_path, car.get_node_or_null("RearLeft/WheelMesh"))
	_apply_wheel_model(vehicle_data.wheel_path, car.get_node_or_null("RearRight/WheelMesh"))


func _apply_wheel_model(wheel_path: String, wheel_mesh_node: Node) -> void:
	if not wheel_mesh_node:
		return
	# Remove the old MeshInstance3D content
	if wheel_mesh_node is MeshInstance3D:
		wheel_mesh_node.mesh = null
	# Remove any previous loaded wheel model children
	for child in wheel_mesh_node.get_children():
		child.queue_free()
	# Load and attach the new wheel model
	var wheel_scene: PackedScene = load(wheel_path)
	if wheel_scene:
		var instance := wheel_scene.instantiate()
		# Reset the cylinder rotation — GLB wheels should be correctly oriented
		wheel_mesh_node.transform = Transform3D.IDENTITY
		wheel_mesh_node.add_child(instance)
	else:
		printerr("VehicleModelLoader: failed to load wheel: ", wheel_path)
