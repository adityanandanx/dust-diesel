extends GPUParticles3D

## Tire smoke uses scene-authored particle materials.
## This script only provides lightweight runtime controls.

var _base_scale_min: float = 1.0
var _base_scale_max: float = 1.0


func _ready() -> void:
	emitting = false
	var mat: ParticleProcessMaterial = process_material as ParticleProcessMaterial
	if mat:
		_base_scale_min = mat.scale_min
		_base_scale_max = mat.scale_max


func set_intensity(value: float) -> void:
	var mat: ParticleProcessMaterial = process_material as ParticleProcessMaterial
	if not mat:
		return
	var clamped: float = clampf(value, 0.0, 1.0)
	speed_scale = lerpf(0.35, 1.0, clamped)
	mat.scale_min = lerpf(_base_scale_min * 0.6, _base_scale_min, clamped)
	mat.scale_max = lerpf(_base_scale_max * 0.6, _base_scale_max, clamped)
