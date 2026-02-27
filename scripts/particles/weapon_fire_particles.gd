extends GPUParticles3D

## Weapon muzzle flash particles. Lightweight one-shot burst used for firing feedback.

@export var auto_free: bool = true


func _ready() -> void:
	emitting = false


func emit_at(pos: Vector3, forward: Vector3 = Vector3.FORWARD) -> void:
	global_position = pos
	var dir: Vector3 = forward.normalized()
	if dir.length_squared() <= 0.0001:
		dir = Vector3.FORWARD

	look_at(global_position + dir, Vector3.UP)
	restart()
	emitting = true

	if auto_free:
		get_tree().create_timer(lifetime + 0.15).timeout.connect(queue_free)
