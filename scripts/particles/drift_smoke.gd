extends GPUParticles3D

## Drift smoke uses scene-authored particle materials.
## This script only modulates intensity at runtime.

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
	speed_scale = lerpf(0.4, 1.1, clamped)
	mat.scale_min = lerpf(_base_scale_min * 0.65, _base_scale_min, clamped)
	mat.scale_max = lerpf(_base_scale_max * 0.65, _base_scale_max, clamped)
