extends GPUParticles3D

## Pickup sparkle uses scene-authored particle resources.
## Call play() to emit once.

@export var auto_free: bool = true


func _ready() -> void:
	emitting = false


func play() -> void:
	restart()
	emitting = true
	if auto_free:
		get_tree().create_timer(lifetime + 0.3).timeout.connect(queue_free)
